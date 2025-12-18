# api/routes/auth_router.py

import os
import uuid
import requests
import psycopg2
import pyrebase
import firebase_admin

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from firebase_admin import credentials, auth

from schemas import SignUpSchema, LoginSchema

router = APIRouter(prefix="/auth", tags=["Authentication"])

SERVICE_KEY_PATH = "/app/secrets/serviceAccountKey.json"

if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_KEY_PATH)
    firebase_admin.initialize_app(cred)

firebaseConfig = {
  "apiKey": "DUMMY_API_KEY_DO_NOT_USE",
  "authDomain": "teryaq-demo.firebaseapp.com",
  "projectId": "teryaq-demo-project",
  "storageBucket": "teryaq-demo.appspot.com",
  "messagingSenderId": "123456789000",
  "appId": "1:123456789000:android:aaaaaaaaaaaaaaaaaaaaaa",
  "databaseURL": ""
}


firebase = pyrebase.initialize_app(firebaseConfig)
firebase_auth = firebase.auth()

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_NAME = os.getenv("DB_NAME", "med_delivery")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASSWORD", "mysecretpassword")

def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS
    )

# =====================================================
# 🔹 NEW: Reusable Firebase Token Verification
# =====================================================
def verify_firebase_token(id_token: str):
    try:
        decoded = auth.verify_id_token(id_token)
        return decoded  # uid, email, etc.
    except Exception:
        return None

# =====================================================
# 🔹 Helper
# =====================================================
def get_default_hospital_for_city(city_name: str):
    if city_name and city_name.strip().lower() == "riyadh":
        return "HOSP001"
    return "HOSP001"

# =====================================================
# 🔹 Register User
# =====================================================
@router.post('/register')
async def register_user(user_data: SignUpSchema):
    fake_email = f"{user_data.national_id}@teryaq.com"
    password = user_data.password

    try:
        user = auth.create_user(
            email=fake_email,
            password=password
        )
        firebase_uid = user.uid

        hospital_id = getattr(user_data, "hospital_id", None)
        if not hospital_id:
            hospital_id = get_default_hospital_for_city(user_data.city)

        conn = get_db_connection()
        cur = conn.cursor()

        patient_id = "PAT" + uuid.uuid4().hex[:29].upper()

        cur.execute("""
            INSERT INTO Patient (
                patient_id, national_id, hospital_id, name, address, email,
                phone_number, gender, lat, lon
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NULL, NULL)
        """, (
            patient_id,
            user_data.national_id,
            hospital_id,
            user_data.name,
            user_data.address,
            fake_email,
            user_data.phone_number,
            user_data.gender
        ))

        conn.commit()
        cur.close()
        conn.close()

        return JSONResponse(
            content={
                "message": "User registered successfully",
                "firebase_uid": firebase_uid,
                "patient_id": patient_id,
                "national_id": user_data.national_id,
                "hospital_id": hospital_id
            },
            status_code=201
        )

    except firebase_admin.auth.EmailAlreadyExistsError:
        raise HTTPException(status_code=400, detail="Account already exists for this national ID")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")


# =====================================================
# 🔹 Login
# =====================================================
@router.post('/login')
async def login_user(user_data: LoginSchema):
    fake_email = f"{user_data.national_id}@teryaq.com"
    password = user_data.password

    try:
        login_result = firebase_auth.sign_in_with_email_and_password(fake_email, password)
        token = login_result["idToken"]

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT patient_id, name, national_id, hospital_id, address,
                   phone_number, gender, email, lat, lon
            FROM Patient
            WHERE national_id=%s
        """, (user_data.national_id,))

        patient = cur.fetchone()
        cur.close()
        conn.close()

        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        return {
            "token": token,
            "patient": {
                "patient_id": patient[0],
                "name": patient[1],
                "national_id": patient[2],
                "hospital_id": patient[3],
                "address": patient[4],
                "phone_number": patient[5],
                "gender": patient[6],
                "email": patient[7],
                "lat": patient[8],
                "lon": patient[9]
            }
        }

    except requests.exceptions.HTTPError:
        raise HTTPException(status_code=401, detail="Invalid National ID or password")

    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Login failed: {str(e)}")


# =====================================================
# 🔹 Protected Endpoint
# =====================================================
@router.post('/protected')
async def validate_token(request: Request):
    jwt_token = request.headers.get("authorization")

    if not jwt_token:
        raise HTTPException(status_code=400, detail="Authorization header missing")

    try:
        decoded = auth.verify_id_token(jwt_token)
        return {"firebase_uid": decoded["uid"]}

    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
