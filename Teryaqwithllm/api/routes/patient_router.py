# ============================================================
# patient_router.py — PRIVACY-SAFE, DASHBOARD-COMPATIBLE (FINAL MERGE)
# - Mirrors driver telemetry logic using Order.dashboard_id (NOT Dashboard.order_id)
# - Patient sees ONLY their own current route segment (driver -> this patient)
# - Hardened against SQLAlchemy Row/BaseRow vs tuple vs ORM object results
# - Hardened against automap schema drift (missing relations/columns)
# - Adds robust order selection + deterministic events (safe, additive)
# - FIXED: home summary refill + notifications (no dummy, no crash)
# - FIXED: orders medication_name (no dummy)
# ============================================================

import os
import requests
from datetime import date, datetime, timedelta
from typing import List, Optional, Dict, Any, Tuple
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import desc, text

from database import get_db
import models
import schemas
from ml.predictor import predict_sample

router = APIRouter(prefix="/patient", tags=["patient"])


def _format_hm(td) -> str:
    if not td:
        return "-"
    try:
        total = int(td.total_seconds())
        h = total // 3600
        m = (total % 3600) // 60
        return f"{h}h {m}m"
    except Exception:
        return "-"

@router.get("/{national_id}/reports/{order_id}")
def get_patient_delivery_report(national_id: str, order_id: str, db: Session = Depends(get_db)):
    # 1) patient
    patient = db.query(models.Patient).filter(models.Patient.national_id == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # 2) order
    order = db.query(models.Order).filter(models.Order.order_id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # 3) ownership check (critical)
    if str(order.patient_id) != str(patient.patient_id):
        raise HTTPException(status_code=403, detail="Order does not belong to this patient")

    hospital = db.query(models.Hospital).filter(models.Hospital.hospital_id == order.hospital_id).first()
    pres = db.query(models.Prescription).filter(models.Prescription.prescription_id == order.prescription_id).first()

    med = None
    if pres:
        med = db.query(models.Medication).filter(models.Medication.medication_id == pres.medication_id).first()

    # 4) delivery events (same as hospital router)
    delivery_events = (
        db.query(models.DeliveryEvent)
        .filter(models.DeliveryEvent.order_id == order_id)
        .order_by(models.DeliveryEvent.recorded_at.asc())
        .all()
    )

    delivery_details = []
    for ev in delivery_events:
        delivery_details.append({
            "status": ev.event_status or "-",
            "description": ev.event_message or "-",
            "duration": _format_hm(getattr(ev, "duration", None)),
            "stability": _format_hm(getattr(ev, "remaining_stability", None)),
            "condition": getattr(ev, "condition", None) or "Normal",
            # optional timestamp for patient UI
            "time": ev.recorded_at.isoformat() if getattr(ev, "recorded_at", None) else None,
        })

    # 5) medication safety (same meaning as hospital)
    allowed_temp = "-"
    max_excursion = "-"
    return_to_fridge = "-"

    if med:
        if med.min_temp_range_excursion is not None and med.max_temp_range_excursion is not None:
            allowed_temp = f"{med.min_temp_range_excursion}–{med.max_temp_range_excursion}°C"
        max_excursion = _format_hm(getattr(med, "max_time_exertion", None))
        if getattr(med, "return_to_the_fridge", None) is not None:
            return_to_fridge = "Yes" if med.return_to_the_fridge else "No"

    generated = datetime.utcnow()

    # 6) Return BOTH camelCase and snake_case to keep old Flutter safe
    payload = {
        "reportId": str(order.order_id),
        "report_id": str(order.order_id),
        "type": "Delivery Report",
        "generated": generated.isoformat(),

        "orderId": str(order.order_id),
        "order_id": str(order.order_id),
        "orderCode": str(order.order_id)[:8],
        "order_code": str(order.order_id)[:8],

        "orderType": getattr(order, "order_type", None) or "-",
        "order_type": getattr(order, "order_type", None) or "-",

        "orderStatus": getattr(order, "status", None) or "-",
        "order_status": getattr(order, "status", None) or "-",

        "createdAt": order.created_at.isoformat() if getattr(order, "created_at", None) else "",
        "created_at": order.created_at.isoformat() if getattr(order, "created_at", None) else "",

        "deliveredAt": order.delivered_at.isoformat() if getattr(order, "delivered_at", None) else "",
        "delivered_at": order.delivered_at.isoformat() if getattr(order, "delivered_at", None) else "",

        "otpCode": str(getattr(order, "otp", "") or ""),
        "otp_code": str(getattr(order, "otp", "") or ""),
        "verified": bool(getattr(order, "otp_verified", False)),
        "priority": getattr(order, "priority_level", None) or "Normal",

        "patientName": patient.name or "-",
        "patient_name": patient.name or "-",
        "phoneNumber": patient.phone_number or "-",
        "phone_number": patient.phone_number or "-",

        "hospitalName": hospital.name if hospital else "-",
        "hospital_name": hospital.name if hospital else "-",

        "medicationName": med.name if med else "-",
        "medication_name": med.name if med else "-",
        "allowedTemp": allowed_temp,
        "allowed_temp": allowed_temp,
        "maxExcursion": max_excursion,
        "max_excursion": max_excursion,
        "returnToFridge": return_to_fridge,
        "return_to_fridge": return_to_fridge,

        "deliveryDetails": delivery_details,
        "delivery_details": delivery_details,
    }

    return payload

# ============================================================
# Row/Entity unwrapping helpers (SQLAlchemy 1.4/2.0 compatible)
# ============================================================
def _unwrap_entity(row, keys: List[str], idx: int):
    """
    SQLAlchemy 1.4/2.0 can return Row objects for multi-entity queries.
    This extracts the ORM entity safely.
    """
    try:
        m = row._mapping  # type: ignore[attr-defined]
        for k in keys:
            if k in m:
                return m[k]
    except Exception:
        pass

    for k in keys:
        try:
            return getattr(row, k)
        except Exception:
            continue

    try:
        return row[idx]
    except Exception:
        return row


def _status_rank(canonical_status: str) -> int:
    s = (canonical_status or "").strip().lower()
    if s == "on_route":
        return 400
    if s == "on_delivery":
        return 300
    if s == "accepted":
        return 200
    if s == "pending":
        return 100
    if s in ("delivered", "delivery_failed", "rejected"):
        return 0
    return 50


def _is_row_like(obj: Any) -> bool:
    return hasattr(obj, "_mapping")


def _safe_col(model, *names: str):
    """Return the first existing ORM column attribute for a model."""
    for n in names:
        if model is not None and hasattr(model, n):
            return getattr(model, n)
    return None


def _safe_in_filter(q, model, col_name: str, values: Tuple[str, ...]):
    """Apply `col.in_(values)` only if the column exists."""
    if model is None or not hasattr(model, col_name):
        return q
    col = getattr(model, col_name)
    try:
        return q.filter(col.in_(values))
    except Exception:
        return q


def _coerce_uuid_maybe(value: Any) -> Optional[UUID]:
    """Best-effort UUID parsing. Returns UUID if parseable, else None."""
    if value is None:
        return None
    if isinstance(value, UUID):
        return value
    try:
        return UUID(str(value))
    except Exception:
        return None


# ============================================================
# Automap-safe model resolver
# ============================================================
def _model(*names):
    for n in names:
        if hasattr(models, n):
            return getattr(models, n)
    return None


HospitalModel = _model("Hospital", "hospital")
PatientModel = _model("Patient", "patient")
DriverModel = _model("Driver", "driver")
MedicationModel = _model("Medication", "medication")
PrescriptionModel = _model("Prescription", "prescription")
OrderModel = _model("Order", "order")  # must exist

NotificationModel = _model("Notification", "notification")
GpsModel = _model("Gps", "gps", "GPS")
TempModel = _model("Temperature", "temperature")

EstimatedDeliveryModel = _model("Estimated_Delivery_Time", "estimated_delivery_time", "EstimatedDeliveryTime")
EstimatedStabilityModel = _model("Estimated_Stability_Time", "estimated_stability_time", "EstimatedStabilityTime")


# ============================================================
# Local input model for address update
# ============================================================
class PatientAddressUpdateIn(BaseModel):
    address: str
    label: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None


# ============================================================
# Helpers
# ============================================================
def _compute_age(birth_date: Optional[date]) -> Optional[int]:
    if not birth_date:
        return None
    today = date.today()
    age = today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))
    return max(age, 0)


def format_interval_hm(value: Optional[timedelta]) -> Optional[str]:
    """Match driver formatting: 'Xh Ym' (or 'Ym')."""
    if not value:
        return None
    if not isinstance(value, timedelta):
        return str(value)
    total = int(value.total_seconds())
    if total < 0:
        total = 0
    h = total // 3600
    m = (total % 3600) // 60
    if h <= 0:
        return f"{m}m"
    return f"{h}h {m}m"


def _normalize_status(status_raw: Optional[str]) -> str:
    s = (status_raw or "").strip().lower()

    if s in ("delivered", "completed", "done"):
        return "delivered"
    if s in ("delivery_failed", "failed", "failure", "not_delivered"):
        return "delivery_failed"
    if s in ("rejected", "denied", "cancelled", "canceled", "cancel"):
        return "rejected"
    if s in ("on_route", "on the way", "on_route", "on route", "en-route"):
        return "on_route"
    if s in ("on_delivery", "progress", "out_for_delivery", "out for delivery", "in_progress", "in progress", "accepted_and_dispatched"):
        return "on_delivery"
    if s in ("accepted", "approved", "confirm"):
        return "accepted"
    if s in ("pending", "waiting", "new"):
        return "pending"

    return s or "pending"


def _is_active_status(canonical_status: str) -> bool:
    return canonical_status in ("pending", "accepted", "on_delivery", "on_route")


def _fmt_dt(dt_val: Optional[datetime]) -> Optional[str]:
    if isinstance(dt_val, datetime):
        return dt_val.strftime("%d %b %Y, %I:%M %p")
    return None


def _get_lat_lon(obj) -> Tuple[Optional[float], Optional[float]]:
    if obj is None:
        return None, None

    lat = None
    lon = None

    for k in ("lat", "latitude", "lat_value", "gps_lat"):
        if hasattr(obj, k):
            lat = getattr(obj, k)
            break

    for k in ("lon", "lng", "longitude", "lon_value", "gps_lon", "gps_lng"):
        if hasattr(obj, k):
            lon = getattr(obj, k)
            break

    try:
        lat = float(lat) if lat is not None else None
    except Exception:
        lat = None

    try:
        lon = float(lon) if lon is not None else None
    except Exception:
        lon = None

    return lat, lon


def _set_first_existing(obj, value, *field_names: str) -> bool:
    for f in field_names:
        if hasattr(obj, f):
            try:
                setattr(obj, f, value)
                return True
            except Exception:
                continue
    return False


# ============================================================
# Medication name resolver (REUSED everywhere to remove "dummy")
# ============================================================
def _resolve_med_name_for_prescription(db: Session, presc: Any) -> Optional[str]:
    """
    Resolve medication name for a Prescription, automap-safe.
    Priority:
      1) presc.medication relationship (if exists)
      2) query Medication by presc.medication_id (if exists)
      3) presc.medication_name (if exists)
      4) None
    """
    med_name = None

    # 1) relationship
    try:
        if hasattr(presc, "medication") and getattr(presc, "medication", None):
            med_obj = getattr(presc, "medication")
            med_name = getattr(med_obj, "name", None)
    except Exception:
        pass

    # 2) explicit query
    if not med_name and MedicationModel is not None:
        try:
            med_id = getattr(presc, "medication_id", None)
            if med_id is not None and hasattr(MedicationModel, "medication_id"):
                med = db.query(MedicationModel).filter(getattr(MedicationModel, "medication_id") == med_id).first()
                if med:
                    med_name = getattr(med, "name", None)
        except Exception:
            pass

    # 3) fallback field
    if not med_name:
        try:
            if hasattr(presc, "medication_name"):
                med_name = getattr(presc, "medication_name", None)
        except Exception:
            pass

    return med_name


def _resolve_med_name_for_order(db: Session, order: Any) -> Optional[str]:
    """
    Resolve medication name for an Order using its prescription_id.
    Works even if Order has no relationship.
    """
    if PrescriptionModel is None:
        return None

    presc_id = getattr(order, "prescription_id", None)
    if presc_id is None:
        return None

    presc = None
    try:
        # try uuid
        presc_uuid = _coerce_uuid_maybe(presc_id)
        if presc_uuid is not None and hasattr(PrescriptionModel, "prescription_id"):
            presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_uuid).first()
        if presc is None and hasattr(PrescriptionModel, "prescription_id"):
            presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_id).first()
    except Exception:
        presc = None

    if not presc:
        return None

    return _resolve_med_name_for_prescription(db, presc)


def _pick_best_order_for_dashboard(db: Session, patient_id) -> Optional[Any]:
    if OrderModel is None:
        return None

    created_col = _safe_col(OrderModel, "created_at", "createdAt", "created_time")

    q = db.query(OrderModel).filter(getattr(OrderModel, "patient_id") == patient_id)
    if created_col is not None:
        q = q.order_by(desc(created_col))

    rows = q.limit(50).all()
    if not rows:
        return None

    def _dt_or_min(v):
        return v if isinstance(v, datetime) else datetime.min

    best = None
    best_key = None

    for o in rows:
        canon = _normalize_status(getattr(o, "status", None))
        rank = _status_rank(canon)

        created_val = None
        if created_col is not None:
            try:
                created_val = getattr(o, created_col.key)  # type: ignore[attr-defined]
            except Exception:
                created_val = getattr(o, "created_at", None)

        created_val = _dt_or_min(created_val)
        key = (rank, created_val)

        if best is None or key > best_key:
            best = o
            best_key = key

    return best


def _build_order_events(order: Any) -> List[Dict[str, Any]]:
    raw_status = getattr(order, "status", None)
    order_status = _normalize_status(raw_status)

    created_at = getattr(order, "created_at", None)
    delivered_at = getattr(order, "delivered_at", None)

    def _evt(status_txt: str, desc: str, ts: Optional[datetime] = None) -> Dict[str, Any]:
        return {"status": status_txt, "description": desc, "timestamp": ts}

    events: List[Dict[str, Any]] = []
    events.append(_evt("Pending", "Order created by patient.", created_at))

    if order_status == "pending":
        events.append(_evt("Pending", "Order is pending hospital approval.", created_at))
    elif order_status == "accepted":
        events.append(_evt("Accepted", "Hospital approved the order.", created_at))
    elif order_status == "on_delivery":
        events.append(_evt("Accepted", "Hospital approved the order.", created_at))
        events.append(_evt("On Delivery", "Driver started delivery process.", created_at))
    elif order_status == "on_route":
        events.append(_evt("Accepted", "Hospital approved the order.", created_at))
        events.append(_evt("On Delivery", "Driver started delivery process.", created_at))
        events.append(_evt("On Route", "Driver is on route to the patient.", created_at))
    elif order_status == "delivered":
        events.append(_evt("Delivered", "Order delivered successfully.", delivered_at))
    elif order_status == "delivery_failed":
        events.append(_evt("Delivery Failed", "Delivery failed. Please contact support.", delivered_at))
    elif order_status == "rejected":
        events.append(_evt("Rejected", "Order was canceled/rejected.", created_at))
    else:
        events.append(_evt("Status", f"Order status is '{order_status}'.", created_at))

    return events


def _push_notification(db: Session, order_id, content: str, notif_type: str = "warning"):
    if NotificationModel is None:
        return
    try:
        kwargs = {}
        if hasattr(NotificationModel, "order_id"):
            kwargs["order_id"] = order_id
        if hasattr(NotificationModel, "notification_content"):
            kwargs["notification_content"] = content
        if hasattr(NotificationModel, "notification_type"):
            kwargs["notification_type"] = notif_type
        if hasattr(NotificationModel, "notification_time"):
            kwargs["notification_time"] = datetime.utcnow()

        n = NotificationModel(**kwargs)
        db.add(n)
        db.commit()
    except Exception:
        db.rollback()

# ============================================================
# DeliveryEvent + Notification (ONE helper to do both)
# ============================================================

def _notification_type_for_event(event_status: str, condition: str) -> str:
    s = (event_status or "").strip().lower()
    c = (condition or "").strip().lower()

    # danger
    if s in ("temperature_exceeded", "stability_exceeded", "delivery_failed", "issue_reported"):
        return "danger"
    if c in ("danger", "critical", "risk"):
        return "danger"

    # warning
    if s in ("cancelled", "canceled", "rejected", "warning"):
        return "warning"

    # success
    if s in ("created", "accepted", "on_delivery", "on_route", "delivered", "otp_verified"):
        return "success"

    return "info"


def _recent_same_event_exists(db: Session, order_id, event_status: str, contains_text: str, within_minutes: int = 5) -> bool:
    """
    Prevent spamming events when the patient opens track multiple times.
    """
    DeliveryEventModel = getattr(models, "DeliveryEvent", None)
    if DeliveryEventModel is None:
        return False

    if not hasattr(DeliveryEventModel, "order_id") or not hasattr(DeliveryEventModel, "event_status"):
        return False

    # choose a time column that exists
    time_col = None
    if hasattr(DeliveryEventModel, "recorded_at"):
        time_col = getattr(DeliveryEventModel, "recorded_at")
    elif hasattr(DeliveryEventModel, "created_at"):
        time_col = getattr(DeliveryEventModel, "created_at")

    q = db.query(DeliveryEventModel).filter(
        getattr(DeliveryEventModel, "order_id") == order_id,
        getattr(DeliveryEventModel, "event_status") == event_status,
    )

    if time_col is not None:
        cutoff = datetime.utcnow() - timedelta(minutes=within_minutes)
        q = q.filter(time_col >= cutoff).order_by(time_col.desc())

    rows = q.limit(10).all()
    needle = (contains_text or "").strip().lower()
    for r in rows:
        msg = (getattr(r, "event_message", "") or "").lower()
        if needle and needle in msg:
            return True
    return False


def _log_delivery_event(
    db: Session,
    order_id,
    event_status: str,
    event_message: str,
    condition: str = "Normal",
    duration: Optional[timedelta] = None,
    remaining_stability: Optional[timedelta] = None,
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    eta: Optional[datetime] = None,
    dedupe_contains: Optional[str] = None,
    dedupe_minutes: int = 5,
    notify: bool = True,
    notif_message: Optional[str] = None,
) -> None:
    """
    ONE call does BOTH:
      1) insert DeliveryEvent row
      2) insert Notification row (using your existing _push_notification)
    """
    DeliveryEventModel = getattr(models, "DeliveryEvent", None)
    if DeliveryEventModel is None:
        return

    # optional dedupe
    if dedupe_contains:
        if _recent_same_event_exists(db, order_id, event_status, dedupe_contains, within_minutes=dedupe_minutes):
            return

    try:
        # 1) delivery_event insert
        kwargs = {}

        if hasattr(DeliveryEventModel, "order_id"):
            kwargs["order_id"] = order_id
        if hasattr(DeliveryEventModel, "event_status"):
            kwargs["event_status"] = event_status
        if hasattr(DeliveryEventModel, "event_message"):
            kwargs["event_message"] = event_message
        if hasattr(DeliveryEventModel, "condition"):
            kwargs["condition"] = condition

        if duration is not None and hasattr(DeliveryEventModel, "duration"):
            kwargs["duration"] = duration
        if remaining_stability is not None and hasattr(DeliveryEventModel, "remaining_stability"):
            kwargs["remaining_stability"] = remaining_stability

        if lat is not None and hasattr(DeliveryEventModel, "lat"):
            kwargs["lat"] = lat
        if lon is not None and hasattr(DeliveryEventModel, "lon"):
            kwargs["lon"] = lon
        if eta is not None and hasattr(DeliveryEventModel, "eta"):
            kwargs["eta"] = eta

        now = datetime.utcnow()
        if hasattr(DeliveryEventModel, "recorded_at"):
            kwargs["recorded_at"] = now
        elif hasattr(DeliveryEventModel, "created_at"):
            kwargs["created_at"] = now

        db.add(DeliveryEventModel(**kwargs))

        # 2) notification insert
        if notify:
            notif_type = _notification_type_for_event(event_status, condition)
            msg = (notif_message or event_message or "").strip()
            if msg:
                _push_notification(db=db, order_id=order_id, content=msg, notif_type=notif_type)

        db.commit()

    except Exception:
        db.rollback()

# ============================================================
# Dashboard telemetry (IDENTICAL MECHANISM AS DRIVER, HARDENED)
# ============================================================
def get_dashboard_times(dashboard_id: Optional[Any], db: Session) -> Tuple[Optional[str], Optional[str], Optional[int], Optional[int]]:
    if not dashboard_id:
        return None, None, None, None

    try:
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
    except Exception:
        return None, None, None, None

    eta_td = eta[0] if eta else None
    stb_td = stb[0] if stb else None

    arrival_hm = format_interval_hm(eta_td) if eta_td else None
    stability_hm = format_interval_hm(stb_td) if stb_td else None

    eta_sec = int(eta_td.total_seconds()) if isinstance(eta_td, timedelta) else None
    stb_sec = int(stb_td.total_seconds()) if isinstance(stb_td, timedelta) else None

    return arrival_hm, stability_hm, eta_sec, stb_sec


def get_latest_temperature(dashboard_id: Optional[Any], db: Session) -> Optional[float]:
    if not dashboard_id:
        return None
    try:
        row = db.execute(
            text(
                """
                SELECT temp_value
                FROM temperature
                WHERE dashboard_id = :id
                ORDER BY recorded_at DESC
                LIMIT 1
                """
            ),
            {"id": str(dashboard_id)},
        ).fetchone()
        if row and row[0] is not None:
            return float(row[0])
    except Exception:
        return None
    return None


# ============================================================
# Privacy-safe route: ONLY driver -> this patient
# ============================================================
def build_osrm_route(driver_lat: float, driver_lon: float, patient_lat: float, patient_lon: float) -> Optional[Dict[str, Any]]:
    base = os.getenv("OSRM_BASE_URL") or os.getenv("OSRM_URL")
    if not base:
        return None

    base = base.rstrip("/")
    url = (
        f"{base}/route/v1/driving/"
        f"{driver_lon},{driver_lat};{patient_lon},{patient_lat}"
        f"?overview=full&geometries=geojson"
    )

    try:
        resp = requests.get(url, timeout=6)
        if not resp.ok:
            return None
        data = resp.json() or {}
        routes = data.get("routes") or []
        if not routes:
            return None

        r0 = routes[0]
        geom = (r0.get("geometry") or {}).get("coordinates")
        if not geom:
            return None

        coords = [{"lat": float(lat), "lon": float(lon)} for lon, lat in geom]
        return {"distance_m": r0.get("distance"), "duration_s": r0.get("duration"), "coordinates": coords}
    except Exception:
        return None


# ============================================================
#  GET /patient/auth/lookup
# ============================================================
@router.get("/auth/lookup")
def lookup_patient_id(national_id: str, db: Session = Depends(get_db)):
    if PatientModel is None:
        raise HTTPException(500, "Patient model not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return {"patient_id": str(getattr(patient, "patient_id")), "name": getattr(patient, "name", "")}


# ============================================================
#  GET /patient/{national_id} → profile
# ============================================================
@router.get("/{national_id}", response_model=schemas.PatientAppProfileOut)
def get_patient_profile(national_id: str, db: Session = Depends(get_db)):
    if PatientModel is None:
        raise HTTPException(500, "Patient model not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    hospital_name: Optional[str] = None
    hospital_id = getattr(patient, "hospital_id", None)
    if hospital_id is not None and HospitalModel is not None and hasattr(HospitalModel, "hospital_id"):
        hosp = db.query(HospitalModel).filter(getattr(HospitalModel, "hospital_id") == hospital_id).first()
        if hosp:
            hospital_name = getattr(hosp, "name", None)

    return schemas.PatientAppProfileOut(
        patient_id=str(getattr(patient, "patient_id")),
        national_id=getattr(patient, "national_id", ""),
        name=getattr(patient, "name", ""),
        gender=getattr(patient, "gender", None),
        birth_date=getattr(patient, "birth_date", None),
        phone_number=getattr(patient, "phone_number", None),
        email=getattr(patient, "email", None),
        marital_status=getattr(patient, "marital_status", None),
        address=getattr(patient, "address", None),
        city=getattr(patient, "city", None),
        primary_hospital=hospital_name,
    )


# ============================================================
#  PUT /patient/{national_id}/address
# ============================================================
@router.put("/{national_id}/address")
def update_patient_address(national_id: str, payload: PatientAddressUpdateIn, db: Session = Depends(get_db)):
    if PatientModel is None:
        raise HTTPException(500, "Patient model not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    if hasattr(patient, "address"):
        setattr(patient, "address", payload.address)

    if payload.lat is not None:
        _set_first_existing(patient, payload.lat, "lat", "latitude", "gps_lat")
    if payload.lon is not None:
        _set_first_existing(patient, payload.lon, "lon", "lng", "longitude", "gps_lon", "gps_lng")

    db.commit()
    db.refresh(patient)
    return {"detail": "Address updated successfully"}


# ============================================================
#  GET /patient/home/{national_id}
# ============================================================
@router.get("/home/{national_id}", response_model=schemas.PatientHomeSummary)
def get_patient_home_summary(national_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None or PrescriptionModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    best_order = _pick_best_order_for_dashboard(db, getattr(patient, "patient_id"))

    recent_orders: List[schemas.PatientHomeRecentOrder] = []
    if best_order:
        order_code = getattr(best_order, "code", None) or str(getattr(best_order, "order_id"))
        status_str = _normalize_status(getattr(best_order, "status", "pending"))
        recent_orders.append(schemas.PatientHomeRecentOrder(status=status_str, code=order_code))

    today = date.today()

    # -----------------------------
    # NEXT REFILL (FIXED, NO CRASH)
    # -----------------------------
    next_refill: Optional[schemas.PatientHomeRefill] = None
    presc_q = (
        db.query(PrescriptionModel)
        .filter(
            getattr(PrescriptionModel, "patient_id") == getattr(patient, "patient_id"),
            getattr(PrescriptionModel, "status") == "Active",
        )
    )

    best_presc = None
    best_days = None

    for presc in presc_q.all():
        exp = getattr(presc, "expiration_date", None)
        if not exp:
            continue

        exp_date = exp.date() if isinstance(exp, datetime) else exp
        if not isinstance(exp_date, date):
            continue

        days_left = (exp_date - today).days
        if days_left < 0:
            continue

        if best_days is None or days_left < best_days:
            best_days = days_left
            best_presc = presc

    if best_presc and best_days is not None:
        med_name = _resolve_med_name_for_prescription(db, best_presc) or "Unknown Medication"
        next_refill = schemas.PatientHomeRefill(medication_name=med_name, days_left=best_days)

    # -----------------------------------
    # NOTIFICATIONS (LATEST, DETERMINISTIC)
    # -----------------------------------
    notifications: List[schemas.PatientHomeNotification] = []
    if NotificationModel is not None and hasattr(NotificationModel, "order_id") and hasattr(NotificationModel, "notification_time"):
        nq = (
            db.query(NotificationModel, OrderModel)
            .join(OrderModel, getattr(NotificationModel, "order_id") == getattr(OrderModel, "order_id"))
            .filter(getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"))
            .order_by(desc(getattr(NotificationModel, "notification_time")))
        )

        row = nq.limit(1).first()
        if row:
            notif = _unwrap_entity(row, ["Notification", "notification"], 0)
            notifications.append(
                schemas.PatientHomeNotification(message=getattr(notif, "notification_content", "") or "")
            )

    return schemas.PatientHomeSummary(
        patient_name=getattr(patient, "name", "Patient"),
        next_refill=next_refill,
        notifications=notifications,
        recent_orders=recent_orders,
    )


# ============================================================
#  GET /patient/{national_id}/dashboard-map
# ============================================================
@router.get("/{national_id}/dashboard-map", response_model=schemas.PatientDashboardMapOut)
def get_patient_dashboard_map(national_id: str, order_id: Optional[str] = None, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    patient_lat, patient_lon = _get_lat_lon(patient)

    active_order = None
    if order_id and str(order_id).strip():
        order_uuid = _coerce_uuid_maybe(order_id)
        if order_uuid is None:
            raise HTTPException(status_code=400, detail="order_id must be a valid UUID")
        active_order = (
            db.query(OrderModel)
            .filter(
                getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"),
                getattr(OrderModel, "order_id") == order_uuid,
            )
            .first()
        )
        if not active_order:
            raise HTTPException(status_code=404, detail=f"Order {order_id} not found for this patient")

    if active_order is None:
        active_order = _pick_best_order_for_dashboard(db, getattr(patient, "patient_id"))

    if not active_order:
        return schemas.PatientDashboardMapOut(
            order_id=None,
            order_code=None,
            status=None,
            patient=schemas.MapPoint(lat=patient_lat, lon=patient_lon),
            driver=None,
            temperature=None,
            arrival_time=None,
            remaining_stability=None,
            notifications=[],
            driver_name=None,
            driver_phone=None,
            events=[],
        )

    driver_lat = None
    driver_lon = None
    driver_name = None
    driver_phone = None

    driver_id = getattr(active_order, "driver_id", None)
    driver_obj = None
    if driver_id is not None and DriverModel is not None and hasattr(DriverModel, "driver_id"):
        driver_obj = db.query(DriverModel).filter(getattr(DriverModel, "driver_id") == driver_id).first()
        if driver_obj is not None:
            driver_name = getattr(driver_obj, "name", None) or getattr(driver_obj, "full_name", None)
            driver_phone = getattr(driver_obj, "phone_number", None) or getattr(driver_obj, "mobile", None)
            driver_lat, driver_lon = _get_lat_lon(driver_obj)

    notifications: List[schemas.PatientDashboardMapNotification] = []
    if NotificationModel is not None and hasattr(NotificationModel, "order_id"):
        notif_time_col = _safe_col(NotificationModel, "notification_time", "created_at", "createdAt")
        nq = db.query(NotificationModel).filter(getattr(NotificationModel, "order_id") == getattr(active_order, "order_id"))
        if notif_time_col is not None:
            nq = nq.order_by(desc(notif_time_col))
        notif_rows = nq.limit(50).all()

        for n in notif_rows:
            notifications.append(
                schemas.PatientDashboardMapNotification(
                    notification_id=str(getattr(n, "notification_id", "")),
                    order_id=str(getattr(active_order, "order_id")),
                    notification_content=getattr(n, "notification_content", ""),
                    notification_type=getattr(n, "notification_type", None),
                    notification_time=getattr(n, "notification_time", None),
                )
            )

    order_code = getattr(active_order, "code", None) or str(getattr(active_order, "order_id"))
    status_canonical = _normalize_status(getattr(active_order, "status", None))
    events = _build_order_events(active_order)

    dashboard_id = getattr(active_order, "dashboard_id", None)
    arrival_time, remaining_stability, _eta_sec, _stb_sec = get_dashboard_times(dashboard_id, db)
    temperature = get_latest_temperature(dashboard_id, db)

    return schemas.PatientDashboardMapOut(
        order_id=str(getattr(active_order, "order_id")),
        order_code=order_code,
        status=status_canonical,
        patient=schemas.MapPoint(lat=patient_lat, lon=patient_lon),
        driver=schemas.MapPoint(lat=driver_lat, lon=driver_lon),
        temperature=temperature,
        arrival_time=arrival_time,
        remaining_stability=remaining_stability,
        notifications=notifications,
        driver_name=driver_name,
        driver_phone=driver_phone,
        events=events,
    )


# ============================================================
#  GET /patient/{national_id}/notifications
# ============================================================
@router.get("/{national_id}/notifications", response_model=List[schemas.PatientNotificationOut])
def get_patient_notifications(national_id: str, order_id: Optional[str] = None, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None or NotificationModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    order_uuid: Optional[UUID] = None
    if order_id and str(order_id).strip():
        order_uuid = _coerce_uuid_maybe(order_id)
        if order_uuid is None:
            raise HTTPException(status_code=400, detail="order_id must be a valid UUID")

    notif_time_col = _safe_col(NotificationModel, "notification_time", "created_at", "createdAt")

    q = (
        db.query(NotificationModel, OrderModel)
        .join(OrderModel, getattr(NotificationModel, "order_id") == getattr(OrderModel, "order_id"))
        .filter(getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"))
    )
    if order_uuid is not None:
        q = q.filter(getattr(NotificationModel, "order_id") == order_uuid)
    if notif_time_col is not None:
        q = q.order_by(desc(notif_time_col))

    rows = q.limit(50).all()

    def _map_type_to_level(notification_type: Optional[str]) -> str:
        t = (notification_type or "").lower()
        if t in ("success", "delivered", "stable", "ok"):
            return "success"
        if t in ("danger", "error", "excursion", "unsafe", "failed"):
            return "danger"
        return "warning"

    result: List[schemas.PatientNotificationOut] = []
    for row in rows:
        notif = _unwrap_entity(row, keys=["Notification", "notification"], idx=0)
        order = _unwrap_entity(row, keys=["Order", "order"], idx=1)

        order_code = getattr(order, "code", None) or str(getattr(order, "order_id"))
        title = f"Order {order_code}"

        result.append(
            schemas.PatientNotificationOut(
                title=title,
                description=getattr(notif, "notification_content", ""),
                level=_map_type_to_level(getattr(notif, "notification_type", None)),
                notification_time=getattr(notif, "notification_time", None),
            )
        )

    return result


# ============================================================
#  GET /patient/{national_id}/orders
# ============================================================
@router.get("/{national_id}/orders", response_model=List[schemas.PatientOrderOut])
def get_patient_orders(national_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        return []

    created_col = _safe_col(OrderModel, "created_at", "createdAt", "created_time")
    q = db.query(OrderModel).filter(getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"))
    if created_col is not None:
        q = q.order_by(desc(created_col))

    rows = q.limit(100).all()

    result: List[schemas.PatientOrderOut] = []
    for order in rows:
        order_id_val = getattr(order, "order_id", None)
        if order_id_val is None:
            continue

        order_id_str = str(order_id_val)
        code = getattr(order, "code", None) or order_id_str
        status_canonical = _normalize_status(getattr(order, "status", None))

        # ✅ FIX: resolve medication name (no dummy)
        med_name = _resolve_med_name_for_order(db, order) or "Unknown Medication"

        result.append(
            schemas.PatientOrderOut(
                order_id=order_id_str,
                status=status_canonical,
                code=code,
                medication_name=med_name,
                hospital_name=None,
                placed_at=getattr(order, "created_at", None),
                delivered_at=getattr(order, "delivered_at", None),
            )
        )

    return result


# ============================================================
#  DELETE /patient/{national_id}/orders/{order_id}  (soft-cancel)
# ============================================================
@router.delete("/{national_id}/orders/{order_id}")
def cancel_and_delete_patient_order(national_id: str, order_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    order_uuid = _coerce_uuid_maybe(order_id)
    if order_uuid is None:
        raise HTTPException(status_code=400, detail="order_id must be a valid UUID")

    order = (
        db.query(OrderModel)
        .filter(
            getattr(OrderModel, "order_id") == order_uuid,
            getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"),
        )
        .first()
    )
    if not order:
        raise HTTPException(status_code=404, detail="Order not found for this patient")

    if _normalize_status(getattr(order, "status", None)) != "pending":
        raise HTTPException(status_code=400, detail="Only pending orders can be canceled")

    if hasattr(order, "status"):
        setattr(order, "status", "rejected")
    db.commit()
    db.refresh(order)

    order_code_for_msg = getattr(order, "code", None) or str(getattr(order, "order_id"))

    _log_delivery_event(
        db=db,
        order_id=getattr(order, "order_id"),
        event_status="cancelled",
        event_message=f"Order {order_code_for_msg} has been canceled by the patient.",
        condition="Normal",
        dedupe_contains="canceled by the patient",
        dedupe_minutes=5,
        notify=True,
    )


@router.post("/{national_id}/orders/{order_id}/cancel")
def cancel_and_delete_patient_order_fallback(national_id: str, order_id: str, db: Session = Depends(get_db)):
    return cancel_and_delete_patient_order(national_id=national_id, order_id=order_id, db=db)


# ============================================================
#  GET /patient/{national_id}/prescriptions
# ============================================================
@router.get("/{national_id}/prescriptions", response_model=List[schemas.PatientPrescriptionCardOut])
def get_patient_prescriptions(national_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or PrescriptionModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        return []

    today = date.today()
    presc_created_col = _safe_col(PrescriptionModel, "created_at", "createdAt", "created_time")
    q = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "patient_id") == getattr(patient, "patient_id"))
    if presc_created_col is not None:
        q = q.order_by(desc(presc_created_col))
    rows = q.all()

    result: List[schemas.PatientPrescriptionCardOut] = []

    for presc in rows:
        presc_id_val = getattr(presc, "prescription_id", None)
        if presc_id_val is None:
            continue

        exp = getattr(presc, "expiration_date", None)
        exp_date: Optional[date] = (exp.date() if isinstance(exp, datetime) else exp if isinstance(exp, date) else None)

        days_left = (exp_date - today).days if exp_date else 0

        status_raw = (getattr(presc, "status", "") or "").lower()
        refill_remaining = getattr(presc, "reorder_threshold", None)

        needs_new = (
            days_left <= 0
            or status_raw in ("invalid", "expired")
            or (isinstance(refill_remaining, int) and refill_remaining <= 0)
        )

        # your plug (kept) but routed through helper
        med_name = _resolve_med_name_for_prescription(db, presc) or "Unknown Medication"

        result.append(
            schemas.PatientPrescriptionCardOut(
                prescription_id=str(presc_id_val),
                medicine=med_name,
                dose=getattr(presc, "dosage", None) or getattr(presc, "dose", None),
                days_left=days_left,
                doctor=getattr(presc, "prescribing_doctor", None) or getattr(presc, "doctor_name", None),
                needs_new_prescription=needs_new,
            )
        )

    return result


# ============================================================
#  GET /patient/{national_id}/order-review/{prescription_id}
# ============================================================
@router.get("/{national_id}/order-review/{prescription_id}", response_model=schemas.PatientOrderReviewOut)
def get_patient_order_review(national_id: str, prescription_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or PrescriptionModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    # --- fetch prescription (uuid-safe) ---
    presc_uuid = _coerce_uuid_maybe(prescription_id)
    presc = None
    if presc_uuid is not None and hasattr(PrescriptionModel, "prescription_id"):
        presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_uuid).first()
    if presc is None and hasattr(PrescriptionModel, "prescription_id"):
        presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == prescription_id).first()

    if not presc:
        raise HTTPException(status_code=404, detail=f"Prescription {prescription_id} not found")

    # ✅ strict ownership (your schema always has patient_id)
    if str(getattr(presc, "patient_id", "")) != str(getattr(patient, "patient_id", "")):
        raise HTTPException(status_code=403, detail="Prescription does not belong to this patient")

    # --- resolve medication + risk_level from schema ---
    med_name = _resolve_med_name_for_prescription(db, presc) or "Unknown Medication"

    risk_level = None
    if MedicationModel is not None:
        med_id = getattr(presc, "medication_id", None)
        if med_id is not None and hasattr(MedicationModel, "medication_id"):
            med = db.query(MedicationModel).filter(getattr(MedicationModel, "medication_id") == med_id).first()
            if med:
                risk_level = getattr(med, "risk_level", None)

    # --- age must be int (avoid predictor crash) ---
    age = _compute_age(getattr(patient, "birth_date", None))
    if age is None:
        age = 30  # safe fallback; choose what matches your dataset assumptions

    # --- hospital_id should preferably come from prescription, then patient ---
    hosp_id = getattr(presc, "hospital_id", None) or getattr(patient, "hospital_id", None)
    hosp_id_str = str(hosp_id) if hosp_id else ""

    # --- request preferences (optional) ---
    requested_type = (getattr(patient, "preferred_delivery_type", None) or "delivery").lower()
    priority_req = "Normal"

    # --- ML features (typed, non-null where it matters) ---
    features = {
        "patient_id": str(getattr(patient, "patient_id")),
        "hospital_id": hosp_id_str,
        "patient_gender": getattr(patient, "gender", None),
        "patient_age": int(age),
        "risk_level": risk_level or "Normal",  # ✅ avoid None
        "order_type_requested": requested_type,
        "priority_level_requested": priority_req,
    }

    # --- call predictor safely ---
    try:
        ml_raw = predict_sample(features) or {}
    except Exception:
        ml_raw = {}

    delivery_type = (ml_raw.get("delivery_type") or requested_type or "delivery").lower()
    score = ml_raw.get("score", None)

    # --- fill prescription card fields from schema (no dummy) ---
    valid_until = getattr(presc, "expiration_date", None)
    refill_limit = getattr(presc, "reorder_threshold", None)

    # Optional: real hospital name (instead of "Hospital")
    hospital_name = "Hospital"
    if HospitalModel is not None and hosp_id and hasattr(HospitalModel, "hospital_id"):
        hosp = db.query(HospitalModel).filter(getattr(HospitalModel, "hospital_id") == hosp_id).first()
        if hosp and getattr(hosp, "name", None):
            hospital_name = getattr(hosp, "name")

    prescription_out = schemas.PatientOrderReviewPrescription(
        prescription_id=str(getattr(presc, "prescription_id")),
        medicine=med_name,
        doctor=getattr(presc, "prescribing_doctor", None) or "Doctor",
        hospital=hospital_name,
        instruction=getattr(presc, "instructions", "") or "",
        valid_until=valid_until,
        refill_limit=refill_limit,
    )

    address = getattr(patient, "address", None) or "Address not set"
    location_out = schemas.PatientOrderReviewLocation(label="Home", address=address)
    ml_out = schemas.DeliveryPredictionOut(delivery_type=delivery_type, score=score, raw=ml_raw)

    return schemas.PatientOrderReviewOut(prescription=prescription_out, location=location_out, ml=ml_out)

# ============================================================
#  POST /patient/{national_id}/orders
# ============================================================
@router.post("/{national_id}/orders", response_model=schemas.PatientOrderOut, status_code=status.HTTP_201_CREATED)
def create_patient_order(national_id: str, payload: schemas.PatientOrderCreateIn, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None or PrescriptionModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    presc_uuid = _coerce_uuid_maybe(getattr(payload, "prescription_id", None))
    presc = None
    if presc_uuid is not None:
        presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_uuid).first()
    if presc is None:
        presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == getattr(payload, "prescription_id")).first()
    if not presc:
        raise HTTPException(status_code=404, detail=f"Prescription {payload.prescription_id} not found")

    order_kwargs: Dict[str, Any] = {}
    for k, v in {
        "patient_id": getattr(patient, "patient_id"),
        "prescription_id": getattr(presc, "prescription_id"),
        "hospital_id": getattr(presc, "hospital_id", None) or getattr(patient, "hospital_id", None),
        "priority_level": getattr(payload, "priority_level", None) or "Normal",
        "order_type": (getattr(payload, "order_type", None) or "delivery").lower(),
        "status": "pending",
        "notes": getattr(payload, "notes", None),
    }.items():
        if hasattr(OrderModel, k):
            order_kwargs[k] = v

    order = OrderModel(**order_kwargs)
    db.add(order)
    db.commit()
    db.refresh(order)

    order_code_for_msg = getattr(order, "code", None) or str(getattr(order, "order_id"))

    _log_delivery_event(
        db=db,
        order_id=getattr(order, "order_id"),
        event_status="created",
        event_message=f"Order {order_code_for_msg} has been placed successfully.",
        condition="Normal",
        dedupe_contains="placed successfully",
        dedupe_minutes=2,
        notify=True,
    )

    order_id_str = str(getattr(order, "order_id"))
    code = getattr(order, "code", None) or order_id_str

    # ✅ FIX: return real medication name
    med_name = _resolve_med_name_for_prescription(db, presc) or "Unknown Medication"

    return schemas.PatientOrderOut(
        order_id=order_id_str,
        status="pending",
        code=code,
        medication_name=med_name,
        hospital_name=None,
        placed_at=getattr(order, "created_at", None),
        delivered_at=getattr(order, "delivered_at", None),
    )


# ============================================================
# GPS helper: latest gps row for THIS order only (HARDENED)
# ============================================================
def _get_latest_gps_point(db: Session, order_uuid: UUID):
    if GpsModel is None or not hasattr(GpsModel, "order_id"):
        return None

    q = db.query(GpsModel).filter(getattr(GpsModel, "order_id") == order_uuid)

    if hasattr(GpsModel, "recorded_at"):
        q = q.order_by(desc(getattr(GpsModel, "recorded_at")))
    elif hasattr(GpsModel, "created_at"):
        q = q.order_by(desc(getattr(GpsModel, "created_at")))
    elif hasattr(GpsModel, "gps_time"):
        q = q.order_by(desc(getattr(GpsModel, "gps_time")))

    return q.first()


# ============================================================
#  GET /patient/{national_id}/track
# ============================================================
@router.get("/{national_id}/track")
def get_patient_track(national_id: str, order_id: Optional[str] = None, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    order = None

    if order_id and str(order_id).strip():
        order_uuid = _coerce_uuid_maybe(order_id)
        if order_uuid is None:
            raise HTTPException(status_code=400, detail="order_id must be a valid UUID")

        order = (
            db.query(OrderModel)
            .filter(
                getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"),
                getattr(OrderModel, "order_id") == order_uuid,
            )
            .first()
        )
        if not order:
            raise HTTPException(status_code=404, detail=f"Order {order_id} not found for this patient")

    if order is None:
        order = _pick_best_order_for_dashboard(db, getattr(patient, "patient_id"))

    if not order:
        raise HTTPException(status_code=404, detail="No orders found for this patient")

    driver_name = None
    driver_phone = None
    driver_lat = None
    driver_lon = None

    driver_id = getattr(order, "driver_id", None)
    driver_obj = None
    if driver_id is not None and DriverModel is not None and hasattr(DriverModel, "driver_id"):
        driver_obj = db.query(DriverModel).filter(getattr(DriverModel, "driver_id") == driver_id).first()
        if driver_obj:
            driver_name = getattr(driver_obj, "name", None) or getattr(driver_obj, "full_name", None)
            driver_phone = getattr(driver_obj, "phone_number", None) or getattr(driver_obj, "mobile", None)
            driver_lat, driver_lon = _get_lat_lon(driver_obj)

    try:
        order_uuid2 = _coerce_uuid_maybe(getattr(order, "order_id"))
        if order_uuid2 is not None:
            gps_row = _get_latest_gps_point(db, order_uuid2)
            if gps_row is not None:
                glat, glon = _get_lat_lon(gps_row)
                if glat is not None and glon is not None:
                    driver_lat, driver_lon = glat, glon
    except Exception:
        pass

    patient_lat, patient_lon = _get_lat_lon(patient)

    created_at = getattr(order, "created_at", None)
    delivered_at = getattr(order, "delivered_at", None)

    created_at_str = _fmt_dt(created_at) or ""
    delivered_at_str = _fmt_dt(delivered_at) or ""

    eta_dt = getattr(order, "estimated_delivery_time", None)
    estimated_date_str = (
        eta_dt.strftime("%d %b %Y") if isinstance(eta_dt, datetime)
        else (created_at.strftime("%d %b %Y") if isinstance(created_at, datetime) else "")
    )

    status_canonical = _normalize_status(getattr(order, "status", None))
    priority = getattr(order, "priority_level", None) or "Normal"
    order_type = getattr(order, "order_type", None) or "Delivery"
    order_code = getattr(order, "code", None) or str(getattr(order, "order_id"))

    dashboard_id = getattr(order, "dashboard_id", None)
    arrival_time, remaining_stability, eta_seconds, stability_seconds = get_dashboard_times(dashboard_id, db)
    temperature = get_latest_temperature(dashboard_id, db)
        # ============================================================
    # AUTO LOG: Temperature / Stability excursions (patient-side)
    # - Writes DeliveryEvent + Notification (via _log_delivery_event)
    # - DEDUPED to avoid spamming when patient refreshes track
    # ============================================================

    try:
        # Fetch medication limits for this order (if available)
        min_allowed = None
        max_allowed = None
        max_time_exertion_td = None  # optional (timedelta)

        presc = None
        med = None

        if PrescriptionModel is not None:
            presc_id = getattr(order, "prescription_id", None)
            presc_uuid = _coerce_uuid_maybe(presc_id) if presc_id is not None else None

            if presc_uuid is not None and hasattr(PrescriptionModel, "prescription_id"):
                presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_uuid).first()
            if presc is None and hasattr(PrescriptionModel, "prescription_id"):
                presc = db.query(PrescriptionModel).filter(getattr(PrescriptionModel, "prescription_id") == presc_id).first()

        if presc is not None and MedicationModel is not None:
            med_id = getattr(presc, "medication_id", None)
            if med_id is not None and hasattr(MedicationModel, "medication_id"):
                med = db.query(MedicationModel).filter(getattr(MedicationModel, "medication_id") == med_id).first()

        if med is not None:
            # temperature band
            min_allowed = getattr(med, "min_temp_range_excursion", None)
            max_allowed = getattr(med, "max_temp_range_excursion", None)

            # optional: maximum time outside safe range
            max_time_exertion_td = getattr(med, "max_time_exertion", None)

        # Latest patient/driver location for context (optional)
        pl_lat, pl_lon = _get_lat_lon(patient)

        # ------------- Temperature excursion -------------
        if temperature is not None and min_allowed is not None and max_allowed is not None:
            try:
                temp_val = float(temperature)
                lo = float(min_allowed)
                hi = float(max_allowed)

                if temp_val < lo or temp_val > hi:
                    _log_delivery_event(
                        db=db,
                        order_id=getattr(order, "order_id"),
                        event_status="temperature_exceeded",
                        event_message=f"Temperature excursion detected: {temp_val:.2f}°C (allowed {lo:.2f}–{hi:.2f}°C).",
                        condition="Danger",
                        remaining_stability=(timedelta(seconds=stability_seconds) if isinstance(stability_seconds, int) else None),
                        lat=pl_lat,
                        lon=pl_lon,
                        dedupe_contains="Temperature excursion detected",
                        dedupe_minutes=10,
                        notify=True,
                        notif_message=f"Warning: temperature is out of range ({temp_val:.1f}°C).",
                    )
            except Exception:
                pass

        # ------------- Stability excursion (remaining <= 0) -------------
        if isinstance(stability_seconds, int) and stability_seconds <= 0:
            _log_delivery_event(
                db=db,
                order_id=getattr(order, "order_id"),
                event_status="stability_exceeded",
                event_message="Stability time exceeded: medication stability window is over.",
                condition="Danger",
                remaining_stability=timedelta(seconds=0),
                lat=pl_lat,
                lon=pl_lon,
                dedupe_contains="Stability time exceeded",
                dedupe_minutes=10,
                notify=True,
                notif_message="Warning: stability time has been exceeded.",
            )

        # ------------- Optional: Max excursion time exceeded (if you store it somewhere) -------------
        # If you later track "time_out_of_range" in your DB, this is where you'd compare it to max_time_exertion_td
        # and log a "time_exceeded" event. For now, we only log temperature_exceeded + stability_exceeded.

    except Exception:
        # Never break the track endpoint because of logging
        pass

    route = None
    if driver_lat is not None and driver_lon is not None and patient_lat is not None and patient_lon is not None:
        route = build_osrm_route(driver_lat, driver_lon, patient_lat, patient_lon)

    events = _build_order_events(order)

    return {
        "orderId": str(getattr(order, "order_id")),
        "orderCode": order_code,
        "status": status_canonical,
        "estimatedDate": estimated_date_str or "",

        "dashboard_id": str(dashboard_id) if dashboard_id else None,
        "temperature": temperature,
        "arrival_time": arrival_time,
        "remaining_stability": remaining_stability,

        "eta_hm": arrival_time or "",
        "stability_hm": remaining_stability or "",
        "eta_seconds": eta_seconds,
        "stability_seconds": stability_seconds,

        "patient": {"lat": patient_lat, "lon": patient_lon},
        "driver": {"lat": driver_lat, "lon": driver_lon},

        "route": route,

        "deliveredAt": delivered_at_str or "",
        "driverName": driver_name or "",
        "driverPhone": driver_phone or "",
        "priority": priority,
        "orderType": order_type,
        "createdAt": created_at_str or "",

        "events": events,
    }


# ============================================================
#  GET /patient/{national_id}/current-route
# ============================================================
@router.get("/{national_id}/current-route")
def get_patient_current_route(national_id: str, order_id: Optional[str] = None, db: Session = Depends(get_db)):
    data = get_patient_track(national_id=national_id, order_id=order_id, db=db)
    return {"order_id": data.get("orderId"), "driver": data.get("driver"), "patient": data.get("patient"), "route": data.get("route")}


# ============================================================
#  BONUS: GET /patient/{national_id}/track/{order_id}
# ============================================================
@router.get("/{national_id}/track/{order_id}")
def get_patient_track_by_id(national_id: str, order_id: str, db: Session = Depends(get_db)):
    return get_patient_track(national_id=national_id, order_id=order_id, db=db)


# ============================================================
#  GET /patient/{national_id}/reports/{order_id}
# ============================================================
@router.get("/{national_id}/reports/{order_id}", response_model=schemas.PatientOrderReportOut)
def get_patient_delivery_report(national_id: str, order_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    order_uuid = _coerce_uuid_maybe(order_id)
    if order_uuid is None:
        raise HTTPException(status_code=400, detail="orderId must be a valid UUID (use order_id from /orders).")

    order = (
        db.query(OrderModel)
        .filter(
            getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"),
            getattr(OrderModel, "order_id") == order_uuid,
        )
        .first()
    )
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found for this patient")

    created_at = getattr(order, "created_at", None)
    delivered_at = getattr(order, "delivered_at", None)
    generated_at = datetime.utcnow()

    created_at_str = _fmt_dt(created_at) or ""
    delivered_at_str = _fmt_dt(delivered_at) or ""
    generated_str = _fmt_dt(generated_at) or ""

    order_code = str(getattr(order, "order_id"))
    order_type = getattr(order, "order_type", None) or "Delivery"
    order_status = _normalize_status(getattr(order, "status", None))

    otp_val = getattr(order, "otp", None) or getattr(order, "OTP", None)
    if otp_val is None:
        otp_code = "• • • •"
    else:
        otp_str = str(otp_val)
        otp_code = " ".join(list(otp_str)) if len(otp_str) == 4 else otp_str

    verified = (order_status == "delivered")

    def _event_row(event_status: str, event_desc: str) -> schemas.DeliveryDetail:
        return schemas.DeliveryDetail(status=event_status, description=event_desc, duration="-", stability="-", condition="Normal")

    event_details: List[schemas.DeliveryDetail] = []
    for e in _build_order_events(order):
        event_details.append(_event_row(str(e.get("status", "")), str(e.get("description", ""))))

    static_details: List[schemas.DeliveryDetail] = [
        schemas.DeliveryDetail(status="Packed", description="Order packed and released by hospital.", duration="-", stability="-", condition="Normal"),
        schemas.DeliveryDetail(status="Assigned", description="Driver assigned and picked up the order.", duration="15m", stability="7h 45m", condition="Normal"),
        schemas.DeliveryDetail(status="Delivery", description="Order is on the way to patient.", duration="1h 30m", stability="7h 00m", condition="Normal"),
        schemas.DeliveryDetail(status="Arrived", description="Driver arrived at patient location.", duration="2h 10m", stability="6h 50m", condition="Normal"),
        schemas.DeliveryDetail(status="Delivered", description="OTP verified and order handed to patient.", duration="2h 15m", stability="6h 45m", condition="Normal"),
    ]

    details = event_details + static_details

    return schemas.PatientOrderReportOut(
        id=order_code,
        type="Delivery Report",
        generated=generated_str,
        orderID=order_code,
        orderType=order_type,
        orderStatus=order_status,
        createdAt=created_at_str,
        deliveredAt=delivered_at_str,
        otpCode=otp_code,
        verified=verified,
        priority="High" if str(getattr(order, "priority_level", "Normal")).lower() in ("high", "urgent") else "Normal",
        patientName=getattr(patient, "name", "Patient"),
        phoneNumber=getattr(patient, "phone_number", "") or "",
        hospitalName="",
        medicationName=_resolve_med_name_for_order(db, order) or "Unknown Medication",
        allowedTemp="2–8°C",
        maxExcursion="30m",
        returnToFridge="Yes",
        deliveryDetails=details,
    )


# ============================================================
#  GET /patient/{national_id}/orders/{order_id}/events
# ============================================================
class PatientOrderEventOut(BaseModel):
    status: str
    description: str
    timestamp: Optional[datetime] = None


@router.get("/{national_id}/orders/{order_id}/events", response_model=List[PatientOrderEventOut])
def get_patient_order_events(national_id: str, order_id: str, db: Session = Depends(get_db)):
    if PatientModel is None or OrderModel is None:
        raise HTTPException(500, "Required models not available")

    patient = db.query(PatientModel).filter(getattr(PatientModel, "national_id") == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail=f"Patient with national_id={national_id} not found")

    order_uuid = _coerce_uuid_maybe(order_id)
    if order_uuid is None:
        raise HTTPException(status_code=400, detail="order_id must be a valid UUID")

    order = (
        db.query(OrderModel)
        .filter(
            getattr(OrderModel, "patient_id") == getattr(patient, "patient_id"),
            getattr(OrderModel, "order_id") == order_uuid,
        )
        .first()
    )
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found for this patient")

    events_raw = _build_order_events(order)
    return [
        PatientOrderEventOut(
            status=str(e.get("status", "")),
            description=str(e.get("description", "")),
            timestamp=e.get("timestamp", None),
        )
        for e in events_raw
    ]



from datetime import datetime
from sqlalchemy import asc
from fastapi import HTTPException

def _fmt_interval_hm(val) -> str:
    if val is None:
        return "-"
    try:
        total_minutes = int(val.total_seconds() // 60)
        h = total_minutes // 60
        m = total_minutes % 60
        return f"{h}h {m}m" if h > 0 else f"{m}m"
    except Exception:
        return "-"

@router.get("/{national_id}/reports/{order_id}")
def get_patient_report(national_id: str, order_id: str, db: Session = Depends(get_db)):
    # 1) patient exists
    patient = db.query(models.Patient).filter(models.Patient.national_id == national_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # 2) order exists + belongs to patient (so patient cannot read others)
    order = db.query(models.Order).filter(models.Order.order_id == order_id).first()
    if not order or str(order.patient_id) != str(patient.patient_id):
        raise HTTPException(status_code=403, detail="Order does not belong to this patient")

    hospital = db.query(models.Hospital).filter(models.Hospital.hospital_id == order.hospital_id).first()

    pres = db.query(models.Prescription).filter(models.Prescription.prescription_id == order.prescription_id).first()
    med = None
    if pres:
        med = db.query(models.Medication).filter(models.Medication.medication_id == pres.medication_id).first()

    # ✅ SOURCE OF TRUTH: delivery_event
    events = (
        db.query(models.DeliveryEvent)
        .filter(models.DeliveryEvent.order_id == order_id)
        .order_by(asc(models.DeliveryEvent.recorded_at))
        .all()
    )

    delivery_details = []
    for e in events:
        delivery_details.append({
            "status": e.event_status or "-",
            "description": e.event_message or "-",
            "duration": _fmt_interval_hm(e.duration),
            "stability": _fmt_interval_hm(e.remaining_stability),
            "condition": e.condition or "Normal",
        })

    # medication fields (same as hospital report needs)
    allowed_temp = "-"
    max_excursion = "-"
    return_to_fridge = "-"

    if med:
        allowed_temp = f"{med.min_temp_range_excursion}–{med.max_temp_range_excursion}°C"
        max_excursion = _fmt_interval_hm(med.max_time_exertion)
        return_to_fridge = "Yes" if bool(med.return_to_the_fridge) else "No"

    generated = order.delivered_at or order.created_at or datetime.utcnow()

    # ✅ return keys that BOTH patient/hospital screens can parse
    return {
        "reportId": str(order.order_id),
        "type": "Delivery Report",
        "generated": generated.isoformat(),

        "orderId": str(order.order_id),
        "orderType": order.order_type or "-",
        "orderStatus": order.status or "-",
        "createdAt": order.created_at.isoformat() if order.created_at else "",
        "deliveredAt": order.delivered_at.isoformat() if order.delivered_at else "",
        "otpCode": str(order.OTP or ""),
        "priority": order.priority_level or "Normal",
        "verified": bool(getattr(order, "otp_verified", False)),

        "patientName": patient.name or "-",
        "phoneNumber": patient.phone_number or "-",
        "hospitalName": (hospital.name if hospital else "-"),

        "medicationName": (med.name if med else "-"),
        "allowedTemp": allowed_temp,
        "maxExcursion": max_excursion,
        "returnToFridge": return_to_fridge,

        "deliveryDetails": delivery_details,
    }
