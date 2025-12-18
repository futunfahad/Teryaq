# ==========================================================
# ✅ SEED SCRIPT (Riyadh Demo) — Medications mimic output2.csv
#
# - NO hardcoded Mac path in code.
# - If CSV exists inside container -> use it exactly (Product Name as card label).
# - If CSV missing -> generate synthetic meds that mimic output2 schema and continue.
#
# Optional env:
#   TEMP_SENSITIVE_CSV=/app/data/output2.csv
#   SYNTH_MEDS_COUNT=120
# ==========================================================

import os, time, uuid, random, re, csv, json
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional

import psycopg2
from faker import Faker

# ==========================================================
# 1) PostgreSQL Connection
# ==========================================================

DB_HOST = os.getenv("POSTGRES_HOST", "postgres")
DB_USER = os.getenv("POSTGRES_USER", "postgres")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "mysecretpassword")
DB_NAME = os.getenv("POSTGRES_DB", "med_delivery")
DB_PORT = os.getenv("POSTGRES_PORT", "5432")

SYNTH_MEDS_COUNT = int(os.getenv("SYNTH_MEDS_COUNT", "120"))

print(f"🔌 Connecting to DB at {DB_HOST}:{DB_PORT} (DB={DB_NAME})")

conn = None
for _ in range(10):
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            host=DB_HOST,
            port=DB_PORT,
        )
        print("✅ Connected to PostgreSQL!")
        break
    except Exception as e:
        print("⏳ Waiting for DB:", e)
        time.sleep(3)

if conn is None:
    raise RuntimeError("❌ Could not connect to database.")

cur = conn.cursor()

# ==========================================================
# 2) Wait for ALL Required Tables (before truncate)
# ==========================================================

REQUIRED_TABLES = [
    "hospital",
    "patient",
    "driver",
    "medication",
    "hospital_medication",
    "prescription",
    "dashboard",
    "gps",
    "temperature",
    "estimated_delivery_time",
    "estimated_stability_time",
    "\"Order\"",
    "notification",
    "report",
    "requests",
    "staging_incoming_data",
    "production_table",
]

def table_exists(table_name: str) -> bool:
    cur.execute("SELECT to_regclass(%s);", (table_name,))
    return cur.fetchone()[0] is not None

print("⏳ Waiting for all required tables to be created...")

for attempt in range(60):
    missing = [t for t in REQUIRED_TABLES if not table_exists(t)]
    if not missing:
        print("✅ All tables exist! Continuing with seeding...")
        break
    print(f"⏳ Still waiting... Missing tables: {missing}")
    time.sleep(2)
else:
    raise RuntimeError(f"❌ Timed out waiting for tables: {missing}")

# ==========================================================
# 0) CLEAR ALL EXISTING DATA (safe truncate)
# ==========================================================

print("🧹 Clearing existing data...")

TABLES_TO_TRUNCATE = [
    "\"Order\"",
    "patient",
    "driver",
    "hospital",
    "medication",
    "hospital_medication",
    "prescription",
    "dashboard",
    "gps",
    "temperature",
    "estimated_delivery_time",
    "estimated_stability_time",
    "notification",
    "report",
    "requests",
    "staging_incoming_data",
    "production_table",
]

existing = [t for t in TABLES_TO_TRUNCATE if table_exists(t)]
if existing:
    sql = "TRUNCATE TABLE " + ", ".join(existing) + " RESTART IDENTITY CASCADE;"
    cur.execute(sql)
    conn.commit()
else:
    print("⚠️ No tables found to truncate (unexpected). Continuing...")

# ==========================================================
# 3) Utilities
# ==========================================================

fake = Faker("en_US")
random.seed(42)

def gen_uuid() -> str:
    return str(uuid.uuid4())

def phone_sa() -> str:
    return f"+9665{random.randint(10000000, 99999999)}"

def safe_str(s: str, n: int) -> str:
    return (s or "")[:n]

# Reserve login hospital ID so it never duplicates
generated_national_ids = {"2181241943"}

def gen_national_id_10() -> str:
    while True:
        nid = f"{random.randint(10**9, (10**10) - 1)}"
        if nid not in generated_national_ids:
            generated_national_ids.add(nid)
            return nid

# ------------------ Riyadh Data ------------------

RIYADH_HOSPITALS = [
    ("King Fahad Medical City", "King Fahad Road, Al Olaya, Riyadh", 24.6893, 46.6860),
    ("King Saud Medical City", "Al Imam Abdulaziz Road, Al Suwaidi, Riyadh", 24.6311, 46.7133),
    ("King Khalid University Hospital", "King Saud University, Riyadh", 24.7176, 46.6204),
    ("Security Forces Hospital", "King Abdulaziz Road, Ar Rahmaniyah, Riyadh", 24.7098, 46.6755),
    ("Prince Sultan Military Medical City", "Makkah Al Mukarramah Rd, Riyadh", 24.6867, 46.7081),
]

DISTRICTS = [
    "Al Olaya", "Al Malaz", "An Nuzhah", "Al Nakheel", "Al Yasmin",
    "Al Qirawan", "Al Nafel", "Diriyah", "Al Rahmaniyah", "Al Hada",
]

STREETS = [
    "King Fahd Road", "Takhassusi Street", "Olaya Street",
    "Imam Saud Road", "Eastern Ring Road", "Northern Ring Road",
]

def random_address() -> str:
    return f"{random.randint(10,999)} {random.choice(STREETS)}, {random.choice(DISTRICTS)}, Riyadh, SA"

def random_coords() -> Tuple[float, float]:
    return round(random.uniform(24.5, 25.0), 6), round(random.uniform(46.5, 47.0), 6)

# ==========================================================
# 3.5) CSV Path Resolution (NO hardcoded /Users/... in code)
# ==========================================================

def resolve_csv_path_optional() -> Optional[str]:
    env_path = (os.getenv("TEMP_SENSITIVE_CSV") or "").strip()
    if env_path and Path(env_path).exists():
        return env_path

    here = Path(__file__).resolve().parent
    candidates = [
        here / "output2.csv",
        here / "data" / "output2.csv",
        Path.cwd() / "output2.csv",
        Path.cwd() / "data" / "output2.csv",
        Path("/app/output2.csv"),
        Path("/app/data/output2.csv"),
    ]
    for p in candidates:
        if p.exists():
            return str(p)
    return None

# ==========================================================
# 3.6) Parse helpers (same semantics as output2)
# ==========================================================

def _norm_key(k: str) -> str:
    return (k or "").strip().lower()

def _get_col_ci(row: dict, *keys: str) -> str:
    want = {_norm_key(k) for k in keys if k}
    for rk, rv in row.items():
        if _norm_key(rk) in want and rv is not None:
            return str(rv).strip()
    return ""

def parse_yes_no(v: str) -> bool:
    s = (v or "").strip().lower()
    return s in ("yes", "y", "true", "1", "t")

def parse_temp_range(s: str) -> Tuple[float, float]:
    txt = (s or "").replace("−", "-")
    nums = re.findall(r"-?\d+(?:\.\d+)?", txt)
    if len(nums) >= 2:
        a, b = float(nums[0]), float(nums[1])
        return (min(a, b), max(a, b))
    if len(nums) == 1:
        x = float(nums[0])
        return (x, x)
    return (2.0, 8.0)

def duration_to_minutes_approx(s: str) -> Optional[int]:
    txt = (s or "").strip().lower()
    m = re.findall(r"\d+(?:\.\d+)?", txt)
    if not m:
        return None
    val = float(m[0])
    if "min" in txt:
        return int(val)
    if "hour" in txt or "hr" in txt:
        return int(val * 60)
    if "day" in txt:
        return int(val * 24 * 60)
    if "week" in txt:
        return int(val * 7 * 24 * 60)
    if "month" in txt:
        return int(val * 30 * 24 * 60)
    if "year" in txt:
        return int(val * 365 * 24 * 60)
    return None

def classify_risk(max_time_excursion: str) -> str:
    mins = duration_to_minutes_approx(max_time_excursion)
    if mins is None:
        return "High"
    if mins <= 24 * 60:
        return "Critical"
    if mins <= 7 * 24 * 60:
        return "High"
    return "Medium"

def clean_card_label(name: str) -> str:
    n = (name or "").strip()
    n = re.sub(r"\s+", " ", n)
    return safe_str(n, 100)

# ==========================================================
# 3.7) Load Medications from CSV OR Generate Synthetic (mimic output2)
# ==========================================================

def load_csv_meds(csv_path: str) -> List[Dict]:
    meds_map: Dict[str, Dict] = {}

    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            product = _get_col_ci(row, "Product Name", "product_name", "ProductName")
            desc = _get_col_ci(row, "Description", "description")
            info_src = _get_col_ci(row, "Information Source", "information_source", "InformationSource")
            max_time = _get_col_ci(row, "Maximum Time For excursion", "Maximum Time for excursion", "max_time_excursion")
            temp_range = _get_col_ci(row, "Temperature Range For excursion", "Temperature Range for excursion", "temp_range_excursion")

            rtf = _get_col_ci(row, "Return to the fridge", "return_to_fridge")
            use_within = _get_col_ci(row, "Use product within max time for excursion", "use_within_max_time")
            actions_flag = _get_col_ci(row, "Additional actions following excursion", "additional_actions_following_excursion")
            actions_detail = _get_col_ci(row, "Additional actions detail", "additional_actions_detail")

            # ✅ Name AS-IS from Product Name (card label)
            name = clean_card_label(product)
            if not name:
                name = clean_card_label(desc)

            if not name:
                continue

            min_exc, max_exc = parse_temp_range(temp_range)
            risk = classify_risk(max_time)

            key = f"{name.lower()}|{min_exc}|{max_exc}|{(max_time or '').lower()}"
            if key in meds_map:
                continue

            meds_map[key] = {
                "name": name,
                "description": safe_str(desc or product, 200),
                "information_source": info_src or "Product licence",
                "max_time_exertion": max_time or "N/A",
                "min_exc": min_exc,
                "max_exc": max_exc,
                "return_to_fridge": parse_yes_no(rtf),
                "max_time_safe_use": parse_yes_no(use_within),
                "actions_detail": safe_str(actions_detail, 200),
                "actions_flag": parse_yes_no(actions_flag),
                "risk_level": risk,
            }

    meds = list(meds_map.values())
    if not meds:
        raise RuntimeError("❌ CSV parsed but no medication rows found (check headers/format).")
    return meds

def generate_synthetic_meds(n: int) -> List[Dict]:
    """
    Synthetic meds that mimic output2 semantics:
    - name: card label style (human-like)
    - max_time_exertion: realistic strings ("8 hours", "3 days", ...)
    - temp excursion ranges: mix around cold chain (2-8) and excursion ranges
    - return_to_fridge / max_time_safe_use: boolean
    - actions fields similar to CSV patterns
    """
    base_names = [
        "Insulin Glargine", "Insulin Aspart", "Insulin Lispro",
        "Erythropoietin Injection", "Adalimumab Pen", "Etanercept Auto-Injector",
        "Interferon Beta", "Filgrastim Syringe", "Influenza Vaccine",
        "Hepatitis B Vaccine", "COVID-19 Vaccine", "Growth Hormone (Somatropin)",
        "Rituximab Vial", "Trastuzumab Vial", "GLP-1 Injection (Semaglutide)",
        "Liraglutide Pen", "Monoclonal Antibody Injection",
    ]
    forms = ["Vial", "Pen", "Syringe", "Ampoule", "Cartridge", "Prefilled Syringe"]
    strengths = ["10 mg", "20 mg", "50 mg", "100 mg", "200 mg", "5 mL", "10 mL", "0.5 mL"]
    sources = ["Product licence", "SmPC", "Manufacturer leaflet"]

    duration_pool = [
        "30 minutes", "2 hours", "4 hours", "8 hours", "12 hours",
        "1 day", "2 days", "3 days", "5 days", "7 days",
        "2 weeks", "1 month",
    ]

    temp_pool = [
        (2.0, 8.0),
        (2.0, 25.0),
        (0.0, 25.0),
        (-2.0, 8.0),
        (8.0, 25.0),
        (15.0, 30.0),
    ]

    meds = []
    seen = set()

    for i in range(max(20, n)):
        name = random.choice(base_names)
        # add variation without breaking "card label" vibe
        label = f"{name} {random.choice(strengths)} {random.choice(forms)}"
        label = clean_card_label(label)

        (mn, mx) = random.choice(temp_pool)
        max_time = random.choice(duration_pool)

        key = f"{label.lower()}|{mn}|{mx}|{max_time.lower()}"
        if key in seen:
            continue
        seen.add(key)

        actions_flag = random.random() < 0.35
        actions_detail = ""
        if actions_flag:
            actions_detail = random.choice([
                "Do not use if exposed beyond allowed excursion time.",
                "Discard if uncertain; follow product licence guidance.",
                "Inspect visually; if abnormal, do not use and contact pharmacy.",
                "Record excursion and consult pharmacist before use.",
            ])

        meds.append({
            "name": label,
            "description": safe_str(f"{label} (synthetic, mimics output2)", 200),
            "information_source": random.choice(sources),
            "max_time_exertion": max_time,
            "min_exc": float(mn),
            "max_exc": float(mx),
            "return_to_fridge": random.random() < 0.55,
            "max_time_safe_use": random.random() < 0.75,
            "actions_detail": safe_str(actions_detail, 200),
            "actions_flag": actions_flag,
            "risk_level": classify_risk(max_time),
        })

        if len(meds) >= n:
            break

    if not meds:
        raise RuntimeError("❌ Synthetic meds generation failed unexpectedly.")
    return meds

csv_path = resolve_csv_path_optional()
if csv_path:
    print(f"📄 Loading medications from CSV (card labels): {csv_path}")
    CSV_MEDS = load_csv_meds(csv_path)
    print(f"✅ Loaded {len(CSV_MEDS)} medications from CSV")
else:
    print("⚠️ output2.csv NOT FOUND inside container.")
    print("   ➜ Continuing with SYNTHETIC medications that mimic output2 schema.")
    print("   ➜ (If you want real CSV later: mount it to /app/data/output2.csv and set TEMP_SENSITIVE_CSV=/app/data/output2.csv)")
    CSV_MEDS = generate_synthetic_meds(SYNTH_MEDS_COUNT)
    print(f"✅ Generated {len(CSV_MEDS)} synthetic medications")

# ==========================================================
# Insert ALL meds once, then reuse via Hospital_Medication
# ==========================================================

medication_ids: List[str] = []

print("💊 Inserting medications into medication table...")

for med in CSV_MEDS:
    medication_id = gen_uuid()
    medication_ids.append(medication_id)

    additional_actions = med["actions_detail"]
    if med["actions_flag"] and not additional_actions:
        additional_actions = "Follow product licence excursion actions."

    cur.execute(
        """
        INSERT INTO medication (
            medication_id, name, description, information_source,
            exp_date, max_time_exertion,
            min_temp_range_excursion, max_temp_range_excursion,
            return_to_the_fridge, max_time_safe_use,
            additional_actions_detail, risk_level
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            medication_id,
            med["name"],
            med["description"],
            med["information_source"],
            datetime.now() + timedelta(days=random.randint(180, 900)),
            med["max_time_exertion"],
            med["min_exc"],
            med["max_exc"],
            med["return_to_fridge"],
            med["max_time_safe_use"],
            additional_actions,
            med["risk_level"],
        ),
    )

conn.commit()

# ==========================================================
# 4) Config
# ==========================================================

NUM_HOSPITALS = 3
MIN_PATIENTS_PER_HOSPITAL = 12
MAX_PATIENTS_PER_HOSPITAL = 25
DRIVERS_PER_HOSPITAL = 4
MIN_MEDS_PER_HOSPITAL = 8
MAX_MEDS_PER_HOSPITAL = 15
NUM_ORDERS = 50

hospital_ids: List[str] = []
hospital_info: Dict[str, Dict] = {}
patients_by_hospital: Dict[str, List[str]] = {}
drivers_by_hospital: Dict[str, List[str]] = {}
driver_ids: List[str] = []
prescriptions: List[Dict] = []
orders_meta: Dict[str, Dict] = {}

REQUEST_STATUSES = ["pending", "approved", "rejected", "resolved"]

def pick_priority() -> str:
    r = random.random()
    if r < 0.6:
        return "Normal"
    elif r < 0.9:
        return "High"
    else:
        return "Critical"

def pick_order_type() -> str:
    return "delivery" if random.random() < 0.75 else "pickup"

def pick_order_status() -> str:
    r = random.random()
    if r < 0.25:
        return "pending"
    elif r < 0.40:
        return "accepted"
    elif r < 0.55:
        return "on_delivery"
    elif r < 0.65:
        return "on_route"
    elif r < 0.80:
        return "delivered"
    elif r < 0.90:
        return "rejected"
    else:
        return "delivery_failed"

def random_temp_value(scenario: str) -> float:
    base = random.uniform(2.0, 7.8)
    if scenario in ["excursion", "both"] and random.random() < 0.30:
        return round(random.uniform(-1.5, 1.9), 2) if random.random() < 0.5 else round(random.uniform(8.5, 15.0), 2)
    return round(base, 2)

# ==========================================================
# 5) Create Hospitals, Patients, Drivers, Hospital_Medication, Prescriptions
# ==========================================================

print("🏥 Seeding Hospitals, Patients, Drivers, Hospital_Medication, Prescriptions ...")

chosen_hospitals = random.sample(RIYADH_HOSPITALS, k=NUM_HOSPITALS)

for idx, (name, addr, h_lat, h_lon) in enumerate(chosen_hospitals):
    hospital_id = gen_uuid()
    hospital_ids.append(hospital_id)
    hospital_info[hospital_id] = {"name": name, "address": addr}

    firebase_uid = "HOSP_" + uuid.uuid4().hex

    # Fixed login hospital 2181241943
    if idx == 0:
        national_id = "2181241943"
        email = "2181241943@hospital.teryag.com"
        hosp_name = "Teryaq Test Hospital"
    else:
        national_id = gen_national_id_10()
        email = fake.email()
        hosp_name = name

    cur.execute(
        """
        INSERT INTO hospital (
            hospital_id, firebase_uid, national_id, name, address,
            email, phone_number, lat, lon, status
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            hospital_id,
            firebase_uid,
            national_id,
            hosp_name,
            addr,
            email,
            phone_sa(),
            h_lat,
            h_lon,
            random.choice(["active", "suspended", "active"]),
        ),
    )

    # Patients
    patients_by_hospital[hospital_id] = []
    num_patients = random.randint(MIN_PATIENTS_PER_HOSPITAL, MAX_PATIENTS_PER_HOSPITAL)

    for _ in range(num_patients):
        patient_id = gen_uuid()
        p_firebase_uid = "PAT_" + uuid.uuid4().hex
        p_national_id = gen_national_id_10()
        plat, plon = random_coords()
        birth_date = fake.date_of_birth(minimum_age=1, maximum_age=90)

        cur.execute(
            """
            INSERT INTO patient (
                patient_id, firebase_uid, national_id, hospital_id,
                name, address, email, phone_number, gender, birth_date,
                lat, lon, status
            )
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                patient_id,
                p_firebase_uid,
                p_national_id,
                hospital_id,
                fake.name(),
                random_address(),
                fake.email(),
                phone_sa(),
                random.choice(["Male", "Female"]),
                birth_date,
                plat,
                plon,
                "active",
            ),
        )
        patients_by_hospital[hospital_id].append(patient_id)

    # Drivers
    drivers_by_hospital[hospital_id] = []
    for _ in range(DRIVERS_PER_HOSPITAL):
        driver_id = gen_uuid()
        d_firebase_uid = "DRV_" + uuid.uuid4().hex
        d_national_id = gen_national_id_10()
        dlat, dlon = random_coords()

        cur.execute(
            """
            INSERT INTO driver (
                driver_id, firebase_uid, national_id, hospital_id,
                name, email, phone_number, address,
                lat, lon, status
            )
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                driver_id,
                d_firebase_uid,
                d_national_id,
                hospital_id,
                fake.name(),
                fake.email(),
                phone_sa(),
                random_address(),
                dlat,
                dlon,
                random.choice(["active", "offline", "blocked", "active"]),
            ),
        )
        drivers_by_hospital[hospital_id].append(driver_id)
        driver_ids.append(driver_id)

    # Hospital_Medication + Prescriptions
    num_meds = random.randint(MIN_MEDS_PER_HOSPITAL, MAX_MEDS_PER_HOSPITAL)
    chosen_med_ids = medication_ids[:] if len(medication_ids) <= num_meds else random.sample(medication_ids, k=num_meds)

    for medication_id in chosen_med_ids:
        cur.execute(
            """
            INSERT INTO hospital_medication (hospital_id, medication_id, availability)
            VALUES (%s,%s,%s)
            ON CONFLICT DO NOTHING
            """,
            (hospital_id, medication_id, True),
        )

        for _ in range(random.randint(1, 4)):
            if not patients_by_hospital[hospital_id]:
                continue
            presc_id = gen_uuid()
            patient_id = random.choice(patients_by_hospital[hospital_id])

            cur.execute(
                """
                INSERT INTO prescription (
                    prescription_id, hospital_id, medication_id, patient_id,
                    expiration_date, reorder_threshold, instructions, prescribing_doctor
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    presc_id,
                    hospital_id,
                    medication_id,
                    patient_id,
                    datetime.now() + timedelta(days=random.randint(90, 365)),
                    random.randint(1, 5),
                    "Use as prescribed",
                    fake.name(),
                ),
            )

            prescriptions.append({"prescription_id": presc_id, "hospital_id": hospital_id, "patient_id": patient_id})

conn.commit()

# ==========================================================
# 6) Generate Orders + Telemetry + Notifications + Reports
# ==========================================================

print("📦 Generating Orders & Telemetry...")

for _ in range(NUM_ORDERS):
    order_id = gen_uuid()
    dashboard_id = gen_uuid()

    pres = random.choice(prescriptions)
    hospital_id = pres["hospital_id"]
    patient_id = pres["patient_id"]
    prescription_id = pres["prescription_id"]

    d_candidates = drivers_by_hospital.get(hospital_id, [])
    driver_id = random.choice(d_candidates) if d_candidates else random.choice(driver_ids)

    r = random.random()
    if r < 0.40:
        scenario = "normal"
    elif r < 0.70:
        scenario = "excursion"
    elif r < 0.85:
        scenario = "delay"
    else:
        scenario = "both"

    cur.execute("""INSERT INTO dashboard (dashboard_id) VALUES (%s)""", (dashboard_id,))

    order_status = pick_order_status()
    order_priority = pick_priority()
    order_type = pick_order_type()

    cur.execute(
        """
        INSERT INTO "Order" (
            order_id, driver_id, patient_id, hospital_id, prescription_id,
            dashboard_id, description, notes, priority_level, order_type,
            OTP, status
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            order_id,
            driver_id,
            patient_id,
            hospital_id,
            prescription_id,
            dashboard_id,
            f"Auto-generated {scenario} order",
            f"Auto-notes: scenario={scenario}",
            order_priority,
            order_type,
            random.randint(1000, 9999),
            order_status,
        ),
    )

    orders_meta[order_id] = {"hospital_id": hospital_id, "patient_id": patient_id, "driver_id": driver_id, "scenario": scenario}

    for _ in range(random.randint(8, 20)):
        minutes_ago = random.randint(5, 240)
        temp_val = random_temp_value(scenario)
        cur.execute(
            """
            INSERT INTO temperature (temperature_id, dashboard_id, temp_value, recorded_at)
            VALUES (%s,%s,%s,NOW() - INTERVAL '%s minutes')
            """,
            (gen_uuid(), dashboard_id, str(temp_val), minutes_ago),
        )

    for _ in range(random.randint(8, 20)):
        lat, lon = random_coords()
        minutes_ago = random.randint(5, 240)
        cur.execute(
            """
            INSERT INTO gps (gps_id, dashboard_id, latitude, longitude, recorded_at)
            VALUES (%s,%s,%s,%s,NOW() - INTERVAL '%s minutes')
            """,
            (gen_uuid(), dashboard_id, lat, lon, minutes_ago),
        )

    if scenario == "normal":
        stability = random.randint(120, 240)
        delivery = random.randint(30, stability - 15)
    elif scenario == "delay":
        stability = random.randint(60, 180)
        delivery = random.randint(stability + 10, stability + 120)
    elif scenario == "excursion":
        stability = random.randint(90, 240)
        delivery = random.randint(30, stability)
    else:
        stability = random.randint(60, 150)
        delivery = random.randint(stability + 20, stability + 150)

    cur.execute(
        """
        INSERT INTO estimated_delivery_time (estimated_delivery_id, dashboard_id, delay_time, recorded_at)
        VALUES (%s,%s,%s,NOW())
        """,
        (gen_uuid(), dashboard_id, timedelta(minutes=delivery)),
    )

    cur.execute(
        """
        INSERT INTO estimated_stability_time (estimated_stability_id, dashboard_id, stability_time, recorded_at)
        VALUES (%s,%s,%s,NOW())
        """,
        (gen_uuid(), dashboard_id, timedelta(minutes=stability)),
    )

    cur.execute(
        """
        INSERT INTO notification (
            notification_id, order_id, notification_type,
            notification_content, notification_time
        )
        VALUES (%s,%s,%s,%s,%s)
        """,
        (
            gen_uuid(),
            order_id,
            "info",
            f"Order {order_id} created (scenario={scenario}).",
            datetime.now() - timedelta(minutes=random.randint(10, 120)),
        ),
    )

    cur.execute(
        """
        INSERT INTO report (report_id, order_id, report_type, report_content)
        VALUES (%s,%s,%s,%s)
        """,
        (gen_uuid(), order_id, "auto", f"Summary: scenario={scenario}, delivery={delivery}min, stability={stability}min."),
    )

conn.commit()

# ==========================================================
# ✅ Ensure pending orders per hospital
# ==========================================================

print("✅ Ensuring each hospital has at least one pending order for approval...")

for hid in hospital_ids:
    cur.execute("""SELECT COUNT(*) FROM "Order" WHERE hospital_id=%s AND status='pending';""", (hid,))
    pending_count = cur.fetchone()[0]
    if pending_count == 0:
        cur.execute("""SELECT order_id FROM "Order" WHERE hospital_id=%s ORDER BY created_at ASC LIMIT 1;""", (hid,))
        row = cur.fetchone()
        if row:
            cur.execute("""UPDATE "Order" SET status='pending' WHERE order_id=%s;""", (row[0],))
            print(f"   • Forced pending order for hospital {hid} (order_id={row[0]})")

conn.commit()

# ==========================================================
# 7) Requests
# ==========================================================

print("📝 Generating Requests...")

for order_id, meta in orders_meta.items():
    if random.random() < 0.35:
        req_status = random.choice(REQUEST_STATUSES)
        cur.execute(
            """
            INSERT INTO requests (request_id, hospital_id, order_id, status, request_content)
            VALUES (%s,%s,%s,%s,%s)
            """,
            (gen_uuid(), meta["hospital_id"], order_id, req_status, f"Request status '{req_status}' for order {order_id}"),
        )

# ==========================================================
# 8) Staging & Production dummy JSON
# ==========================================================

cur.execute(
    """INSERT INTO staging_incoming_data (data, status) VALUES (%s,%s)""",
    (json.dumps({"sample": "staging_payload", "ts": datetime.now().isoformat()}), "pending"),
)

cur.execute(
    """INSERT INTO production_table (data) VALUES (%s)""",
    (json.dumps({"sample": "production_record", "ts": datetime.now().isoformat()}),),
)

conn.commit()
cur.close()
conn.close()

print("\n🎉 ALL DUMMY DATA INSERTED SUCCESSFULLY!")
print("✅ Fixed hospital login national_id: 2181241943")
print(f"✅ Medications inserted: {len(medication_ids)}")
