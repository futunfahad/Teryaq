from fastapi import APIRouter, HTTPException
from datetime import datetime, timedelta
from pydantic import BaseModel
from database import get_medication_by_order, save_stability_state, get_stability_state

router = APIRouter(prefix="/stability")

FRIDGE_MAX = 8.0      # Hardcoded fridge safe limit
TEMP_CHECK_INTERVAL = 5  # seconds

class TempUpdate(BaseModel):
    temp: float
    lat: float
    lon: float

# -----------------------------------------------------------
# Start stability for an order
# -----------------------------------------------------------
@router.post("/start")
def start_stability(order_id: str):

    med = get_medication_by_order(order_id)

    save_stability_state(
        order_id=order_id,
        timer_started=False,
        timer_started_at=None,
        remaining_seconds=int(med.max_time_exertion.total_seconds()),
        max_excursion_temp=med.max_temp_range_excursion,
        active=True
    )

    return {"status": "stability ready", "order_id": order_id}

# -----------------------------------------------------------
# Update temperature from IoT/Driver
# -----------------------------------------------------------
@router.post("/update")
def update_stability(order_id: str, data: TempUpdate):

    state = get_stability_state(order_id)
    if not state.active:
        return {"status": "inactive"}

    med = get_medication_by_order(order_id)
    max_excursion = med.max_temp_range_excursion

    # 1) If exceeds max excursion → immediate failure
    if data.temp > max_excursion:
        save_stability_state(order_id, active=False)
        return {"alert": "MAX EXCURSION EXCEEDED", "stop_delivery": True}

    # 2) Start timer only when temp > 8°C
    if data.temp > FRIDGE_MAX and not state.timer_started:
        save_stability_state(order_id, timer_started=True, timer_started_at=datetime.utcnow())
        return {"timer_started": True, "reason": "temp exceeded fridge limit"}

    # 3) If timer already running, update countdown
    if state.timer_started:
        elapsed = (datetime.utcnow() - state.timer_started_at).total_seconds()
        remaining = state.remaining_seconds - elapsed

        if remaining <= 0:
            save_stability_state(order_id, active=False)
            return {"alert": "STABILITY TIME EXPIRED", "stop_delivery": True}

        return {"timer_running": True, "remaining_seconds": remaining}

    return {"status": "safe"}
