from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime, timezone
from sqlalchemy import text
from db_core import engine

router = APIRouter()

FRIDGE_MIN = 2.0
FRIDGE_MAX = 8.0

# ◼️ In-memory stability store
STABILITY_STATE = {}

class TempUpdate(BaseModel):
    temp: float
    lat: float
    lon: float

def _now():
    return datetime.now(timezone.utc)

# 🟦 load medication config from DB
def get_medication_config(order_id: str):
    with engine.connect() as conn:
        row = conn.execute(text("""
            SELECT 
                m.max_temp_range_excursion,
                m.max_time_exertion
            FROM "Order" o
            JOIN prescription p ON o.prescription_id = p.prescription_id
            JOIN medication m   ON p.medication_id   = m.medication_id
            WHERE o.order_id = :oid
            LIMIT 1
        """), {"oid": order_id}).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Order or medication not found")

    max_exc = float(row[0])
    max_time = row[1].total_seconds()
    return max_exc, max_time

# ============================================================
# 👉 START STABILITY (NO DB REQUIRED)
# ============================================================

FRIDGE_MIN = 2.0
FRIDGE_MAX = 8.0

STABILITY_STATE = {}

@router.post("/start")
def start_stability(order_id: str):
    max_exc, max_time = get_medication_config(order_id)

    STABILITY_STATE[order_id] = {
        "timer_started": False,
        "timer_started_at": None,
        "active": True,
        "max_exc": max_exc,
        "max_time": max_time
    }

    return {
        "order_id": order_id,
        "max_excursion_temp": max_exc,
        "max_time_exertion_seconds": max_time,
        "timer_started": False
    }


@router.post("/update")
def update_stability(order_id: str, data: TempUpdate):

    if order_id not in STABILITY_STATE:
        return {"error": "Monitoring not started"}

    state = STABILITY_STATE[order_id]

    if not state["active"]:
        return {"status": "inactive"}

    max_exc = state["max_exc"]
    max_time = state["max_time"]

    # 🔹 Fetch dashboard_id ONCE
    with engine.connect() as conn:
        dash_row = conn.execute(text("""
            SELECT dashboard_id
            FROM "Order"
            WHERE order_id = :oid
        """), {"oid": order_id}).fetchone()

    if not dash_row or not dash_row[0]:
        raise HTTPException(400, "Order has no dashboard")

    dashboard_id = dash_row[0]

    # 1️⃣ MAX TEMP EXCEEDED
    if data.temp > max_exc:
        state["active"] = False
        return {"alert": "MAX_EXCURSION_EXCEEDED"}

    # 2️⃣ Start timer if outside fridge
    if data.temp > FRIDGE_MAX and not state["timer_started"]:
        state["timer_started"] = True
        state["timer_started_at"] = _now()

    # 3️⃣ Timer running → compute remaining
    if state["timer_started"]:
        elapsed = (_now() - state["timer_started_at"]).total_seconds()
        remaining = max_time - elapsed

        if remaining <= 0:
            state["active"] = False
            remaining = 0

        # ✅ WRITE TO DASHBOARD TABLE
        with engine.connect() as conn:
            conn.execute(text("""
                INSERT INTO estimated_stability_time (
                    dashboard_id,
                    stability_time,
                    recorded_at
                )
                VALUES (
                    :dash,
                    make_interval(secs => :secs),
                    NOW()
                )
            """), {
                "dash": dashboard_id,
                "secs": int(remaining)
            })
            conn.commit()

        return {
            "remaining_seconds": int(remaining),
            "written_to_dashboard": True
        }

    # 4️⃣ Safe inside fridge → write FULL stability
    with engine.connect() as conn:
        conn.execute(text("""
            INSERT INTO estimated_stability_time (
                dashboard_id,
                stability_time,
                recorded_at
            )
            VALUES (
                :dash,
                make_interval(secs => :secs),
                NOW()
            )
        """), {
            "dash": dashboard_id,
            "secs": int(max_time)
        })
        conn.commit()

    return {"status": "safe", "written_to_dashboard": True}



@router.get("/config/{order_id}")
def stability_config(order_id: str):
    """
    Return medication configuration for an order.
    No DB session table required.
    """
    with engine.connect() as conn:
        row = conn.execute(text("""
            SELECT 
                m.max_temp_range_excursion,
                m.max_time_exertion
            FROM "Order" o
            JOIN prescription p ON o.prescription_id = p.prescription_id
            JOIN medication m   ON p.medication_id   = m.medication_id
            WHERE o.order_id = :oid
            LIMIT 1
        """), {"oid": order_id}).fetchone()

    if not row:
        raise HTTPException(404, "Order or medication not found")

    max_exc = float(row[0])
    max_time = int(row[1].total_seconds())

    return {
        "order_id": order_id,
        "max_excursion_temp": max_exc,
        "max_time_exertion_seconds": max_time
    }
