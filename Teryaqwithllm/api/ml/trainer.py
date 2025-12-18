import os
import pandas as pd
import numpy as np
import joblib
from math import radians, cos, sin, asin, sqrt

from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.linear_model import LogisticRegression

from database import get_db_connection
from ml.firebase_utils import LOCAL_MODEL_PATH, LOCAL_META_PATH


# ============================================================
# Utility: Haversine distance (km)
# ============================================================

def haversine(lat1, lon1, lat2, lon2):
    """
    Compute distance between two geo-points in kilometers.
    """
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = sin(dlat / 2)**2 + cos(lat1) * cos(lat2) * sin(dlon / 2)**2
    c = 2 * asin(sqrt(a))

    return 6371 * c


# ============================================================
# 1) LOAD RAW DATA (Extended)
# ============================================================

def load_raw_data(limit=50000):
    """
    Load raw operational, spatial, and medical data for each order.
    """

    query = f"""
        SELECT 
            o.order_id,
            o.dashboard_id,

            -- Temperature telemetry
            t.temp_value,
            t.recorded_at AS temp_time,

            -- GPS telemetry (during delivery)
            g.latitude AS gps_lat,
            g.longitude AS gps_lon,

            -- Time estimates
            edt.delay_time,
            est.stability_time,

            -- Patient location
            p.lat AS patient_lat,
            p.lon AS patient_lon,

            -- Hospital location
            h.lat AS hospital_lat,
            h.lon AS hospital_lon,

            -- Medication information
            m.name AS medication_name,
            m.risk_level AS medication_risk_level,
            m.min_temp AS med_min_temp,
            m.max_temp AS med_max_temp

        FROM "Order" o
        LEFT JOIN Temperature t ON t.dashboard_id = o.dashboard_id
        LEFT JOIN GPS g ON g.dashboard_id = o.dashboard_id
        LEFT JOIN estimated_delivery_time edt ON edt.dashboard_id = o.dashboard_id
        LEFT JOIN estimated_stability_time est ON est.dashboard_id = o.dashboard_id
        LEFT JOIN Patient p ON p.patient_id = o.patient_id
        LEFT JOIN Hospital h ON h.hospital_id = o.hospital_id
        LEFT JOIN Medication m ON m.medication_id = o.medication_id
        LIMIT {limit}
    """

    db = get_db_connection()
    df = pd.read_sql(query, db)
    db.close()

    return df


# ============================================================
# 2) FEATURE ENGINEERING
# ============================================================

def engineer_features(df_raw):
    """
    Convert raw telemetry and metadata into ML-ready features.
    """

    # -------------------------------
    # Temperature-based features
    # -------------------------------
    temp_df = df_raw.dropna(subset=["temp_value"]).copy()
    temp_df["temp_value"] = temp_df["temp_value"].astype(float)

    temp_agg = temp_df.groupby("order_id").agg(
        avg_temp=("temp_value", "mean"),
        max_temp=("temp_value", "max"),
        min_temp=("temp_value", "min"),
        temp_exceed_count=("temp_value", lambda x: np.sum((x > 8) | (x < 2)))
    )

    # -------------------------------
    # GPS movement features
    # -------------------------------
    gps_df = df_raw.dropna(subset=["gps_lat", "gps_lon"])
    gps_agg = gps_df.groupby("order_id").agg(
        gps_points=("gps_lat", "count")
    )

    # -------------------------------
    # Time & stability features
    # -------------------------------
    time_df = df_raw.drop_duplicates(subset="order_id").copy()
    time_df["delay_minutes"] = pd.to_numeric(time_df["delay_time"], errors="coerce")
    time_df["stability_minutes"] = pd.to_numeric(time_df["stability_time"], errors="coerce")
    time_df["remaining_stability"] = (
        time_df["stability_minutes"] - time_df["delay_minutes"]
    )

    time_agg = time_df.set_index("order_id")[
        ["delay_minutes", "stability_minutes", "remaining_stability"]
    ]

    # -------------------------------
    # Spatial distance feature
    # -------------------------------
    loc_df = df_raw.drop_duplicates(subset="order_id").copy()
    loc_df["delivery_distance_km"] = loc_df.apply(
        lambda r: haversine(
            r["hospital_lat"], r["hospital_lon"],
            r["patient_lat"], r["patient_lon"]
        ) if pd.notna(r["patient_lat"]) else 0,
        axis=1
    )

    loc_agg = loc_df.set_index("order_id")[["delivery_distance_km"]]

    # -------------------------------
    # Medication risk features
    # -------------------------------
    med_df = df_raw.drop_duplicates(subset="order_id").copy()
    med_df["medication_risk_level"] = med_df["medication_risk_level"].fillna("unknown")
    med_agg = med_df.set_index("order_id")[["medication_risk_level"]]

    # -------------------------------
    # Merge all features
    # -------------------------------
    final = (
        temp_agg
        .join(gps_agg, how="left")
        .join(time_agg, how="left")
        .join(loc_agg, how="left")
        .join(med_agg, how="left")
        .fillna(0)
        .reset_index()
    )

    return final


# ============================================================
# 3) LABELING (Pickup vs Delivery)
# ============================================================

def generate_label(row):
    """
    Rule-based labeling used to train the model.
    """

    if row["temp_exceed_count"] >= 2:
        return "pickup"

    if row["remaining_stability"] < 0:
        return "pickup"

    return "delivery"


def add_labels(df_features):
    df = df_features.copy()
    df["label"] = df.apply(generate_label, axis=1)
    return df


# ============================================================
# 4) TRAIN MODEL
# ============================================================

def train_model(limit=50000):
    """
    Train a binary classification model (Delivery vs Pickup)
    using operational, spatial, and medical features.
    """

    print("📥 Loading raw data...")
    df_raw = load_raw_data(limit)

    print("⚙️ Engineering features...")
    df_features = engineer_features(df_raw)

    print("🏷️ Generating labels...")
    df_labeled = add_labels(df_features)

    X = df_labeled.drop(columns=["label", "order_id"])
    y = df_labeled["label"]

    # Identify numeric and categorical columns
    num_cols = X.select_dtypes(include=["float64", "int64"]).columns.tolist()
    cat_cols = [c for c in X.columns if c not in num_cols]

    # Preprocessing pipeline
    preprocessor = ColumnTransformer([
        ("num", StandardScaler(), num_cols),
        ("cat", OneHotEncoder(handle_unknown="ignore"), cat_cols)
    ])

    # Classification model
    model = Pipeline([
        ("pre", preprocessor),
        ("clf", LogisticRegression(
            max_iter=300,
            class_weight="balanced"
        ))
    ])

    print("🚀 Training model...")
    model.fit(X, y)

    # Save model and metadata locally
    joblib.dump(model, LOCAL_MODEL_PATH)
    joblib.dump((num_cols, cat_cols, list(X.columns)), LOCAL_META_PATH)

    print("💾 Model saved at:", LOCAL_MODEL_PATH)

    return "Enhanced delivery decision model trained successfully"
