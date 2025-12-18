# api/routes/ml_router.py

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict, Any

# ============================================
#  🔬 ML Pipeline
# ============================================
from ml.trainer import train_model
from ml.predictor import predict_sample

router = APIRouter(
    prefix="/ml",
    tags=["Machine Learning"],
)

# ============================================
# 1) Generic ML Request (for any model)
# ============================================


class MLRequest(BaseModel):
    """
    Generic ML request wrapper.

    - `data` is a free-form feature vector that will be passed
      directly to `predict_sample(...)`.

    Use this if you want full flexibility from Jupyter / scripts.
    """
    data: Dict[str, Any]


@router.post("/train")
def train_endpoint(limit: int = 50000):
    """
    Train the ML model on PostgreSQL data and save the trained
    artifact (e.g., to Firebase Storage or local storage).

    - `limit`: maximum number of rows to load from the DB.
    """
    try:
        message = train_model(limit=limit)
        return {"message": message}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Training failed: {str(e)}",
        )


@router.post("/predict")
def predict_endpoint(payload: MLRequest):
    """
    Run a generic prediction using the latest model.

    Request body:
    {
      "data": {
         ... free-form feature vector ...
      }
    }

    The body is forwarded as-is to `predict_sample(payload.data)`.
    """
    try:
        result = predict_sample(payload.data)
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Prediction failed: {str(e)}",
        )


# ============================================
# 2) Delivery vs Pickup ML – strongly typed
#    (Patient → Hospital prediction)
# ============================================


class DeliveryFeatures(BaseModel):
    """
    Structured features for the pickup vs delivery classifier.

    This is the shape we expect from the backend when deciding
    how the patient should receive the medication:
      - pickup from hospital
      - or home delivery.

    These fields should match the features used during training.
    """
    patient_id: str
    hospital_id: str

    # Patient-related features
    patient_gender: Optional[str] = None
    patient_age: Optional[int] = None  # backend can compute from birth_date

    # Medication / risk features
    risk_level: Optional[str] = None   # e.g. "High", "Medium", "Low"

    # Request context
    order_type_requested: Optional[str] = "delivery"   # what user originally requested
    priority_level_requested: Optional[str] = "Normal" # "High", "Normal", ...


class DeliveryPredictionOut(BaseModel):
    """
    Standardized response for the delivery decision.

    - delivery_type: "delivery" or "pickup"
    - score: optional confidence score
    - raw: raw dict returned by the underlying model (for debugging/analytics)
    """
    delivery_type: str
    score: Optional[float] = None
    raw: Dict[str, Any]


@router.post("/predict/delivery", response_model=DeliveryPredictionOut)
def predict_delivery_endpoint(payload: DeliveryFeatures):
    """
    Predict whether the patient should receive the medication via
    DELIVERY or PICKUP, using the trained ML model.

    This is the endpoint that can be called by:
      - Hospital backend when creating an order
      - Patient app if you want to preview the recommendation

    Example request:
    {
      "patient_id": "uuid...",
      "hospital_id": "uuid...",
      "patient_gender": "female",
      "patient_age": 35,
      "risk_level": "High",
      "order_type_requested": "delivery",
      "priority_level_requested": "Normal"
    }
    """
    try:
        # Build the feature vector that the model expects.
        features = payload.dict()

        # Call the shared predictor.
        # The model should return something like:
        #   {"delivery_type": "delivery", "score": 0.87, ...}
        result = predict_sample(features)

        # Safe extraction with fallbacks.
        delivery_type = result.get("delivery_type", "delivery")
        score = result.get("score", None)

        return DeliveryPredictionOut(
            delivery_type=delivery_type,
            score=score,
            raw=result,
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Delivery prediction failed: {str(e)}",
        )
