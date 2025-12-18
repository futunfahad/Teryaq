# ============================================================
# iot_router.py — Real-time HW → DB (GPS + Temperature)
# + Live endpoint for Flutter polling
# (NO NEW TABLES)
# ============================================================

from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime
import math
import os
import random

from database import get_db

router = APIRouter(prefix="/iot", tags=["IoT / Hardware"])

# ============================================================
# Constants
# ============================================================
FREEZING_TEMP_C = 1.0  # ❄️ only freezing protection

# ============================================================
# DEBUG: Force GPS near a target point (OFF by default)
# ============================================================
DEBUG_FORCE_NEAR_COORDS = os.getenv("DEBUG_FORCE_NEAR_COORDS", "0") == "1"
DEBUG_TARGET_LAT = float(os.getenv("DEBUG_TARGET_LAT", "25.902672"))
DEBUG_TARGET_LON = float(os.getenv("DEBUG_TARGET_LON", "45.381932"))
DEBUG_JITTER_METERS = float(os.getenv("DEBUG_JITTER_METERS", "35"))  # how "near" it is


def jitter_near(lat: float, lon: float, jitter_m: float) -> tuple[float, float]:
    """
    Returns a random point within ~jitter_m meters of (lat, lon).
    """
    # Random distance + bearing
    d = random.uniform(0, max(0.0, jitter_m))
    brng = random.uniform(0, 2 * math.pi)

    # Convert meters -> degrees
    dlat = (d * math.cos(brng)) / 111_320.0
    dlon = (d * math.sin(brng)) / (111_320.0 * math.cos(math.radians(lat)))

    return lat + dlat, lon + dlon

# ------------------------------------------------------------
# Haversine — compute distance in km
# ------------------------------------------------------------
def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ------------------------------------------------------------
# Resolve order context
# ------------------------------------------------------------
def resolve_order_context(db: Session, dashboard_id: str | None, order_id: str | None):
    if order_id:
        row = db.execute(
            text("""
                SELECT dashboard_id, patient_id, driver_id
                FROM "Order"
                WHERE order_id = :oid
            """),
            {"oid": order_id},
        ).fetchone()

        if not row or not row[0]:
            raise HTTPException(status_code=400, detail="Invalid order_id")

        return str(row[0]), str(order_id), row[1], str(row[2]) if row[2] else None

    if dashboard_id:
        row = db.execute(
            text("""
                SELECT order_id, patient_id, driver_id
                FROM "Order"
                WHERE dashboard_id = :did
            """),
            {"did": dashboard_id},
        ).fetchone()

        if not row:
            raise HTTPException(status_code=400, detail="Invalid dashboard_id")

        return str(dashboard_id), str(row[0]), row[1], str(row[2]) if row[2] else None

    raise HTTPException(status_code=400, detail="order_id or dashboard_id required")


# ------------------------------------------------------------
# Get ONLY max temperature from medication
# ------------------------------------------------------------
def get_max_temp(db: Session, order_id: str):
    row = db.execute(
        text("""
            SELECT m.max_temp_range_excursion
            FROM "Order" o
            JOIN prescription pr ON pr.prescription_id = o.prescription_id
            JOIN medication m ON m.medication_id = pr.medication_id
            WHERE o.order_id = :oid
        """),
        {"oid": order_id},
    ).fetchone()

    return float(row[0]) if row and row[0] is not None else None


# ------------------------------------------------------------
# Notification helper (dedupe)
# ------------------------------------------------------------
def push_notification(db, order_id, notif_type, content, minutes=5):
    recent = db.execute(
        text("""
            SELECT 1 FROM notification
            WHERE order_id = :oid
              AND notification_type = :t
              AND notification_time >= NOW() - INTERVAL :m
            LIMIT 1
        """),
        {"oid": order_id, "t": notif_type, "m": f"{minutes} minutes"},
    ).fetchone()

    if not recent:
        db.execute(
            text("""
                INSERT INTO notification
                (notification_id, order_id, notification_type, notification_content, notification_time)
                VALUES (uuid_generate_v4(), :oid, :t, :c, NOW())
            """),
            {"oid": order_id, "t": notif_type, "c": content},
        )


# ------------------------------------------------------------
# Delivery event helper (dedupe)
# ------------------------------------------------------------
def log_delivery_event(db, order_id, status, message, condition="Normal", minutes=5):
    recent = db.execute(
        text("""
            SELECT 1 FROM delivery_event
            WHERE order_id = :oid
              AND event_status = :st
              AND recorded_at >= NOW() - INTERVAL :m
            LIMIT 1
        """),
        {"oid": order_id, "st": status, "m": f"{minutes} minutes"},
    ).fetchone()

    if not recent:
        db.execute(
            text("""
                INSERT INTO delivery_event
                (order_id, event_status, event_message, condition, recorded_at)
                VALUES (:oid, :st, :msg, :cond, NOW())
            """),
            {"oid": order_id, "st": status, "msg": message, "cond": condition},
        )


# ------------------------------------------------------------
# Fail order once
# ------------------------------------------------------------
def fail_order_if_needed(db, order_id, reason):
    row = db.execute(
        text("""SELECT status FROM "Order" WHERE order_id = :oid"""),
        {"oid": order_id},
    ).fetchone()

    if not row:
        return

    if row[0].lower() in ("delivered", "delivery_failed", "rejected"):
        return

    db.execute(
        text("""
            UPDATE "Order"
            SET status = 'delivery_failed',
                delivered_at = NOW()
            WHERE order_id = :oid
        """),
        {"oid": order_id},
    )

    log_delivery_event(
        db, order_id,
        status="DELIVERY_FAILED",
        message=reason,
        condition="Critical",
        minutes=60,
    )

    push_notification(
        db, order_id,
        notif_type="delivery_failed",
        content=reason,
        minutes=60,
    )


# ============================================================
# POST /iot/data
# ============================================================
@router.post("/data")
def receive_hw_data(
    temperature: float = Form(...),

    # IMPORTANT: make lat/lon optional now
    latitude: float | None = Form(None),
    longitude: float | None = Form(None),

    humidity: float | None = Form(None),
    speed: float | None = Form(None),
    direction: float | None = Form(None),

    order_id: str | None = Form(None),
    dashboard_id: str | None = Form(None),

    # NEW: force using driver table lat/lon (recommended = true)
    use_driver_location: bool = Form(True),

    db: Session = Depends(get_db),
):
    try:
        dash_id, ord_id, patient_id, driver_id = resolve_order_context(
            db, dashboard_id, order_id
        )
        if not driver_id:
            raise HTTPException(status_code=400, detail="Order has no driver")

        # ------------------------------------------------------------
        # SOURCE OF TRUTH for GPS:
        # - If use_driver_location=True => read from driver table
        # - Else => accept posted latitude/longitude and update driver table
        # ------------------------------------------------------------
        if use_driver_location:
            row = db.execute(
                text("""SELECT lat, lon FROM driver WHERE driver_id=:did"""),
                {"did": driver_id},
            ).fetchone()

            if not row or row[0] is None or row[1] is None:
                raise HTTPException(
                    status_code=400,
                    detail="Driver location is not available in driver table",
                )

            latitude = float(row[0])
            longitude = float(row[1])

        else:
            # If you insist on taking lat/lon from IoT payload
            if latitude is None or longitude is None:
                raise HTTPException(
                    status_code=400,
                    detail="latitude/longitude required when use_driver_location=false",
                )

            # Update driver position FROM PAYLOAD only in this mode
            db.execute(
                text("""UPDATE driver SET lat=:lat, lon=:lon WHERE driver_id=:did"""),
                {"lat": latitude, "lon": longitude, "did": driver_id},
            )

        # ------------------------------------------------------------
        # Insert GPS snapshot (now guaranteed to be driver's current loc)
        # ------------------------------------------------------------
        db.execute(
            text("""INSERT INTO gps VALUES (uuid_generate_v4(), :d, :lat, :lon, NOW())"""),
            {"d": dash_id, "lat": latitude, "lon": longitude},
        )

        # ------------------------------------------------------------
        # Insert temperature
        # ------------------------------------------------------------
        db.execute(
            text("""INSERT INTO temperature VALUES (uuid_generate_v4(), :d, :t, NOW())"""),
            {"d": dash_id, "t": f"{temperature:.2f}"},
        )

        # Temperature logic (unchanged)
        max_temp = get_max_temp(db, ord_id)
        out = False
        reason = None

        if temperature <= FREEZING_TEMP_C:
            out = True
            reason = f"Temperature {temperature:.2f}°C indicates freezing risk"
        elif max_temp is not None and temperature > max_temp:
            out = True
            reason = f"Temperature {temperature:.2f}°C exceeds max {max_temp:.2f}°C"

        if out:
            push_notification(db, ord_id, "temp_alert", reason)
            log_delivery_event(db, ord_id, "TEMP_OUT_OF_RANGE", reason, "Danger")
            fail_order_if_needed(db, ord_id, f"Delivery failed due to temperature excursion. {reason}")

        db.commit()
        return {
            "status": "ok",
            "out_of_range": out,
            "gps_source": "driver_table" if use_driver_location else "payload",
            "gps": {"lat": latitude, "lon": longitude},
        }

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# ============================================================
# GET /iot/live/{order_id}
# ============================================================
@router.get("/live/{order_id}")
def iot_live(order_id: str, db: Session = Depends(get_db)):
    dash = db.execute(
        text("""SELECT dashboard_id FROM "Order" WHERE order_id=:oid"""),
        {"oid": order_id},
    ).fetchone()

    if not dash:
        raise HTTPException(status_code=404, detail="Order not found")

    max_temp = get_max_temp(db, order_id)

    # ✅ Prefer driver table (current driver position)
    drv = db.execute(
        text("""
            SELECT d.lat, d.lon
            FROM "Order" o
            JOIN driver d ON d.driver_id = o.driver_id
            WHERE o.order_id = :oid
            LIMIT 1
        """),
        {"oid": order_id},
    ).fetchone()

    gps_obj = None
    if drv and drv[0] is not None and drv[1] is not None:
        gps_obj = {"lat": float(drv[0]), "lon": float(drv[1])}
    else:
        # fallback: latest gps snapshot
        gps = db.execute(
            text("""
                SELECT latitude, longitude
                FROM gps
                WHERE dashboard_id=:d
                ORDER BY recorded_at DESC
                LIMIT 1
            """),
            {"d": dash[0]},
        ).fetchone()
        gps_obj = {"lat": gps[0], "lon": gps[1]} if gps else None

    temp = db.execute(
        text("""
            SELECT temp_value
            FROM temperature
            WHERE dashboard_id=:d
            ORDER BY recorded_at DESC
            LIMIT 1
        """),
        {"d": dash[0]},
    ).fetchone()

    return {
        "order_id": order_id,
        "gps": gps_obj,
        "temperature": {"value": float(temp[0])} if temp else None,
        "allowed_range": {"min_temp": FREEZING_TEMP_C, "max_temp": max_temp},
    }

    
