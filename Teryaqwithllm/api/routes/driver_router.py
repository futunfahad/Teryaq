# ============================================================
# driver_router.py — ENRICHED VERSION (Teryaq Driver API)
# ============================================================

from fastapi import APIRouter, Depends, Header, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime, date, time, timedelta
from uuid import uuid4
from firebase_admin import auth as firebase_auth
from pydantic import BaseModel
from collections import Counter
import requests

from database import get_db
from models import (
    Driver,
    Order,
    Patient,
    Hospital,
    DeliveryEvent,
    Prescription,
    Medication,
)

router = APIRouter(prefix="/driver", tags=["Driver"])

def _create_return_to_hospital_order(db: Session, original: Order) -> Order:
    if not original.hospital_id:
        raise HTTPException(400, "Order has no hospital_id; cannot create return order")

    # create dashboard row for return order (recommended for live tracking)
    dash_row = db.execute(
        text(
            """
            INSERT INTO dashboard (dashboard_id, created_at)
            VALUES (uuid_generate_v4(), NOW())
            RETURNING dashboard_id
            """
        )
    ).fetchone()
    return_dashboard_id = dash_row[0] if dash_row else None

    return_order = Order(
        order_id=uuid4(),
        driver_id=original.driver_id,
        patient_id=original.patient_id,  # optional: keep reference
        hospital_id=original.hospital_id,
        prescription_id=getattr(original, "prescription_id", None),
        dashboard_id=return_dashboard_id,
        description="Return medication to hospital",
        priority_level=getattr(original, "priority_level", "medium"),
        order_type="return_to_hospital",
        status="accepted",
        created_at=datetime.utcnow(),
    )
    db.add(return_order)

    # Optional: add a notification for the return order
    try:
        db.execute(
            text(
                """
                INSERT INTO notification (notification_id, order_id, notification_type, notification_content, notification_time)
                VALUES (uuid_generate_v4(), :oid, 'delivery_status', :msg, NOW())
                """
            ),
            {
                "oid": str(return_order.order_id),
                "msg": "Return order created to deliver medication back to the hospital.",
            },
        )
    except Exception:
        pass

    return return_order


# ============================================================
# Helper — Convert timedelta → "Xh Ym"
# ============================================================
def format_interval_hm(value):
    if not value:
        return None
    if not isinstance(value, timedelta):
        return str(value)

    total = int(value.total_seconds())
    h = total // 3600
    m = (total % 3600) // 60
    return f"{h}h {m}m"


# ============================================================
# Helper — Convert interval/time/"HH:MM:SS" → minutes (int)
# ============================================================
def interval_to_minutes(v):
    if v is None:
        return None

    if isinstance(v, timedelta):
        return int(v.total_seconds() // 60)

    if isinstance(v, time):
        return int(v.hour) * 60 + int(v.minute)

    if isinstance(v, str):
        # "HH:MM:SS" or "HH:MM"
        if ":" in v:
            try:
                parts = v.split(":")
                h = int(parts[0])
                m = int(parts[1]) if len(parts) > 1 else 0
                s = int(parts[2]) if len(parts) > 2 else 0
                return h * 60 + m + (1 if s >= 30 else 0)
            except Exception:
                return None
        return None

    return None


# ============================================================
# Helper — Extract Firebase User from Authorization header
# ============================================================
def get_current_user(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid Authorization header format")

    token = authorization.split(" ", 1)[1].strip()

    try:
        decoded = firebase_auth.verify_id_token(token, clock_skew_seconds=10)
        return decoded
    except firebase_auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Expired Firebase token")
    except firebase_auth.RevokedIdTokenError:
        raise HTTPException(status_code=401, detail="Revoked Firebase token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid Firebase token")

# ============================================================
# Helper — Find Driver Using Token Email → national_id
# ============================================================
def get_driver_from_token(decoded, db: Session) -> Driver:
    email = decoded.get("email")
    if not email:
        raise HTTPException(400, "Email missing in token")

    national_id = email.split("@")[0]
    driver = db.query(Driver).filter(Driver.national_id == national_id).first()
    if not driver:
        raise HTTPException(404, "Driver not found")

    return driver


# ============================================================
# Helper — Convert Order model to dict
# ============================================================
def order_to_dict(o: Order):
    return {
        "order_id": str(o.order_id),
        "driver_id": str(o.driver_id) if o.driver_id else None,
        "patient_id": str(o.patient_id) if o.patient_id else None,
        "hospital_id": str(o.hospital_id) if o.hospital_id else None,
        "dashboard_id": str(o.dashboard_id) if o.dashboard_id else None,
        "status": o.status,
        "OTP": getattr(o, "otp", None),
        "description": getattr(o, "description", None),
        "priority_level": getattr(o, "priority_level", None),
        "order_type": getattr(o, "order_type", None),
        "created_at": o.created_at.isoformat() if o.created_at else None,
        "delivered_at": (
            o.delivered_at.isoformat() if getattr(o, "delivered_at", None) else None
        ),
    }


# ============================================================
# Helper — Latest ETA & Stability from Dashboard tables
# ============================================================
def get_dashboard_times(dashboard_id, db: Session):
    """
    Returns (arrival_time, remaining_stability) as strings like "2h 30m".
    If no data is available, returns (None, None).
    """
    if not dashboard_id:
        return None, None

    eta = db.execute(
        text(
            """
            SELECT delay_time
            FROM estimated_delivery_time
            WHERE dashboard_id = :id
            ORDER BY recorded_at DESC
            LIMIT 1
        """
        ),
        {"id": str(dashboard_id)},
    ).fetchone()

    stb = db.execute(
        text(
            """
            SELECT stability_time
            FROM estimated_stability_time
            WHERE dashboard_id = :id
            ORDER BY recorded_at DESC
            LIMIT 1
        """
        ),
        {"id": str(dashboard_id)},
    ).fetchone()

    arrival_time = format_interval_hm(eta[0]) if eta else None
    remaining_stability = format_interval_hm(stb[0]) if stb else None
    return arrival_time, remaining_stability


# ============================================================
# 🔵 /driver/me
# ============================================================
@router.get("/me")
def get_driver_me(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)

    hospital = (
        db.query(Hospital)
        .filter(Hospital.hospital_id == driver.hospital_id)
        .first()
    )

    return {
        "driver_id": str(driver.driver_id),
        "name": driver.name,
        "national_id": driver.national_id,
        "phone_number": driver.phone_number,
        "address": driver.address,
        "email": driver.email,
        "lat": driver.lat,
        "lon": driver.lon,
        "hospital_id": str(driver.hospital_id) if driver.hospital_id else None,
        "hospital_name": hospital.name if hospital else None,
    }


# ============================================================
# 🔵 /driver/home
# ============================================================
@router.get("/home")
def get_driver_home(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)
    today_orders = db.query(Order).filter(Order.driver_id == driver.driver_id).all()

    return {
        "driver_name": driver.name,
        "driver_id": str(driver.driver_id),
        "today_orders": [order_to_dict(o) for o in today_orders],
    }


# ============================================================
# 🔵 /driver/dashboard
# ============================================================
@router.get("/dashboard")
def get_driver_dashboard(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)

    total = db.query(Order).filter(Order.driver_id == driver.driver_id).count()
    delivered = (
        db.query(Order)
        .filter(Order.driver_id == driver.driver_id, Order.status == "delivered")
        .count()
    )

    return {
        "total_orders": total,
        "delivered": delivered,
        "pending": total - delivered,
        "delivery_rate": (delivered / total * 100) if total else 0,
    }


# ============================================================
# 🔵 /driver/order/{order_id}/dashboard
# ============================================================
@router.get("/order/{order_id}/dashboard")
def get_order_dashboard_card(order_id: str, db: Session = Depends(get_db)):
    order = db.query(Order).filter(Order.order_id == order_id).first()
    if not order:
        raise HTTPException(404, "Order not found")

    if not order.dashboard_id:
        return {
            "order_id": str(order.order_id),
            "dashboard_id": None,
            "has_dashboard": False,
            "temperature": None,
            "arrival_time": None,
            "remaining_stability": None,
        }

    dash_id = order.dashboard_id

    temp = db.execute(
        text(
            """
            SELECT temp_value
            FROM temperature
            WHERE dashboard_id = :id
            ORDER BY recorded_at DESC
            LIMIT 1
        """
        ),
        {"id": dash_id},
    ).fetchone()

    arrival_time, remaining_stability = get_dashboard_times(dash_id, db)

    return {
        "order_id": str(order.order_id),
        "dashboard_id": str(dash_id),
        "has_dashboard": True,
        "temperature": temp[0] if temp else None,
        "arrival_time": arrival_time,
        "remaining_stability": remaining_stability,
    }


# ============================================================
# 🔵 /driver/delivery
# ============================================================
@router.get("/delivery")
def get_driver_delivery(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)

    orders = (
        db.query(Order)
        .filter(Order.driver_id == driver.driver_id)
        .order_by(Order.created_at.desc())
        .all()
    )

    return {"deliveries": [order_to_dict(o) for o in orders]}


# ============================================================
# 🔵 /driver/history
# ============================================================
@router.get("/history")
def get_driver_history(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)

    orders = (
        db.query(Order)
        .filter(Order.driver_id == driver.driver_id)
        .order_by(Order.created_at.desc())
        .all()
    )

    return {"history": [order_to_dict(o) for o in orders]}


# ============================================================
# 🔵 /driver/notifications
# ============================================================
@router.get("/notifications")
def get_driver_notifications(decoded=Depends(get_current_user), db: Session = Depends(get_db)):
    driver = get_driver_from_token(decoded, db)

    rows = db.execute(
        text(
            """
            SELECT
                n.notification_id,
                n.order_id,
                n.notification_type,
                n.notification_content,
                n.notification_time
            FROM notification n
            JOIN "Order" o ON o.order_id = n.order_id
            WHERE o.driver_id = :driver_id
            ORDER BY n.notification_time DESC
        """
        ),
        {"driver_id": str(driver.driver_id)},
    ).fetchall()

    return {
        "notifications": [
            {
                "notification_id": str(r[0]),
                "order_id": str(r[1]),
                "notification_type": r[2],
                "notification_content": r[3],
                "notification_time": r[4].isoformat() if r[4] else None,
            }
            for r in rows
        ]
    }


# ============================================================
# 🔵 /driver/order/{order_id}
# ============================================================
@router.get("/order/{order_id}")
def get_driver_order(order_id: str, db: Session = Depends(get_db)):
    order = db.query(Order).filter(Order.order_id == order_id).first()
    if not order:
        raise HTTPException(404, "Order not found")

    patient = db.query(Patient).filter(Patient.patient_id == order.patient_id).first()
    hospital = db.query(Hospital).filter(Hospital.hospital_id == order.hospital_id).first()

    return {
        "order": order_to_dict(order),
        "patient": {
            "name": patient.name,
            "phone_number": patient.phone_number,
            "address": patient.address,
            "lat": patient.lat,
            "lon": patient.lon,
        } if patient else None,
        "hospital": {
            "name": hospital.name,
            "address": hospital.address,
            "phone_number": hospital.phone_number,
            "lat": hospital.lat,
            "lon": hospital.lon,
        } if hospital else None,
    }


# ============================================================
# 🔵 /driver/orders/today
# ============================================================
@router.get("/orders/today")
def get_today_orders(
    driver_id: str = Query(...),
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)

    # Prevent requesting other drivers' data
    if str(driver.driver_id) != str(driver_id):
        raise HTTPException(status_code=403, detail="driver_id does not match token")

    active = ["accepted", "on_delivery", "on_route"]

    rows = (
        db.query(Order, Patient, Hospital, Prescription, Medication)
        .outerjoin(Patient, Order.patient_id == Patient.patient_id)
        .outerjoin(Hospital, Order.hospital_id == Hospital.hospital_id)
        .outerjoin(Prescription, Order.prescription_id == Prescription.prescription_id)
        .outerjoin(Medication, Prescription.medication_id == Medication.medication_id)
        .filter(
            Order.driver_id == driver_id,
            Order.status.in_(active),
        )
        .order_by(Order.created_at.asc())
        .all()
    )

    # ================================================
    # FETCH cumulative ETA from VRP backend (HGS)
    # ================================================
    cumulative_eta_map = {}
    try:
        hgs_resp = requests.get(
            "http://localhost:8080/driver/hgs",
            params={"driver_id": driver_id},
            timeout=10,
        )
        if hgs_resp.ok:
            hgs_json = hgs_resp.json()
            cumulative_eta_map = (
                hgs_json.get("debug", {}).get("eta_cumulative_by_order", {}) or {}
            )
    except Exception:
        cumulative_eta_map = {}

    patient_ids = [
        str(o.patient_id)
        for (o, *_rest) in rows
        if o.patient_id is not None
    ]
    patient_counts = Counter(patient_ids)

    result = []
    for (o, p, h, pr, med) in rows:
        base = order_to_dict(o)

        arrival_time, remaining_stability = get_dashboard_times(o.dashboard_id, db)

        max_exc_value = None
        if med is not None:
            max_exc_value = getattr(med, "max_excursion_time", None)
            if max_exc_value is None:
                max_exc_value = getattr(med, "medication_max_excursion_time", None)

        max_exc_minutes = interval_to_minutes(max_exc_value)

        hospital_name = h.name if h else None
        first_stop = None
        if p and getattr(p, "address", None):
            first_stop = p.address
        elif h and getattr(h, "address", None):
            first_stop = h.address

        pid = str(o.patient_id) if o.patient_id else None
        count_for_patient = patient_counts.get(pid, 1) if pid else 1
        orders_count = "1 Order" if count_for_patient == 1 else f"{count_for_patient} Orders"

        order_id_str = str(o.order_id)
        cum_min = cumulative_eta_map.get(order_id_str) if isinstance(cumulative_eta_map, dict) else None

        cumulative_arrival_time = (
            format_interval_hm(timedelta(minutes=int(cum_min)))
            if cum_min is not None
            else None
        )

        base.update(
            {
                "hospital_name": hospital_name,
                "first_stop": first_stop,
                "orders_count": orders_count,
                "arrival_time": arrival_time,
                "remaining_stability": remaining_stability,
                "max_excursion_minutes": max_exc_minutes,
                "medication_max_excursion_time": (
                    str(max_exc_value) if max_exc_value is not None else None
                ),
                "cumulative_eta_minutes": cum_min,
                "cumulative_arrival_time": cumulative_arrival_time,
                "patient_name": p.name if p else None,
                "patient_address": p.address if p else None,
            }
        )

        result.append(base)

    return result


# ============================================================
# 🔵 /driver/orders/create
# ============================================================
class CreateOrderRequest(BaseModel):
    patient_id: str
    hospital_id: str
    driver_id: str
    description: str = "New order"
    priority_level: str = "medium"
    order_type: str = "normal"


@router.post("/orders/create")
def create_order(req: CreateOrderRequest, db: Session = Depends(get_db)):
    new = Order(
        order_id=uuid4(),
        patient_id=req.patient_id,
        hospital_id=req.hospital_id,
        driver_id=req.driver_id,
        description=req.description,
        priority_level=req.priority_level,
        order_type=req.order_type,
        status="accepted",
        created_at=datetime.utcnow(),
    )

    db.add(new)
    db.commit()
    db.refresh(new)

    return {"message": "Order created", "order_id": str(new.order_id)}


# ============================================================
# 🔵 /driver/orders/history
# ============================================================
@router.get("/orders/history")
def get_driver_orders_history(
    driver_id: str,
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)
    if str(driver.driver_id) != str(driver_id):
        raise HTTPException(status_code=403, detail="driver_id does not match token")

    history_status = ["delivered", "delivery_failed", "rejected"]

    rows = (
        db.query(Order, Patient, Hospital)
        .outerjoin(Patient, Order.patient_id == Patient.patient_id)
        .outerjoin(Hospital, Order.hospital_id == Hospital.hospital_id)
        .filter(
            Order.driver_id == driver_id,
            Order.status.in_(history_status),
        )
        .order_by(Order.created_at.desc())
        .all()
    )

    result = []
    for (o, p, h) in rows:
        order_dict = order_to_dict(o)
        arrival_time, remaining_stability = get_dashboard_times(o.dashboard_id, db)

        hospital_name = h.name if h else None
        first_stop = None
        if p and p.address:
            first_stop = p.address
        elif h and h.address:
            first_stop = h.address

        enriched = {
            "order": order_dict,
            "patient": {
                "name": p.name,
                "phone_number": p.phone_number,
                "address": p.address,
                "lat": p.lat,
                "lon": p.lon,
            } if p else None,
            "hospital": {
                "name": h.name,
                "address": h.address,
                "phone_number": h.phone_number,
                "lat": h.lat,
                "lon": h.lon,
            } if h else None,
            "hospital_name": hospital_name,
            "first_stop": first_stop,
            "orders_count": "1 Order",
            "arrival_time": arrival_time,
            "remaining_stability": remaining_stability,
        }

        result.append(enriched)

    return result


# ============================================================
# ✅ NEW: /driver/orders/mark-failed
# - marks order as delivery_failed
# - creates a NEW return order (order_type="return_to_hospital")
# - return order destination will be hospital on /today-orders-map
# ============================================================
class MarkFailedRequest(BaseModel):
    order_id: str
    reason: str | None = "delivery_failed"


@router.post("/orders/mark-failed")
def mark_order_failed(
    payload: MarkFailedRequest,
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)

    order = db.query(Order).filter(Order.order_id == payload.order_id).first()
    if not order:
        raise HTTPException(404, "Order not found")

    if order.driver_id != driver.driver_id:
        raise HTTPException(403, "This is not your order")

    if not order.hospital_id:
        raise HTTPException(400, "Order has no hospital_id; cannot create return order")

    # 1) mark original order as failed
    order.status = "delivery_failed"
    order.delivered_at = datetime.utcnow()

    # 2) create dashboard row for return order (recommended)
    dash_row = db.execute(
        text(
            """
            INSERT INTO dashboard (dashboard_id, created_at)
            VALUES (uuid_generate_v4(), NOW())
            RETURNING dashboard_id
        """
        )
    ).fetchone()
    return_dashboard_id = dash_row[0] if dash_row else None

    # 3) create the return-to-hospital order
    return_order = Order(
        order_id=uuid4(),
        driver_id=order.driver_id,
        patient_id=order.patient_id,  # keep reference (optional)
        hospital_id=order.hospital_id,
        prescription_id=getattr(order, "prescription_id", None),
        dashboard_id=return_dashboard_id,
        description="Return medication to hospital",
        priority_level=getattr(order, "priority_level", "medium"),
        order_type="return_to_hospital",
        status="accepted",
        created_at=datetime.utcnow(),
    )
    db.add(return_order)

    # 4) optional notification on the NEW return order
    try:
        db.execute(
            text(
                """
                INSERT INTO notification (notification_id, order_id, notification_type, notification_content, notification_time)
                VALUES (uuid_generate_v4(), :oid, 'delivery_status', :msg, NOW())
            """
            ),
            {
                "oid": str(return_order.order_id),
                "msg": "Delivery failed. Return order created to deliver medication back to the hospital.",
            },
        )
    except Exception:
        # If notification table/uuid extension differs, do not block the main flow
        pass

    db.commit()
    db.refresh(return_order)

    return {
        "success": True,
        "failed_order_id": str(order.order_id),
        "return_order_id": str(return_order.order_id),
        "return_order_type": getattr(return_order, "order_type", None),
        "return_status": return_order.status,
    }


# ============================================================
# 🔵 /driver/today-orders-map
# ✅ UPDATED:
# - if order_type == "return_to_hospital" → destination is HOSPITAL coords
# - otherwise destination is PATIENT coords (same as before)
# ============================================================
@router.get("/today-orders-map")
def get_today_orders_map(
    driver_id: str = Query(...),
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)
    if str(driver.driver_id) != str(driver_id):
        raise HTTPException(status_code=403, detail="driver_id does not match token")

    rows = (
        db.query(Order, Driver, Patient, Hospital)
        .join(Driver, Order.driver_id == Driver.driver_id)
        .outerjoin(Patient, Order.patient_id == Patient.patient_id)
        .join(Hospital, Order.hospital_id == Hospital.hospital_id)
        .filter(Order.driver_id == driver_id)
        .all()
    )

    orders_out = []
    for (o, d, p, h) in rows:
        order_type = (getattr(o, "order_type", None) or "").strip().lower()
        st = (getattr(o, "status", None) or "").strip().lower()

        # Hospital destination if it's a return order OR if rejected/failed (fallback)
        use_hospital_dest = (
            order_type == "return_to_hospital"
            or st in ("rejected", "delivery_failed")
        )

        # Keep key name "patient" for Flutter compatibility (destination marker)
        if use_hospital_dest:
            dest = {
                "id": str(h.hospital_id),
                "name": h.name,
                "lat": float(h.lat) if h.lat is not None else None,
                "lon": float(h.lon) if h.lon is not None else None,
            }
        else:
            dest = {
                "id": str(p.patient_id) if p else None,
                "name": p.name if p else None,
                "lat": float(p.lat) if (p and p.lat is not None) else None,
                "lon": float(p.lon) if (p and p.lon is not None) else None,
            }

        orders_out.append(
            {
                "order_id": str(o.order_id),
                "status": o.status,
                "order_type": getattr(o, "order_type", None),
                "created_at": o.created_at.isoformat() if o.created_at else None,
                "driver": {
                    "id": str(d.driver_id),
                    "name": d.name,
                    "lat": float(d.lat) if d.lat is not None else None,
                    "lon": float(d.lon) if d.lon is not None else None,
                },
                "patient": dest,  # destination marker
            }
        )

    return {"orders": orders_out}

# ============================================================
# 🔵 /driver/verify-otp
# ============================================================
class VerifyOtpRequest(BaseModel):
    order_id: str
    otp: str


@router.post("/verify-otp")
def verify_otp(payload: VerifyOtpRequest, db: Session = Depends(get_db)):
    order = db.query(Order).filter(Order.order_id == payload.order_id).first()
    if not order:
        raise HTTPException(404, "Order not found")

    correct = str(order.otp) if getattr(order, "otp", None) else None
    if correct is None:
        return {"verified": False, "message": "This order does not have an OTP assigned"}

    is_correct = payload.otp == correct
    return {"verified": is_correct, "message": "OTP correct" if is_correct else "Wrong OTP"}


# ============================================================
# 🔵 /driver/orders/mark-delivered
# ============================================================
class MarkDeliveredRequest(BaseModel):
    order_id: str


class RejectOrderRequest(BaseModel):
    order_id: str
    reason: str | None = "reported_by_driver"


@router.post("/orders/mark-delivered")
def mark_order_delivered(
    payload: MarkDeliveredRequest,
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)

    order = db.query(Order).filter(Order.order_id == payload.order_id).first()
    if not order:
        raise HTTPException(404, "Order not found")

    if order.driver_id != driver.driver_id:
        raise HTTPException(403, "This is not your order")

    order.status = "delivered"
    order.delivered_at = datetime.utcnow()

    db.commit()
    db.refresh(order)

    return {
        "success": True,
        "order_id": str(order.order_id),
        "status": order.status,
        "delivered_at": order.delivered_at.isoformat(),
    }


# ============================================================
# 🔴 /driver/orders/reject
# ============================================================
import logging
logger = logging.getLogger("driver_router")

@router.post("/orders/reject")
def reject_order(
    payload: RejectOrderRequest,
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        driver = get_driver_from_token(decoded, db)

        order = db.query(Order).filter(Order.order_id == payload.order_id).first()
        if not order:
            raise HTTPException(404, "Order not found")

        if order.driver_id != driver.driver_id:
            raise HTTPException(403, "This is not your order")

        order.status = "rejected"
        order.delivered_at = datetime.utcnow()

        db.commit()
        db.refresh(order)

        return {
            "success": True,
            "order_id": str(order.order_id),
            "status": order.status,
            "reason": payload.reason,
            "delivered_at": order.delivered_at.isoformat(),
        }

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        logger.exception("Reject order failed")  # prints full stack trace in server logs
        raise HTTPException(status_code=500, detail=f"Reject failed: {repr(e)}")

# ============================================================
# 🔵 /driver/orders/main
# ============================================================
@router.post("/orders/main")
def get_or_create_main_order(
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)

    active_statuses = ["pending", "accepted", "on_delivery", "on_route"]

    existing = (
        db.query(Order)
        .filter(Order.driver_id == driver.driver_id, Order.status.in_(active_statuses))
        .order_by(Order.created_at.desc())
        .first()
    )

    if existing:
        hospital = db.query(Hospital).filter(Hospital.hospital_id == existing.hospital_id).first()
        patient = db.query(Patient).filter(Patient.patient_id == existing.patient_id).first()
        return {
            "is_new": False,
            "order": order_to_dict(existing),
            "hospital_name": hospital.name if hospital else None,
            "patient_name": patient.name if patient else None,
        }

    hospital_id = driver.hospital_id
    if not hospital_id:
        any_hospital = db.query(Hospital).first()
        if not any_hospital:
            raise HTTPException(status_code=400, detail="No hospital available to attach main order.")
        hospital_id = any_hospital.hospital_id

    patient = (
        db.query(Patient)
        .filter(Patient.hospital_id == hospital_id)
        .order_by(Patient.created_at.asc())
        .first()
    )
    patient_id = patient.patient_id if patient else None

    dash_row = db.execute(
        text(
            """
            INSERT INTO dashboard (dashboard_id, created_at)
            VALUES (uuid_generate_v4(), NOW())
            RETURNING dashboard_id
        """
        )
    ).fetchone()

    dashboard_id = dash_row[0]

    new_order = Order(
        order_id=uuid4(),
        driver_id=driver.driver_id,
        patient_id=patient_id,
        hospital_id=hospital_id,
        prescription_id=None,
        dashboard_id=dashboard_id,
        description="Main demo order for driver",
        priority_level="medium",
        order_type="demo",
        status="accepted",
        created_at=datetime.utcnow(),
    )

    db.add(new_order)
    db.commit()
    db.refresh(new_order)

    hospital = db.query(Hospital).filter(Hospital.hospital_id == hospital_id).first()

    return {
        "is_new": True,
        "order": order_to_dict(new_order),
        "hospital_name": hospital.name if hospital else None,
        "patient_name": patient.name if patient else None,
    }


# ============================================================
# 🔵 /driver/orders/start-day
# ============================================================
class StartDayRequest(BaseModel):
    first_order_id: str


@router.post("/orders/start-day")
def start_day(
    payload: StartDayRequest,
    decoded=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    driver = get_driver_from_token(decoded, db)

    active_statuses = ["accepted", "on_delivery", "on_route"]

    orders = (
        db.query(Order)
        .filter(
            Order.driver_id == driver.driver_id,
            Order.status.in_(active_statuses),
        )
        .order_by(Order.created_at.asc())
        .all()
    )

    if not orders:
        raise HTTPException(status_code=400, detail="No active orders for today.")

    for o in orders:
        o.status = "on_delivery"

    first = next((o for o in orders if str(o.order_id) == payload.first_order_id), None)
    if not first:
        raise HTTPException(status_code=404, detail="first_order_id not found in today's orders.")

    first.status = "on_route"

    db.commit()
    db.refresh(first)

    return {
        "success": True,
        "first_order_id": str(first.order_id),
        "first_status": first.status,
        "updated_orders": [order_to_dict(o) for o in orders],
    }
