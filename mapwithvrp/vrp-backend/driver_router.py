# ============================================================
#  📦 DRIVER ROUTER - Fixed for db_core.py
# ============================================================

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
import logging


from db_core import engine  # Your database engine


class RejectPayload(BaseModel):
    order_id: str
    reason: Optional[str] = "reported_by_driver"

# ============================================================
# CORRECT IMPORTS for your project structure
# ============================================================
from db_core import engine  # Your database engine

# For get_current_user, adjust based on where your auth is:
try:
    from auth_utils import get_current_user
except ImportError:
    try:
        from utils.auth_utils import get_current_user
    except ImportError:
        # Temporary placeholder if auth is not set up yet
        def get_current_user():
            """Placeholder - replace with your actual Firebase auth"""
            return {"uid": "test-uid"}

logger = logging.getLogger(__name__)

# ============================================================
# Database Session Dependency
# ============================================================
def get_db():
    """Create database session using your db_core engine"""
    from sqlalchemy.orm import sessionmaker
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Create router WITHOUT prefix (will be added when including)
router = APIRouter()

# ============================================================
# Pydantic Models
# ============================================================
class RejectPayload(BaseModel):
    order_id: str
    reason: Optional[str] = "reported_by_driver"

class DeliveredPayload(BaseModel):
    order_id: str

# ============================================================
# Helper — Resolve driver_id
# ============================================================
def _resolve_driver_id(
    db: Session,
    current_user: dict,
    explicit_driver_id: Optional[str] = None,
) -> str:
    """Resolve driver UUID from query param or Firebase user"""
    if explicit_driver_id:
        return explicit_driver_id

    firebase_uid = current_user.get("uid")
    if not firebase_uid:
        raise HTTPException(status_code=401, detail="Missing Firebase UID")

    result = db.execute(
        text("SELECT driver_id FROM driver WHERE firebase_uid = :uid"),
        {"uid": firebase_uid},
    ).fetchone()

    if not result or not result[0]:
        raise HTTPException(status_code=404, detail="Driver not found")

    return str(result[0])

# ============================================================
#  🔵 GET /driver/me
# ============================================================
@router.get("/me")
def driver_me(
    current=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get current driver profile"""
    result = db.execute(
        text("""
            SELECT driver_id, national_id, name, phone_number, hospital_id
            FROM driver
            WHERE firebase_uid = :uid
        """),
        {"uid": current["uid"]},
    ).fetchone()

    if not result:
        raise HTTPException(status_code=404, detail="Driver not found")

    return {
        "driver_id": str(result[0]),
        "national_id": result[1],
        "name": result[2],
        "phone_number": result[3],
        "hospital_id": str(result[4]) if result[4] else None,
    }

# ============================================================
#  🔵 GET /driver/order/{order_id}
# ============================================================
@router.get("/order/{order_id}")
def order_details(
    order_id: str,
    db: Session = Depends(get_db),
    current=Depends(get_current_user),
):
    """Get order details with patient and hospital info"""
    result = db.execute(
        text("""
            SELECT
                o.order_id, o.status, o.created_at, o.delivered_at,
                o.driver_id, o.patient_id, o.hospital_id, o.dashboard_id,
                o.description, o.priority_level, o.order_type, o.otp as OTP,
                o.arrival_time, o.is_medication_bad, o.progress,
                
                p.name as patient_name, p.phone_number as patient_phone, p.address as patient_address,
                h.name as hospital_name, h.phone_number as hospital_phone, h.address as hospital_address
            FROM medication_order o
            LEFT JOIN patient p ON o.patient_id = p.patient_id
            LEFT JOIN hospital h ON o.hospital_id = h.hospital_id
            WHERE o.order_id = :oid
        """),
        {"oid": order_id},
    ).fetchone()

    if not result:
        raise HTTPException(status_code=404, detail="Order not found")

    return {
        "order": {
            "order_id": str(result[0]),
            "status": result[1],
            "created_at": result[2].isoformat() if result[2] else None,
            "delivered_at": result[3].isoformat() if result[3] else None,
            "driver_id": str(result[4]) if result[4] else None,
            "patient_id": str(result[5]) if result[5] else None,
            "hospital_id": str(result[6]) if result[6] else None,
            "dashboard_id": str(result[7]) if result[7] else None,
            "description": result[8],
            "priority_level": result[9],
            "order_type": result[10],
            "OTP": result[11],
            "arrival_time": result[12],
            "is_medication_bad": result[13],
            "progress": float(result[14]) if result[14] else 0.0,
        },
        "patient": {
            "name": result[15],
            "phone_number": result[16],
            "address": result[17],
        } if result[15] else None,
        "hospital": {
            "name": result[18],
            "phone_number": result[19],
            "address": result[20],
        } if result[18] else None,
    }

# ============================================================
#  🔵 GET /driver/orders/today
# ============================================================
@router.get("/orders/today")
def today_orders(
    driver_id: str = Query(..., description="Driver UUID"),
    db: Session = Depends(get_db),
):
    """Get today's active orders for driver"""
    results = db.execute(
        text("""
            SELECT
                o.order_id, o.status, o.created_at, o.delivered_at,
                p.name as patient_name, p.phone_number as patient_phone, p.address as patient_address,
                h.name as hospital_name, h.phone_number as hospital_phone, h.address as hospital_address
            FROM medication_order o
            LEFT JOIN patient p ON o.patient_id = p.patient_id
            LEFT JOIN hospital h ON o.hospital_id = h.hospital_id
            WHERE
                o.driver_id = :did
                AND DATE(o.created_at) = CURRENT_DATE
                AND o.status NOT IN ('delivered', 'rejected', 'failed')
            ORDER BY o.created_at ASC
        """),
        {"did": driver_id},
    ).fetchall()

    return [
        {
            "order_id": str(r[0]),
            "status": r[1],
            "created_at": r[2].isoformat() if r[2] else None,
            "delivered_at": r[3].isoformat() if r[3] else None,
            "patient_name": r[4],
            "patient_phone": r[5],
            "patient_address": r[6],
            "hospital_name": r[7],
            "hospital_phone": r[8],
            "hospital_address": r[9],
        }
        for r in results
    ]

# ============================================================
#  🔵 GET /driver/orders/history
# ============================================================
@router.get("/orders/history")
def get_orders_history(
    driver_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current=Depends(get_current_user),
):
    """Get driver's order history (delivered/rejected/failed)"""
    driver_uuid = _resolve_driver_id(db, current, driver_id)

    results = db.execute(
        text("""
            SELECT
                o.order_id, o.driver_id, o.patient_id, o.hospital_id,
                o.status, o.description, o.priority_level, o.order_type,
                o.created_at, o.delivered_at, o.progress, o.is_medication_bad,
                
                p.name as patient_name, p.phone_number as patient_phone, p.address as patient_address,
                h.name as hospital_name, h.phone_number as hospital_phone, h.address as hospital_address
            FROM medication_order o
            LEFT JOIN patient p ON o.patient_id = p.patient_id
            LEFT JOIN hospital h ON o.hospital_id = h.hospital_id
            WHERE
                o.driver_id = :driver_id
                AND o.status IN ('delivered', 'rejected', 'failed')
            ORDER BY COALESCE(o.delivered_at, o.created_at) DESC
        """),
        {"driver_id": driver_uuid},
    ).fetchall()

    return [
        {
            "order_id": str(r[0]),
            "driver_id": str(r[1]) if r[1] else None,
            "patient_id": str(r[2]) if r[2] else None,
            "hospital_id": str(r[3]) if r[3] else None,
            "status": r[4],
            "description": r[5],
            "priority_level": r[6],
            "order_type": r[7],
            "created_at": r[8].isoformat() if r[8] else None,
            "delivered_at": r[9].isoformat() if r[9] else None,
            "progress": float(r[10]) if r[10] is not None else None,
            "is_medication_bad": bool(r[11]) if r[11] is not None else None,
            "patient_name": r[12],
            "patient_phone": r[13],
            "patient_address": r[14],
            "hospital_name": r[15],
            "hospital_phone": r[16],
            "hospital_address": r[17],
        }
        for r in results
    ]

# ============================================================
#  🔴 POST /driver/orders/reject - THE CRITICAL ENDPOINT
# ============================================================
@router.post("/orders/reject")
def reject_order(
    payload: RejectPayload,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Mark an order as rejected by the driver.

    Body:
    {
      "order_id": "...",
      "reason": "reported_by_driver"   // optional
    }
    """
    # 1) Fetch the order
    order = db.query(Order).filter(Order.order_id == payload.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # 2) (Optional) ensure the current driver owns this order
    #    If you have driver_id in Order and you map Firebase UID → Driver
    #    you can enforce that here. For now we'll just trust the token.

    # 3) Update status → rejected
    order.status = "rejected"
    order.delivered_at = datetime.utcnow()
    order.progress = 1.0

    db.commit()
    db.refresh(order)

    return {
        "ok": True,
        "status": order.status,
        "order_id": str(order.order_id),
        "reason": payload.reason,
    }


# ============================================================
#  🔵 POST /driver/orders/mark-delivered
# ============================================================
@router.post("/orders/mark-delivered")
def mark_delivered(
    payload: DeliveredPayload,
    db: Session = Depends(get_db),
    current=Depends(get_current_user),
):
    """Mark order as delivered"""
    result = db.execute(
        text("SELECT order_id FROM medication_order WHERE order_id = :oid"),
        {"oid": payload.order_id},
    ).fetchone()

    if not result:
        raise HTTPException(status_code=404, detail="Order not found")

    db.execute(
        text("""
            UPDATE medication_order
            SET status = 'delivered',
                delivered_at = :now,
                progress = 1.0
            WHERE order_id = :oid
        """),
        {"oid": payload.order_id, "now": datetime.utcnow()},
    )
    db.commit()

    return {
        "ok": True,
        "status": "delivered",
        "order_id": str(payload.order_id),
    }


# ============================================================
#  📋 TESTING ENDPOINTS (Optional - for debugging)
# ============================================================

@router.get("/test")
def test_endpoint():
    """Test if driver router is working"""
    return {
        "status": "ok",
        "message": "Driver router is working!",
        "timestamp": datetime.utcnow().isoformat()
    }

@router.get("/test-db")
def test_db(db: Session = Depends(get_db)):
    """Test database connection"""
    try:
        result = db.execute(text("SELECT 1")).fetchone()
        return {
            "status": "ok",
            "message": "Database connection working!",
            "test_result": result[0] if result else None
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")