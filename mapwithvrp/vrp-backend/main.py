# =============================================================================
# 🧭 Teryaq VRP Backend (FastAPI) - COMPLETE VERSION
# =============================================================================
# ✅ Features
# - PostgreSQL integration (Hospitals, Patients, Orders)
# - Exports valid Solomon C102 instances
# - Runs HGS solver (Hybrid Genetic Search)
# - Integrates OSRM for accurate travel time
# - Multi-Trip Merge (capacity + 8h shift)
# - Driver endpoints for mobile app
# - Stability monitoring endpoints
# =============================================================================

import os, math, tempfile, json, requests, logging
from typing import Dict, List, Tuple
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from fastapi import FastAPI, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime

# Import solver
from hgs.solve import solve_with_hgs

# Configure logging FIRST
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | backend | %(message)s",
)
logger = logging.getLogger("backend")

# -----------------------------------------------------------------------------
# ⚙️ Config
# -----------------------------------------------------------------------------
SOL_NUM_VEH = 20
SOL_VEH_CAP = 15
DEPOT_ID = 0
SHIFT_LIMIT_SEC = 8 * 3600          # 8h = 28800 s
FALLBACK_SPEED_MPS = 16.67          # 60 km/h

DEFAULT_HOSPITAL_ID = os.getenv("HOSPITAL_ID", "7e57056b-ffe1-4a4c-b1ac-5429efcef902")

OSRM_BASE_URL    = os.getenv("OSRM_BASE_URL", "http://osrm:5000")
OSRM_PROFILE     = os.getenv("OSRM_PROFILE", "driving")
# 🔵 Increase timeout so OSRM has a real chance before we fallback
OSRM_TIMEOUT_SEC = float(os.getenv("OSRM_TIMEOUT_SEC", "30"))
OSRM_RETRIES     = int(os.getenv("OSRM_RETRIES", "1"))


# -----------------------------------------------------------------------------
# 🗄️ Database Setup
# -----------------------------------------------------------------------------
def get_engine() -> Engine:
    load_dotenv()
    user = os.getenv("DB_USER", "postgres")
    pwd  = os.getenv("DB_PASSWORD", "mysecretpassword")
    host = os.getenv("DB_HOST", "postgres")
    port = os.getenv("DB_PORT", "5432")
    db   = os.getenv("DB_NAME", "med_delivery")

    # Allow local host override
    if os.getenv("RUN_LOCAL", "false").lower() == "true":
        host = "host.docker.internal"

    uri = f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}"
    logger.info("✅ Connecting to DB %s at %s:%s as %s", db, host, port, user)
    return create_engine(uri, pool_pre_ping=True)

engine = get_engine()

# -----------------------------------------------------------------------------
# 🚀 FastAPI App Creation
# -----------------------------------------------------------------------------
app = FastAPI(
    title="Teryaq VRP Backend",
    version="3.2 (Complete with Driver Routes)",
    description="Medication delivery routing and driver management system"
)

# -----------------------------------------------------------------------------
# 🌐 CORS Middleware
# -----------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For production, restrict to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------------------------------------------------------
# 📦 Import and Include Routers
# -----------------------------------------------------------------------------

# Import stability router
try:
    from stability_router import router as stability_router
    app.include_router(stability_router, prefix="/stability", tags=["stability"])
    logger.info("✅ Stability router included at /stability/*")
except ImportError as e:
    logger.error(f"❌ Failed to import stability_router: {e}")

# Import driver router
try:
    from driver_router import router as driver_router
    app.include_router(driver_router, prefix="/driver", tags=["driver"])
    logger.info("✅ Driver router included at /driver/*")
except ImportError as e:
    logger.error(f"❌ Failed to import driver_router: {e}")
    logger.error("⚠️  Driver routes will NOT be available!")

# -----------------------------------------------------------------------------
# 🏥 Root Endpoints
# -----------------------------------------------------------------------------

@app.get("/")
def root():
    """Root endpoint"""
    return {
        "message": "Teryaq VRP Backend API",
        "status": "running",
        "version": "3.2",
        "endpoints": {
            "docs": "/docs",
            "health": "/health",
            "debug": "/debug/routes",
            "hgs": "/hgs",
            "driver": "/driver/*",
            "stability": "/stability/*"
        }
    }

@app.get("/health")
def health():
    """Health check with database connectivity test"""
    try:
        with engine.connect() as c:
            c.execute(text("SELECT 1"))
        return {
            "status": "ok",
            "db": "connected",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            "status": "error",
            "db_error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

@app.get("/debug/routes")
def list_routes():
    """List all registered routes for debugging"""
    routes = []
    for route in app.routes:
        if hasattr(route, 'methods') and hasattr(route, 'path'):
            routes.append({
                "path": route.path,
                "methods": list(route.methods),
                "name": getattr(route, 'name', 'unknown')
            })
    return {
        "total_routes": len(routes),
        "routes": routes
    }

# -----------------------------------------------------------------------------
# ⏱️ Time Formatting Helpers
# -----------------------------------------------------------------------------

def interval_to_minutes(val) -> int:
    """Convert Postgres INTERVAL or 'HH:MM:SS' string to integer minutes"""
    if val is None:
        return 0
    try:
        # datetime.timedelta
        if hasattr(val, "total_seconds"):
            return int(val.total_seconds() // 60)
        # 'HH:MM:SS' string
        h, m, *_ = map(int, str(val).split(":"))
        return h * 60 + m
    except Exception:
        return 0

def format_hm(total_minutes: int) -> str:
    """Format minutes as 'Xh Ym' for Flutter card"""
    try:
        total_minutes = int(total_minutes)
    except Exception:
        return "0h 0m"
    h = total_minutes // 60
    m = total_minutes % 60
    return f"{h}h {m}m"

# -----------------------------------------------------------------------------
# 🏥 Hospital (Depot) Data
# -----------------------------------------------------------------------------

def get_hospital_data(hid: str):
    """Fetch hospital data by ID"""
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT hospital_id, name, address, lat, lon FROM hospital WHERE hospital_id = :hid"),
            {"hid": hid},
        ).fetchone()

    if not row:
        raise ValueError(f"Hospital {hid} not found in DB")

    _, name, addr, lat, lon = row
    if lat is None or lon is None:
        raise ValueError(f"🏥 Hospital '{name}' missing coordinates")

    return {
        "id": hid,
        "name": name,
        "address": addr,
        "lat": float(lat),
        "lon": float(lon)
    }

# -----------------------------------------------------------------------------
# 👥 Patients Data
# -----------------------------------------------------------------------------

def get_patients_data():
    """Fetch all patients with demand and due date"""
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT 
                p.patient_id, p.name, p.address, p.lat, p.lon,
                (SELECT COUNT(*) FROM "Order" o WHERE o.patient_id = p.patient_id) AS demand,
                (
                    SELECT ed.delay_time
                    FROM estimated_delivery_time ed
                    JOIN "Order" o2 ON ed.dashboard_id = o2.dashboard_id
                    WHERE o2.patient_id = p.patient_id
                    ORDER BY ed.recorded_at DESC
                    LIMIT 1
                ) AS due_date
            FROM patient p
        """)).fetchall()

    pts, i = [], 1
    for pid, name, addr, lat, lon, demand, due_date in rows:
        if lat is None or lon is None:
            logger.warning("⚠️ Skipping %s (no coords)", name)
            continue

        due_val = 9999
        if due_date:
            try:
                if hasattr(due_date, "total_seconds"):
                    due_val = int(due_date.total_seconds() // 60)
                else:
                    h, m, *_ = map(int, str(due_date).split(":"))
                    due_val = h * 60 + m
            except Exception:
                due_val = 9999

        pts.append({
            "cust_no": i,
            "id": pid,
            "name": name,
            "lat": float(lat),
            "lon": float(lon),
            "demand": int(demand) if demand and int(demand) > 0 else 1,
            "due_date": due_val,
        })
        i += 1

    logger.info("👥 Loaded %d patients", len(pts))
    return pts

# -----------------------------------------------------------------------------
# 🚚 Driver Today's Deliveries
# -----------------------------------------------------------------------------

def get_driver_todays_deliveries(driver_id: str):
    """
    Returns today's deliveries for a driver with:
    - cust_no: 1..N (node index used by HGS)
    - order_id, patient_id, name, lat, lon
    - demand: fixed = 1
    - due_date: medication.max_time_exertion in MINUTES (stability time)
    """
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT
                o.order_id,
                p.patient_id,
                p.name,
                p.lat,
                p.lon,
                m.max_time_exertion
            FROM "Order" o
            JOIN Patient p       ON o.patient_id       = p.patient_id
            JOIN Prescription pr ON o.prescription_id  = pr.prescription_id
            JOIN Medication m    ON pr.medication_id   = m.medication_id
            WHERE o.driver_id = :did
              AND o.status IN ('on_delivery', 'accepted', 'assigned', 'in_progress', 'on_route')

            ORDER BY o.created_at ASC
        """), {"did": driver_id}).fetchall()

    pts = []
    cust_no = 1

    for order_id, patient_id, name, lat, lon, max_time in rows:
        if lat is None or lon is None:
            continue

        # Convert INTERVAL max_time_exertion -> minutes
        if max_time is not None:
            try:
                if hasattr(max_time, "total_seconds"):
                    due_min = int(max_time.total_seconds() // 60)
                else:
                    h, m, *_ = map(int, str(max_time).split(":"))
                    due_min = h * 60 + m
            except Exception:
                due_min = 9999
        else:
            due_min = 9999

        pts.append({
            "cust_no": cust_no,
            "order_id": str(order_id),
            "patient_id": str(patient_id),
            "name": name,
            "lat": float(lat),
            "lon": float(lon),
            "demand": 1,
            "due_date": due_min
        })
        cust_no += 1

    return pts

# -----------------------------------------------------------------------------
# 📄 Export Solomon C102 Format
# -----------------------------------------------------------------------------

def export_c102_from_db(
    hospital_id=DEFAULT_HOSPITAL_ID,
    scale=1000,
    veh_num=SOL_NUM_VEH,
    veh_cap=SOL_VEH_CAP
):
    """Export global instance in Solomon C102 format"""
    depot = get_hospital_data(hospital_id)
    dx, dy = int(depot["lon"] * scale), int(depot["lat"] * scale)

    lines = [
        "C102",
        "",
        "VEHICLE",
        "NUMBER     CAPACITY",
        f"{veh_num:5d}{veh_cap:11d}",
        "",
        "CUSTOMER",
        "CUST NO.   XCOORD.    YCOORD.   DEMAND   READY TIME   DUE DATE  SERVICE TIME",
    ]

    lines.append(f"{0:7d}{dx:11d}{dy:11d}{0:9d}{0:13d}{9999:11d}{0:14d}")

    patients = get_patients_data()

    for p in patients:
        x = int(p["lon"] * scale)
        y = int(p["lat"] * scale)
        demand = p.get("demand", 1)
        due = p.get("due_date", 9999)
        lines.append(
            f"{p['cust_no']:7d}{x:11d}{y:11d}{demand:9d}{0:13d}{due:11d}{0:14d}"
        )

    txt = "\n".join(lines).strip() + "\n"
    logger.info("📦 Exported valid C102 with %d customers", len(patients))
    return txt

def export_driver_c102(depot, pts, veh_num=SOL_NUM_VEH, veh_cap=SOL_VEH_CAP, scale=1000):
    """Export driver-specific instance in Solomon C102 format"""
    dx, dy = int(depot["lon"] * scale), int(depot["lat"] * scale)

    lines = [
        "C102",
        "",
        "VEHICLE",
        "NUMBER     CAPACITY",
        f"{veh_num:5d}{veh_cap:11d}",
        "",
        "CUSTOMER",
        "CUST NO.   XCOORD.    YCOORD.   DEMAND   READY TIME   DUE DATE  SERVICE TIME",
    ]

    # Depot row
    lines.append(f"{0:7d}{dx:11d}{dy:11d}{0:9d}{0:13d}{9999:11d}{0:14d}")

    # Customers
    for p in pts:
        x = int(p["lon"] * scale)
        y = int(p["lat"] * scale)
        demand = int(p.get("demand", 1))
        due    = int(p.get("due_date", 9999))

        lines.append(
            f"{p['cust_no']:7d}{x:11d}{y:11d}{demand:9d}{0:13d}{due:11d}{0:14d}"
        )

    txt = "\n".join(lines).strip() + "\n"
    logger.info("📦 Exported DRIVER C102 with %d customers", len(pts))
    return txt

# -----------------------------------------------------------------------------
# 📏 Haversine Distance
# -----------------------------------------------------------------------------

def haversine_m(lat1, lon1, lat2, lon2):
    """Calculate distance between two points using Haversine formula"""
    R = 6371000.0
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ, dλ = math.radians(lat2-lat1), math.radians(lon2-lon1)
    a = math.sin(dφ/2)**2 + math.cos(φ1)*math.cos(φ2)*math.sin(dλ/2)**2
    return 2 * R * math.asin(math.sqrt(a))

# -----------------------------------------------------------------------------
# 🧭 OSRM Client
# -----------------------------------------------------------------------------

class OSRMClient:
    """Client for OSRM routing service"""
    def __init__(self, coords: Dict[int, Tuple[float, float]]):
        self.coords: Dict[int, Tuple[float, float]] = coords
        self.cache: Dict[Tuple[int, int], Tuple[float, float]] = {}
        # 🔵 Edges where we had to use fallback (no OSRM answer)
        self.fallback_edges: set[Tuple[int, int]] = set()

    def _pick_cell(self, mat):
        if isinstance(mat, list) and mat:
            if isinstance(mat[0], list) and len(mat[0]) >= 2:
                return mat[0][1]
            if not isinstance(mat[0], list):
                return mat[0]
        return None

    def get_edge(self, u: int, v: int) -> Tuple[float, float]:
        """
        Returns (distance_m, duration_s) between nodes u and v.
        Uses OSRM table API; if that fails or times out, falls back
        to Haversine distance at 60 km/h.
        """
        if (u, v) in self.cache:
            return self.cache[(u, v)]

        lat1, lon1 = self.coords[u]
        lat2, lon2 = self.coords[v]
        url = (
            f"{OSRM_BASE_URL}/table/v1/{OSRM_PROFILE}/"
            f"{lon1},{lat1};{lon2},{lat2}?annotations=duration,distance"
        )

        try:
            r = requests.get(url, timeout=OSRM_TIMEOUT_SEC)
            if r.ok:
                data = r.json()
                dist = data.get("distances")
                dur = data.get("durations")

                d = self._pick_cell(dist)
                t = self._pick_cell(dur)

                if d is None or t is None:
                    raise ValueError("Bad OSRM response (missing matrix cells)")

                # OSRM response = meters, seconds
                self.cache[(u, v)] = (d, t)
                return d, t

            raise ValueError(f"OSRM HTTP {r.status_code}: {r.text[:200]}")
        except Exception as e:
            logger.warning("⚠️ OSRM timeout/fallback for %s->%s: %s", u, v, e)

        # 🔁 Fallback: straight-line distance at 60 km/h
        d = haversine_m(lat1, lon1, lat2, lon2)
        t = d / FALLBACK_SPEED_MPS
        self.fallback_edges.add((u, v))

        logger.info(
            "🧮 Fallback %s->%s: d=%.1f m, t=%.1f s (%.1f min)",
            u, v, d, t, t / 60.0,
        )

        self.cache[(u, v)] = (d, t)
        return d, t

# -----------------------------------------------------------------------------
# 🧩 Build Nodes and OSRM Client
# -----------------------------------------------------------------------------

def build_nodes_and_client(depot, patients):
    """Build coordinate map, demand, and due time"""
    coords = {0: (depot["lat"], depot["lon"])}
    demand = {0: 0}
    due    = {0: 10**9}

    for p in patients:
        n = p["cust_no"]
        coords[n] = (p["lat"], p["lon"])
        demand[n] = int(p.get("demand", 1))
        due[n] = int(p.get("due_date", 9999))

    return coords, demand, due, OSRMClient(coords)

# -----------------------------------------------------------------------------
# 🚚 Multi-Trip Management
# -----------------------------------------------------------------------------

def split_into_trips(route, cap, demand):
    """Split route into trips based on capacity"""
    trips, cur, load = [], [], 0
    for c in route:
        d = demand.get(c,0)
        if cur and load + d > cap:
            trips.append((cur,load))
            cur,load=[],0
        cur.append(c)
        load += d
    if cur:
        trips.append((cur,load))
    return trips

def validate_multitrip(route, cap, demand, due, osrm: OSRMClient):
    """
    Validate a multi-trip route with:
    - Capacity per trip
    - Due time per customer (in minutes since leaving depot)
    - BUT: we do NOT reject on due if the leg used OSRM fallback.
      (fallback is only a rough estimate; for presentations we trust real OSRM.)
    """
    trips = split_into_trips(route, cap, demand)
    total_t = 0.0  # seconds
    expanded: List[int] = []

    for i, (trip, load) in enumerate(trips, 1):
        clk = 0.0  # seconds since leaving depot for THIS trip
        full = [0] + trip + [0]

        logger.info("🧭 Trip %d: %s (load=%d/%d)", i, trip, load, cap)

        # Stitch trips into one global path with depot between them
        expanded.extend(full if not expanded else full[1:])

        for u, v in zip(full, full[1:]):
            _, t = osrm.get_edge(u, v)
            clk += t

            # Minutes from depot for THIS trip
            eta_min = clk / 60.0
            is_fallback = hasattr(osrm, "fallback_edges") and (u, v) in osrm.fallback_edges

            if v != 0:
                node_due = due.get(v, 9999)

                # 🔴 If REAL OSRM → enforce due strictly
                # 🔵 If FALLBACK → log warning but do NOT reject the route
                if eta_min > node_due:
                    msg = (
                        "⛔ Late at %s ETA %.1f > due %s (fallback=%s)"
                        % (v, eta_min, node_due, is_fallback)
                    )
                    logger.warning(msg)

                    if not is_fallback:
                        # Only reject if this was a real OSRM-based ETA
                        return False, [], []

        total_t += clk
        logger.info("⏱️ Trip %d = %.1f min", i, clk / 60.0)

    logger.info("🕒 Shift = %.2f h", total_t / 3600.0)

    if total_t > SHIFT_LIMIT_SEC:
        logger.warning(
            "⛔ Shift exceeds limit: %.2f h > %.2f h",
            total_t / 3600.0,
            SHIFT_LIMIT_SEC / 3600.0,
        )
        return False, [], []

    return True, expanded, [n for n in expanded if n != 0]

    

def combine_and_validate_multitrip(routes, cap, demand, due, osrm):
    """Combine and validate multiple routes"""
    raw=[r for r in routes if r]
    merged=True
    
    while merged:
        merged=False
        for i in range(len(raw)):
            for j in range(i+1,len(raw)):
                cand=raw[i]+raw[j]
                ok,_,rw=validate_multitrip(cand,cap,demand,due,osrm)
                if ok:
                    logger.info("✅ Merge %d+%d → %s", i, j, rw)
                    raw.pop(j)
                    raw.pop(i)
                    raw.append(rw)
                    merged=True
                    break
            if merged:
                break

    final=[]
    for r in raw:
        ok,exp,_=validate_multitrip(r,cap,demand,due,osrm)
        if ok:
            final.append(exp)

    logger.info("🏁 Merging: %d → %d", len(routes), len(final))
    return final

# -----------------------------------------------------------------------------
# 📊 Route Metrics
# -----------------------------------------------------------------------------

def summarize_route(osrm, nodes):
    """Calculate route metrics"""
    dist=time=0.0
    for u,v in zip(nodes,nodes[1:]):
        d,t=osrm.get_edge(u,v)
        dist+=d
        time+=t
    return {
        "nodes":nodes,
        "distance_km": round(dist/1000,2),
        "duration_h": round(time/3600,2),
        "within_shift": time <= SHIFT_LIMIT_SEC
    }

# -----------------------------------------------------------------------------
# 🧠 MAIN HGS ENDPOINT
# -----------------------------------------------------------------------------

@app.get("/hgs")
def run_hgs(
    runtime: int = 20,
    hospital_id: str = Query(default=DEFAULT_HOSPITAL_ID),
    multi_merge: bool = True,
):
    """Run HGS solver for all patients"""
    try:
        logger.info("🚀 Run HGS solver")
        
        sol_txt = export_c102_from_db(hospital_id)
        logger.info("========== C102 INPUT BEGIN ==========")
        for line in sol_txt.split("\n"):
            logger.info(line)
        logger.info("========== C102 INPUT END   ==========")

        with tempfile.NamedTemporaryFile(delete=False, suffix=".txt") as f:
            f.write(sol_txt.encode("utf-8"))
            sol_file = f.name

        routes, cost = solve_with_hgs(sol_file, runtime)
        logger.info("========== RAW HGS OUTPUT ==========")
        logger.info("Cost from solver = %s", cost)
        for idx, r in enumerate(routes, start=1):
            logger.info("Route %d: %s", idx, r)
        logger.info("====================================")

        logger.info("✅ Solver: %d routes, cost=%s", len(routes), cost)

        depot = get_hospital_data(hospital_id)
        pts = get_patients_data()

        coords, demand, due, osrm = build_nodes_and_client(depot, pts)

        validated = []
        for r in routes:
            ok, exp, _ = validate_multitrip(r, SOL_VEH_CAP, demand, due, osrm)
            if ok:
                validated.append(exp)
            else:
                trips = split_into_trips(r, SOL_VEH_CAP, demand)
                for t_i, (trip_nodes, _) in enumerate(trips, 1):
                    validated.append([0] + trip_nodes + [0])

        merged = (
            combine_and_validate_multitrip(routes, SOL_VEH_CAP, demand, due, osrm)
            if multi_merge
            else validated
        )

        id_to_meta = {
            0: {
                "name": depot["name"],
                "id": depot["id"],
                "type": "hospital",
            }
        }

        for p in pts:
            id_to_meta[p["cust_no"]] = {
                "name": p["name"],
                "id": p["id"],
                "type": "patient",
            }

        geo = []
        for path in merged:
            seg = []
            for n in path:
                lat, lon = coords[n]
                seg.append({
                    "lat": lat,
                    "lon": lon,
                    "name": id_to_meta[n]["name"],
                    "id": id_to_meta[n]["id"],
                    "type": id_to_meta[n]["type"],
                })
            geo.append(seg)


        logger.info("========== GEO ROUTES ==========")
        for idx, g in enumerate(geo, start=1):
            logger.info("Route %d:", idx)
            for point in g:
                logger.info("  %s", point)
        logger.info("================================")


        metrics = [summarize_route(osrm, p) for p in merged]

        # JSON-safe cost
        safe_cost = cost
        if isinstance(safe_cost, float) and not math.isfinite(safe_cost):
            logger.warning("⚠️ HGS cost is non-finite (%s), sending null", safe_cost)
            safe_cost = None

        return {
            "algorithm": "HGS",
            "num_routes": len(merged),
            "cost": safe_cost,
            "routes": geo,
            "metrics": metrics,
        }

    except Exception as e:
        logger.exception("❌ Run HGS failed")
        return {"error": str(e)}

# -----------------------------------------------------------------------------
# 🧠 DRIVER HGS ENDPOINT
# -----------------------------------------------------------------------------
@app.get("/driver/hgs")
def run_driver_hgs(
    driver_id: str,
    runtime: int = 20,
    multi_merge: bool = True,
):
    """Run HGS solver for specific driver's deliveries"""
    try:
        logger.info(f"🚀 Run HGS for driver {driver_id}")

        # --------------------------------------------------
        # 1) Find driver's hospital (depot)
        # --------------------------------------------------
        with engine.connect() as conn:
            row = conn.execute(
                text("""
                    SELECT d.hospital_id, h.name, h.address, h.lat, h.lon
                    FROM Driver d
                    JOIN Hospital h ON d.hospital_id = h.hospital_id
                    WHERE d.driver_id = :did
                """),
                {"did": driver_id},
            ).fetchone()

        if not row:
            return {"error": "Driver not found"}

        hospital_id, hname, haddr, hlat, hlon = row
        depot = {
            "id": hospital_id,
            "name": hname,
            "address": haddr,
            "lat": float(hlat),
            "lon": float(hlon),
        }

        # --------------------------------------------------
        # 2) Today's active deliveries
        # --------------------------------------------------
        pts = get_driver_todays_deliveries(driver_id)
        if not pts:
            return {
                "driver_id": driver_id,
                "routes": [],
                "geo": [],
                "message": "No deliveries today",
            }

        # --------------------------------------------------
        # 3) Build Solomon instance + run HGS
        # --------------------------------------------------
        sol_txt = export_driver_c102(depot, pts)
        logger.info("========== DRIVER C102 INPUT ==========")
        for line in sol_txt.split("\n"):
            logger.info(line)
        logger.info("=======================================")

        with tempfile.NamedTemporaryFile(delete=False, suffix=".txt") as f:
            f.write(sol_txt.encode("utf-8"))
            sol_file = f.name

        routes, cost = solve_with_hgs(sol_file, runtime)
        logger.info(f"✅ Driver HGS produced {len(routes)} raw routes")
        logger.info("========== RAW DRIVER HGS OUTPUT ==========")
        logger.info("Cost = %s", cost)
        for idx, r in enumerate(routes, start=1):
            logger.info("Route %d: %s", idx, r)
        logger.info("===========================================")


        # --------------------------------------------------
        # 4) Build routing context
        # --------------------------------------------------
        coords, demand, due, osrm = build_nodes_and_client(depot, pts)

        # Try merging multi-trips (capacity + shift)
                # Try merging multi-trips (capacity + shift)
        merged_routes = combine_and_validate_multitrip(
            routes, SOL_VEH_CAP, demand, due, osrm
        )

        logger.info("========== MERGED ROUTES (FINAL) ==========")
        for idx, m in enumerate(merged_routes, start=1):
            logger.info("Merged Route %d: %s", idx, m)
        logger.info("============================================")

        if merged_routes:
            routes = merged_routes


        # Normalize each route to [0, ..., 0] form
        normalized_routes = []
        for r in routes:
            # r is just customer sequence like [3,5,7]
            path = [0] + r + [0]
            normalized_routes.append(path)

        # --------------------------------------------------
        # 5) Compute legs (distance + segment ETA + cumulative ETA)
        # --------------------------------------------------
        final_routes = []
        eta_by_order: Dict[str, int] = {}
        eta_cumulative_by_order: Dict[str, int] = {}

        # node -> (kind, order_id, name)
        meta_by_node = {
            0: {
                "kind": "hospital",
                "order_id": None,
                "name": depot["name"],
            }
        }
        for p in pts:
            meta_by_node[p["cust_no"]] = {
                "kind": "patient",
                "order_id": p["order_id"],
                "name": p["name"],
            }

        cumulative_global_min = 0  # across all routes (if you want one big sequence)

        geo_routes = []
        hgs_order_sequence: List[str] = []

        for path in normalized_routes:
            legs = []
            cumulative = 0.0  # seconds within this route

            # Build ETA legs
            for u, v in zip(path, path[1:]):
                dist, t = osrm.get_edge(u, v)
                cumulative += t

                # Node meta for arrival node
                meta_v = meta_by_node.get(v, {})
                order_id_v = meta_v.get("order_id")

                segment_min = round(t / 60.0)
                cum_min = round(cumulative / 60.0)

                legs.append({
                    "from": u,
                    "to": v,
                    "distance_m": round(dist, 2),
                    "segment_eta_min": segment_min,
                    "cumulative_eta_min": cum_min,
                })

                # Collect ETA only for patient nodes
                if order_id_v:
                    oid = str(order_id_v)
                    # HGS order sequence
                    if oid not in hgs_order_sequence:
                        hgs_order_sequence.append(oid)

                    # Per-stop ETA (segment)
                    # we keep the first segment to that order
                    if oid not in eta_by_order:
                        eta_by_order[oid] = segment_min

                    # Cumulative ETA for that stop (from depot)
                    if oid not in eta_cumulative_by_order:
                        eta_cumulative_by_order[oid] = cum_min + cumulative_global_min

            # After finishing route, increase global cumulative
            cumulative_global_min += round(cumulative / 60.0)

            final_routes.append({
                "path": path,
                "legs": legs,
            })

            # GEO for map
            geo_path = []
            for node in path:
                lat, lon = coords[node]
                meta = meta_by_node.get(node, {})
                geo_path.append({
                    "node": node,
                    "lat": lat,
                    "lon": lon,
                    "kind": meta.get("kind"),
                    "order_id": meta.get("order_id"),
                    "name": meta.get("name"),
                })
            geo_routes.append(geo_path)

        # JSON-safe cost
        safe_cost = cost
        if isinstance(safe_cost, float) and not math.isfinite(safe_cost):
            logger.warning("⚠️ Driver HGS cost is non-finite (%s)", safe_cost)
            safe_cost = None

        # Debug logs for you in console
        logger.info("🧭 HGS order sequence = %s", hgs_order_sequence)
        logger.info("⏱️ ETA by order       = %s", eta_by_order)
        logger.info("⏱️ ETA cumulative    = %s", eta_cumulative_by_order)

        return {
            "driver_id": driver_id,
            "algorithm": "Driver-HGS",
            "num_deliveries": len(pts),
            "routes": final_routes,
            "geo": geo_routes,
            "cost": safe_cost,
            "debug": {
                "hgs_order": hgs_order_sequence,
                "eta_by_order": eta_by_order,
                "eta_cumulative_by_order": eta_cumulative_by_order,
            },
        }

    except Exception as e:
        logger.exception("❌ Driver HGS failed")
        return {"error": str(e)}


# -----------------------------------------------------------------------------
# 🚚 DRIVER TODAY ORDERS WITH ETA
# -----------------------------------------------------------------------------

@app.get("/driver/today-orders")
def driver_today_orders(driver_id: str):
    """
    Returns today's orders for a driver with ETA and stability info
    """
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text("""
                    SELECT
                        o.order_id,
                        o.status,
                        o.created_at,
                        h.name       AS hospital_name,
                        h.lat        AS hlat,
                        h.lon        AS hlon,
                        p.address    AS patient_address,
                        p.lat        AS plat,
                        p.lon        AS plon,

                        m.max_time_exertion
                    FROM "Order" o
                    JOIN Hospital     h  ON o.hospital_id     = h.hospital_id
                    JOIN Patient      p  ON o.patient_id      = p.patient_id
                    JOIN Prescription pr ON o.prescription_id = pr.prescription_id
                    JOIN Medication   m  ON pr.medication_id  = m.medication_id
                    WHERE
                        o.driver_id = :did
                        AND DATE(o.created_at) = CURRENT_DATE
                        AND o.status IN ('on_delivery', 'accepted', 'assigned', 'in_progress', 'on_route')

                    ORDER BY o.created_at ASC
                    """
                ),
                {"did": driver_id},
            ).mappings().all()

        if not rows:
            return []

        orders = []

        for r in rows:
            order_id = str(r["order_id"])
            hlat = float(r["hlat"])
            hlon = float(r["hlon"])
            plat = float(r["plat"])
            plon = float(r["plon"])

            # ---- ETA (minutes) using OSRM table API ----
            eta_min = 0
            try:
                coords = {
                    0: (hlat, hlon),
                    1: (plat, plon),
                }
                osrm = OSRMClient(coords)
                _, dur = osrm.get_edge(0, 1)  # seconds
                eta_min = int(round(dur / 60.0))
            except Exception as e:
                logger.warning("⚠️ ETA OSRM failed for order %s: %s", order_id, e)
                eta_min = 0

            # ---- Max excursion time (minutes) from Medication.max_time_exertion ----
            max_exc_minutes = interval_to_minutes(r["max_time_exertion"])

            orders.append(
                {
                    "order_id": order_id,
                    "hospital_name": r["hospital_name"],
                    "patient_address": r["patient_address"],
                    "orders_count": 1,

                    # 🔢 Numeric fields (for new Flutter logic)
                    "eta_minutes": eta_min,
                    "max_excursion_minutes": max_exc_minutes,

                    # 🔤 String fields for existing UI (2h 30m, 1h 20m, ...)
                    "arrival_time": format_hm(eta_min),
                    "remaining_stability": format_hm(max_exc_minutes),
                }
            )

        return orders

    except Exception as e:
        logger.exception("❌ driver_today_orders failed")
        return {"error": str(e)}
@app.on_event("startup")
async def startup_event():
    print("\n" + "="*60)
    print("📋 REGISTERED ROUTES:")
    print("="*60)
    for route in app.routes:
        if hasattr(route, 'methods') and hasattr(route, 'path'):
            methods = ', '.join(route.methods)
            print(f"{methods:8} {route.path}")
    print("="*60 + "\n")
    
    # Check specifically for the reject endpoint
    reject_routes = [r for r in app.routes if hasattr(r, 'path') and 'reject' in r.path]
    if reject_routes:
        print("✅ Reject endpoint found!")
    else:
        print("❌ WARNING: Reject endpoint NOT found!")
    print()