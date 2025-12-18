# ml/predictor.py
import joblib
import pandas as pd

from ml.firebase_utils import (
    download_model_from_firebase,
    model_exists_local,
    LOCAL_MODEL_PATH,
    LOCAL_META_PATH
)

def load_model_and_meta():

    if not model_exists_local():
        print("⚠️ Model missing. Downloading from Firebase...")
        download_model_from_firebase()

    model = joblib.load(LOCAL_MODEL_PATH)
    num_cols, cat_cols, all_columns = joblib.load(LOCAL_META_PATH)

    return model, num_cols, cat_cols, all_columns


def predict_sample(input_data: dict):
    """
    Returns a unified structure used by both:
      - /ml/predict
      - /ml/predict/delivery
      - patient_router.get_patient_order_review

    Output:
    {
        "delivery_type": "pickup" | "delivery",
        "score": 0.87,                        # probability of predicted class
        "recommendation": "pickup" | "delivery",
        "confidence_scores": [...],           # list of probs aligned with classes
        "classes": [...],                     # model.classes_
        "features_used": [...]
    }
    """

    model, num_cols, cat_cols, all_columns = load_model_and_meta()

    # Convert to DataFrame
    df = pd.DataFrame([input_data])

    # Ensure all expected columns exist
    for col in all_columns:
        if col not in df.columns:
            df[col] = 0

    df = df[all_columns]

    # Predict
    probs = model.predict_proba(df)[0]
    pred = model.predict(df)[0]

    # classes_ usually مثل: ["delivery", "pickup"]
    classes = list(model.classes_)

    # probability الخاصة بالـ class المتنبأ به
    try:
        pred_idx = classes.index(pred)
        score = float(probs[pred_idx])
    except ValueError:
        # لو صار شيء غريب، خذ أعلى احتمال
        pred_idx = int(probs.argmax())
        score = float(probs[pred_idx])
        pred = classes[pred_idx]

    return {
        "delivery_type": str(pred),
        "score": score,
        "recommendation": str(pred),
        "confidence_scores": probs.tolist(),
        "classes": classes,
        "features_used": all_columns,
    }
