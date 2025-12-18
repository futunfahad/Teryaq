import os
import logging
from typing import Optional
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

import requests

# Firebase
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth

# Routers
from routes.auth_router import router as auth_router
from routes.patient_router import router as patient_router
from routes.ml_router import router as ml_router
from routes.driver_router import router as driver_router
from routes.iot_router import router as iot_router
from routes.hospital_router import router as hospital_router


# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | api | %(message)s",
)
logger = logging.getLogger("api")

# -----------------------------------------------------------------------------
# DB Connection
# -----------------------------------------------------------------------------
def get_engine() -> Engine:
    load_dotenv()

    user = os.getenv("DB_USER", "postgres")
    pwd = os.getenv("DB_PASSWORD", "mysecretpassword")
    db = os.getenv("DB_NAME", "med_delivery")
    port = os.getenv("DB_PORT", "5432")
    host = os.getenv("DB_HOST", "postgres")

    # Local development mode
    if os.getenv("RUN_LOCAL", "false").lower() == "true":
        host = "localhost"

    uri = f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}"
    logger.info(f"DB → {uri}")

    return create_engine(uri, pool_pre_ping=True)


engine = get_engine()

# -----------------------------------------------------------------------------
# Firebase Init
# -----------------------------------------------------------------------------
def init_firebase():
    if firebase_admin._apps:
        return

    cred_path = os.getenv("FIREBASE_CREDENTIALS")

    if not cred_path or not os.path.exists(cred_path):
        logger.warning("⚠️ Firebase credentials missing")
        return

    try:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        logger.info("Firebase initialized")
    except Exception as e:
        logger.error(f"Firebase init failed: {e}")


init_firebase()

# -----------------------------------------------------------------------------
# FastAPI App
# -----------------------------------------------------------------------------
app = FastAPI(
    title="Teryaq Delivery API",
    version="1.5",
    description="Backend for Patients, Drivers, Hospital, ML & Routing",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: tighten for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------------------------------------------------------
# OSRM CONFIG
# -----------------------------------------------------------------------------
OSRM_URL = os.getenv("OSRM_URL", "http://osrm_backend:5000")

# -----------------------------------------------------------------------------
# Root Endpoint
# -----------------------------------------------------------------------------
@app.get("/")
def root():
    return {"message": "🚀 Teryaq FastAPI backend running successfully!"}

# -----------------------------------------------------------------------------
# HOSPITALS
# -----------------------------------------------------------------------------
@app.get("/hospitals")
def get_hospitals():
    try:
        with engine.connect() as conn:
            rows = conn.execute(text("""
                SELECT hospital_id, name, address, email, phone_number, lat, lon
                FROM hospital
            """)).fetchall()

        return [
            {
                "id": r[0],
                "name": r[1],
                "address": r[2],
                "email": r[3],
                "phone_number": r[4],
                "lat": float(r[5]) if r[5] else None,
                "lon": float(r[6]) if r[6] else None,
            }
            for r in rows
        ]

    except Exception as e:
        raise HTTPException(500, f"Error: {e}")

# -----------------------------------------------------------------------------
# PATIENTS
# -----------------------------------------------------------------------------
@app.get("/patients")
def get_patients(limit: int = 50):
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text("""
                    SELECT patient_id, hospital_id, name, address, email, phone_number, gender, lat, lon
                    FROM patient LIMIT :l
                """),
                {"l": limit},
            ).fetchall()

        return [
            {
                "id": r[0],
                "hospital_id": r[1],
                "name": r[2],
                "address": r[3],
                "email": r[4],
                "phone_number": r[5],
                "gender": r[6],
                "lat": float(r[7]) if r[7] else None,
                "lon": float(r[8]) if r[8] else None,
            }
            for r in rows
        ]

    except Exception as e:
        raise HTTPException(500, f"Error: {e}")

# -----------------------------------------------------------------------------
# DRIVERS
# -----------------------------------------------------------------------------
@app.get("/drivers")
def get_drivers(limit: int = 50):
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text("""
                    SELECT driver_id, name, email, phone_number, address, lat, lon
                    FROM driver LIMIT :l
                """),
                {"l": limit},
            ).fetchall()

        return [
            {
                "id": r[0],
                "name": r[1],
                "email": r[2],
                "phone_number": r[3],
                "address": r[4],
                "lat": float(r[5]) if r[5] is not None else None,
                "lon": float(r[6]) if r[6] is not None else None,
            }
            for r in rows
        ]

    except Exception as e:
        raise HTTPException(500, f"Error: {e}")

# -----------------------------------------------------------------------------
# ALL ORDERS
# -----------------------------------------------------------------------------
@app.get("/orders")
def get_orders(limit: int = 50):
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text("""
                    SELECT order_id, driver_id, patient_id, hospital_id, status, created_at
                    FROM "Order" LIMIT :l
                """),
                {"l": limit},
            ).fetchall()

        return [
            {
                "id": r[0],
                "driver_id": r[1],
                "patient_id": r[2],
                "hospital_id": r[3],
                "status": r[4],
                "created_at": str(r[5]) if r[5] else None,
            }
            for r in rows
        ]

    except Exception as e:
        raise HTTPException(500, f"Error: {e}")

# -----------------------------------------------------------------------------
# MAP DATA
# -----------------------------------------------------------------------------
@app.get("/map-data")
def get_map_data():
    try:
        with engine.connect() as conn:
            hospitals = conn.execute(
                text("SELECT hospital_id, name, lat, lon FROM hospital")
            ).fetchall()
            patients = conn.execute(
                text("SELECT patient_id, name, lat, lon FROM patient")
            ).fetchall()
            drivers = conn.execute(
                text("SELECT driver_id, name, lat, lon FROM driver")
            ).fetchall()

        return {
            "hospitals": [
                {"id": x[0], "name": x[1], "lat": x[2], "lon": x[3]}
                for x in hospitals
            ],
            "patients": [
                {"id": x[0], "name": x[1], "lat": x[2], "lon": x[3]}
                for x in patients
            ],
            "drivers": [
                {"id": x[0], "name": x[1], "lat": x[2], "lon": x[3]}
                for x in drivers
            ],
        }

    except Exception as e:
        raise HTTPException(500, f"Error: {e}")

# -----------------------------------------------------------------------------
# DRIVER TODAY ORDERS (FOR MAP)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OSRM Route
# -----------------------------------------------------------------------------
@app.get("/route")
def get_route(from_lat: float, from_lon: float, to_lat: float, to_lon: float):
    try:
        url = (
            f"{OSRM_URL}/route/v1/driving/"
            f"{from_lon},{from_lat};{to_lon},{to_lat}"
            f"?overview=full&geometries=geojson"
        )

        r = requests.get(url, timeout=10)
        r.raise_for_status()
        data = r.json()

        if "routes" not in data or len(data["routes"]) == 0:
            raise HTTPException(400, "No route found")

        coords = data["routes"][0]["geometry"]["coordinates"]
        points = [{"lat": lat, "lon": lon} for lon, lat in coords]

        return {"points": points}

    except Exception as e:
        raise HTTPException(500, f"OSRM Error: {e}")

# -----------------------------------------------------------------------------
# INCLUDE ROUTERS
# -----------------------------------------------------------------------------
app.include_router(auth_router)
app.include_router(patient_router)
app.include_router(ml_router)
app.include_router(driver_router)
app.include_router(iot_router)
app.include_router(hospital_router)
