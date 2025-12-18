# api/schemas.py

from datetime import date, datetime
from typing import List, Optional, Literal, Dict, Any

from pydantic import BaseModel, Field

# ============================================================
# 🔐 AUTH SCHEMAS (PATIENT / HOSPITAL / DRIVER)
# ============================================================

class SignUpSchema(BaseModel):
    """
    Generic sign-up schema for any user type in Teryaq:
      - patient
      - hospital
      - driver
      - admin (optional if you need it)

    This schema can be used by an /auth/signup endpoint that:
      1. Creates the Firebase user (email = national_id + domain)
      2. Stores the profile in PostgreSQL in the correct table.
    """
    national_id: str
    password: str
    name: str

    # Optional profile fields (used more for patients / hospitals)
    address: Optional[str] = None
    phone_number: Optional[str] = None
    gender: Optional[str] = None
    city: Optional[str] = None
    email: Optional[str] = None

    # Role decides which table / logic to use
    #   - "patient"   → Patient table
    #   - "hospital"  → Hospital table
    #   - "driver"    → Driver table
    #   - "admin"     → Admin/staff table (if needed)
    role: Literal["patient", "hospital", "driver", "admin"] = "patient"

    # Optional FCM token for push notifications registration on sign-up
    device_token: Optional[str] = None


class LoginSchema(BaseModel):
    """
    Generic login schema based on national_id + password.
    """
    national_id: str
    password: str

    # To distinguish which client is logging in from a single endpoint
    role: Literal["patient", "hospital", "driver", "admin"] = "patient"

    # Optional FCM token so backend can store/update device for notifications
    device_token: Optional[str] = None


class TokenResponse(BaseModel):
    """
    Standard token response if you expose an /auth/login endpoint.
    """
    access_token: str
    token_type: str = "bearer"


# ============================================================
# 👤 PATIENT SCHEMAS (CORE – HOSPITAL SIDE)
# ============================================================

class PatientBase(BaseModel):
    national_id: str
    name: str
    phone_number: Optional[str] = None
    address: Optional[str] = None
    email: Optional[str] = None
    gender: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None

    # DOB موجود عشان يجي في الـ Create و Out
    birth_date: Optional[date] = None


class PatientCreate(PatientBase):
    """
    Used when hospital creates a new patient record from the app:
    POST /hospital/patients
    """
    pass


class PatientOut(PatientBase):
    """
    Response for patient records returned to the hospital app.
    """
    patient_id: str
    hospital_id: Optional[str] = None
    status: str
    created_at: datetime


class StatusUpdate(BaseModel):
    """
    Simple status update payload:
      { "status": "active" } or { "status": "inactive" }
    """
    status: str


# ============================================================
# 🏥 HOSPITAL DASHBOARD
# ============================================================

class HospitalDashboardSummary(BaseModel):
    """
    Summary card for hospital home/dashboard.

    Used by:
      - GET /hospital/dashboard
    """
    hospital_id: str
    active_patients: int
    new_patients_today: int
    active_prescriptions: int
    orders_waiting_approval: int


# ============================================================
# 💊 MEDICATIONS
# ============================================================

class MedicationOut(BaseModel):
    """
    Medication information used in dropdowns and prescription cards.
    """
    medication_id: str
    name: str

    description: Optional[str] = None
    information_source: Optional[str] = None

    # Optional expiry date (if stored on medication level)
    exp_date: Optional[datetime] = None

    # Cold-chain / excursion data
    max_time_exertion: Optional[str] = None
    min_temp_range_excursion: Optional[float] = None
    max_temp_range_excursion: Optional[float] = None
    return_to_the_fridge: Optional[bool] = None
    max_time_safe_use: Optional[int] = None

    additional_actions_detail: Optional[str] = None
    risk_level: Optional[str] = None
    created_at: Optional[datetime] = None


# ============================================================
# 📜 PRESCRIPTIONS
# ============================================================

class PrescriptionCreate(BaseModel):
    """
    Request body for creating a new prescription from hospital app.
    """
    patient_national_id: str
    medication_id: str
    instructions: str
    prescribing_doctor: str
    expiration_date: Optional[datetime] = None
    reorder_threshold: Optional[int] = None

    class Config:
        extra = "ignore"


class PatientPrescriptionSummary(BaseModel):
    """
    Small summary used in PatientProfileScreen card list.
    """
    prescription_id: str
    medicine_name: str
    status: str                        # "Active" / "Expired" / "Invalid"

    refill_limit_text: Optional[str] = None

    start_date: Optional[date] = None
    end_date: Optional[date] = None
    created_at: Optional[date] = None

    doctor_name: Optional[str] = None
    is_valid: Optional[bool] = None
    gender: Optional[str] = None


class PatientProfileOut(BaseModel):
    """
    Full patient profile + list of prescriptions.
    """
    patient_id: str
    national_id: str
    name: str
    phone_number: Optional[str] = None
    email: Optional[str] = None
    status: str
    gender: Optional[str] = None
    birth_date: Optional[date] = None

    prescriptions: List[PatientPrescriptionSummary]


class PrescriptionCardOut(BaseModel):
    """
    Card used in ManagePrescriptions screen list.
    """
    prescription_id: str
    name: str               # medication name
    code: str               # short code from prescription_id
    patient: str            # patient name

    refill_limit: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    created_at: Optional[date] = None

    doctor_name: Optional[str] = None
    status: str             # Active / Expired / Invalid
    is_valid: Optional[bool] = None


class PrescriptionDetailOut(BaseModel):
    """
    Detailed view of a single prescription.
    """
    prescription_id: str
    medication_name: str
    patient_name: str
    patient_national_id: str

    patient_gender: Optional[str] = None
    patient_birth_date: Optional[date] = None
    patient_phone_number: Optional[str] = None
    hospital_name: Optional[str] = None

    instructions: str
    prescribing_doctor: str
    expiration_date: Optional[datetime] = None
    reorder_threshold: Optional[int] = None
    status: str
    created_at: datetime


# ============================================================
# 📦 ORDERS (HOSPITAL SIDE)
# ============================================================

class OrderCreate(BaseModel):
    """
    Request body to create a new order from hospital app.
    """
    patient_id: Optional[str] = None
    patient_national_id: Optional[str] = None
    prescription_id: str

    priority_level: Optional[str] = "Normal"   # Normal / High / etc.
    order_type: Optional[str] = "delivery"     # delivery / pickup
    notes: Optional[str] = None
    otp: Optional[int] = None

    class Config:
        extra = "ignore"


class OrderSummary(BaseModel):
    """
    Lightweight representation for hospital orders list.
    """
    order_id: str
    code: str
    medicine_name: str
    patient_name: str
    placed_at: date
    status: str
    priority_level: str
    can_generate_report: bool


class OrderDetailOut(BaseModel):
    """
    Detailed order view for hospital (OrderReviewScreen, etc.).
    """
    order_id: str
    code: str
    status: str
    priority_level: str

    placed_at: datetime
    delivered_at: Optional[datetime] = None

    # Patient / Medication / Hospital
    medicine_name: str
    patient_name: str
    patient_national_id: str
    hospital_name: str

    # Prescription info
    prescription_id: Optional[str] = None
    instructions: Optional[str] = None
    prescribing_doctor: Optional[str] = None
    expiration_date: Optional[datetime] = None
    reorder_threshold: Optional[int] = None
    refill_limit: Optional[int] = None

    # Location
    location_city: Optional[str] = None
    location_description: Optional[str] = None
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None

    # Hospital-side delivery recommendation
    delivery_type: str                   # delivery / pickup
    delivery_time: str                   # morning / evening
    system_recommendation: str           # delivery / pickup

    otp: Optional[int] = None
    notes: Optional[str] = None


class OrderDecisionIn(BaseModel):
    """
    Hospital decision on an order.
    """
    decision: str   # "accept" / "deny"


# ============================================================
# 📄 ORDER REPORT (HOSPITAL SIDE)
# ============================================================

class DeliveryDetail(BaseModel):
    """
    Single row inside the delivery details timeline for an order.
    """
    status: str
    description: str
    duration: str
    stability: str
    condition: str


class OrderReportOut(BaseModel):
    """
    Full order report used by:
      - GET /hospital/orders/{order_id}/report
    """
    report_id: str
    type: str

    generated: datetime

    order_id: str
    order_code: str
    order_type: Optional[str] = None
    order_status: str

    created_at: datetime
    delivered_at: Optional[datetime] = None

    otp_code: str
    verified: bool
    priority: str

    patient_name: str
    phone_number: Optional[str] = None
    hospital_name: str
    medication_name: str

    # Medication + cold-chain data
    allowed_temp: Optional[str] = None   # e.g. "2–8°C"
    max_excursion: Optional[str] = None  # e.g. "30 minutes"
    return_to_fridge: Optional[str] = None  # "Yes" / "No"

    delivery_details: List[DeliveryDetail]


# ============================================================
# (OPTIONAL) ML SCHEMAS
# ============================================================

class MLRequest(BaseModel):
    """
    Generic ML request wrapper used by /ml/predict.
    """
    data: Dict[str, Any]


class DeliveryFeatures(BaseModel):
    """
    Structured features for ML-based delivery vs pickup prediction.
    """
    patient_id: str
    hospital_id: str

    patient_gender: Optional[str] = None
    patient_age: Optional[int] = None
    risk_level: Optional[str] = None

    order_type_requested: Optional[str] = "delivery"
    priority_level_requested: Optional[str] = "Normal"


class DeliveryPredictionOut(BaseModel):
    """
    Output for ML delivery decision and PatientOrderReview screen.
    """
    delivery_type: str                      # "pickup" or "delivery"
    score: Optional[float] = None
    raw: Dict[str, Any] = Field(default_factory=dict)


# ============================================================
# 👤 PATIENT APP (MOBILE) SCHEMAS
#   - Used by /patient/... endpoints for the patient mobile app
# ============================================================

class PatientAppProfileOut(BaseModel):
    """
    Basic profile for the patient mobile app.
    """
    patient_id: str
    national_id: str
    name: str

    gender: Optional[str] = None
    birth_date: Optional[date] = None

    phone_number: Optional[str] = None
    email: Optional[str] = None
    marital_status: Optional[str] = None

    address: Optional[str] = None
    city: Optional[str] = None

    # Primary hospital name, resolved from hospital_id in the router
    primary_hospital: Optional[str] = None


class PatientHomeNotification(BaseModel):
    """
    Single notification message for the small notification card
    on the PatientHome screen.
    """
    message: str


class PatientHomeRefill(BaseModel):
    """
    Next refill information used in the 'your_next_refill' card.
    """
    medication_name: str
    days_left: int


class PatientHomeRecentOrder(BaseModel):
    """
    One row inside the order status card on PatientHome.
    """
    status: str      # e.g. "On Delivery", "Delivered"
    code: str        # short order code like "UOT-847362"


class PatientHomeSummary(BaseModel):
    """
    Full summary for the PatientHome dashboard.
    """
    patient_name: str
    next_refill: Optional[PatientHomeRefill] = None
    notifications: List[PatientHomeNotification] = []
    recent_orders: List[PatientHomeRecentOrder] = []


# ============================================================
# 🔔 PATIENT APP – FULL NOTIFICATION HISTORY
# ============================================================

class PatientNotificationOut(BaseModel):
    """
    Notification used by PatientNotificationsScreen.

    level:
      - "success" → green
      - "warning" → yellow
      - "danger"  → red
    """
    title: str
    description: str
    level: Literal["success", "warning", "danger"] = "warning"
    notification_time: Optional[datetime] = None

    class Config:
        orm_mode = True


# ============================================================
# 📦 PATIENT APP – ORDERS & PRESCRIPTIONS
# ============================================================

class PatientOrderOut(BaseModel):
    """
    Order summary used by PatientOrders screen.

    - status          → mapped, patient-friendly status label
    - code            → short order code (used as orderId in Flutter)
    - medication_name → medicine name shown in the card
    - placed_at       → order creation time
    - delivered_at    → delivery time (null if not delivered yet)
    """
    status: str
    code: str
    medication_name: str
    placed_at: Optional[datetime] = None
    delivered_at: Optional[datetime] = None


class PatientPrescriptionCardOut(BaseModel):
    """
    Prescription card used by the PatientPrescriptions screen in the patient app.
    """
    prescription_id: str
    medicine: str
    dose: Optional[str] = None
    days_left: int
    doctor: Optional[str] = None
    needs_new_prescription: bool = False


# ============================================================
# 📦 PATIENT APP – ORDER REVIEW & CREATION
# ============================================================

class PatientOrderReviewPrescription(BaseModel):
    """
    Prescription section for the PatientOrderReview screen.
    All fields are strings to keep the Flutter UI simple.
    """
    prescription_id: str
    medicine: str
    doctor: str
    hospital: str
    instruction: str
    valid_until: Optional[datetime] = None
    refill_limit: Optional[int] = None # e.g. "3 refills remaining"


class PatientOrderReviewLocation(BaseModel):
    """
    Location section for the PatientOrderReview screen.
    """
    label: str              # e.g. "Home"
    address: str            # full address string


class PatientOrderReviewOut(BaseModel):
    """
    Full payload for:
      GET /patient/{national_id}/order-review/{prescription_id}
    """
    prescription: PatientOrderReviewPrescription
    location: PatientOrderReviewLocation
    ml: DeliveryPredictionOut


class PatientOrderCreateIn(BaseModel):
    """
    Simple body for Patient app to create an order from a prescription.
    Used by POST /patient/{national_id}/orders.
    """
    prescription_id: str
    order_type: Optional[str] = "delivery"      # "delivery" / "pickup"
    priority_level: Optional[str] = "Normal"
    notes: Optional[str] = None


# ============================================================
# 🗺 PATIENT APP – DASHBOARD MAP
# ============================================================

class MapPoint(BaseModel):
    """
    Simple lat/lon pair used for patient & driver positions on the map.
    """
    lat: Optional[float] = None
    lon: Optional[float] = None


class PatientDashboardMapNotification(BaseModel):
    """
    Notification row used in the small list under the map on PatientDashboard.
    """
    notification_id: str
    order_id: Optional[str] = None
    notification_content: str
    notification_type: Optional[str] = None
    notification_time: Optional[datetime] = None


class PatientDashboardMapOut(BaseModel):
    """
    Full payload for:
      GET /patient/{national_id}/dashboard-map
    """
    order_id: Optional[str] = None
    order_code: Optional[str] = None
    status: Optional[str] = None

    patient: Optional[MapPoint] = None
    driver: Optional[MapPoint] = None

    temperature: Optional[str] = None
    arrival_time: Optional[str] = None
    remaining_stability: Optional[str] = None

    notifications: List[PatientDashboardMapNotification] = []


# ============================================================
# 📄 PATIENT APP – DELIVERY REPORT (MOBILE)
# ============================================================

class PatientOrderReportOut(BaseModel):
    """
    Delivery report for the patient mobile app.

    Used by:
      - GET /patient/{national_id}/reports/{order_id_or_code}
    """
    # Report meta
    id: str
    type: str

    generated: str  # already formatted

    # Order info
    orderID: str
    orderType: Optional[str] = None
    orderStatus: str

    createdAt: str
    deliveredAt: Optional[str] = None

    # OTP and verification
    otpCode: str
    verified: bool
    priority: str            # "High" / "Normal" / etc.

    # Parties
    patientName: str
    phoneNumber: Optional[str] = None
    hospitalName: str
    medicationName: str

    # Medication + cold-chain information (all strings)
    allowedTemp: Optional[str] = None
    maxExcursion: Optional[str] = None
    returnToFridge: Optional[str] = None

    # Timeline rows
    deliveryDetails: List[DeliveryDetail]
