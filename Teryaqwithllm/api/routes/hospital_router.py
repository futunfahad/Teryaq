# routes/hospital_router.py

from datetime import date, datetime
from typing import List, Optional
import random
import os

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from sqlalchemy import or_, cast, String

from database import get_db
import models
import schemas
from ml.predictor import predict_sample


PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORTS_DIR = "/app/generated_reports"
os.makedirs(REPORTS_DIR, exist_ok=True)


router = APIRouter(
    prefix="/hospital",
    tags=["hospital"],
)

# =========================================================
# ✅ ORDER STATUS NORMALIZATION (FIX FILTERS + UI STATUSES)
# =========================================================
# The Hospital Flutter UI often uses labels like:
#   "Pending", "Accepted", "On Delivery", "Delivered", "Delivery Failed", "Rejected"
# بينما قاعدة البيانات قد تستخدم:
#   pending, accepted, on_delivery, on_route, delivered, delivery_failed, rejected
# وبعض الداتا القديمة قد تحتوي:
#   progress, completed
#
# هذه المابّينق تضمن:
#   - فلترة /orders?status=... تعمل حتى مع المسافات/الـcase/الـlegacy
#   - status الراجع للـUI يكون ثابت ومفهوم

_STATUS_CANON_OUT = {
    "pending": "pending",
    "accepted": "accepted",
    "on_delivery": "on_delivery",
    "on_route": "on_delivery",      # hospital UI usually groups this under On Delivery
    "delivered": "delivered",
    "delivery_failed": "delivery_failed",
    "rejected": "rejected",
    "cancelled": "rejected",
    "canceled": "rejected",
    # legacy
    "progress": "on_delivery",
    "completed": "delivered",
}

_STATUS_PARAM_TO_DB_SET = {
    # UI labels / synonyms -> DB statuses to include
    "pending": ["pending"],
    "rejected": ["rejected"],
    "accepted": ["accepted"],
    "on_delivery": ["on_delivery", "on_route", "progress"],  # include legacy progress
    "on_route": ["on_route"],
    "delivered": ["delivered", "completed"],
    "delivery_failed": ["delivery_failed"],
    # allow "all" to mean no filter
    "all": [],
}

_STATUS_ALIASES = {
    # normalize inputs
    "on delivery": "on_delivery",
    "on_delivery": "on_delivery",
    "ondelivery": "on_delivery",
    "on-route": "on_route",
    "on route": "on_route",
    "on_route": "on_route",
    "delivery failed": "delivery_failed",
    "delivery_failed": "delivery_failed",
    "deliveryfailed": "delivery_failed",
    "failed": "delivery_failed",
    "complete": "delivered",
    "completed": "delivered",
    "delivered": "delivered",
    "accept": "accepted",
    "accepted": "accepted",
    "progress": "on_delivery",  # legacy label
    "deny": "rejected",
    "denied": "rejected",
    "reject": "rejected",
    "rejected": "rejected",
    "pending": "pending",
    "all": "all",
}


def _norm_status_token(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    s = str(value).strip().lower()
    s = s.replace("-", " ").replace("_", " ")
    s = " ".join(s.split())
    return _STATUS_ALIASES.get(s, s.replace(" ", "_"))


def _status_filter_db_set(status_param: str) -> Optional[List[str]]:
    """
    Convert UI filter param into a list of DB statuses to match.
    Returns None if no filter should be applied.
    """
    token = _norm_status_token(status_param)
    if not token or token == "all":
        return None

    # If it's a known canonical key, return its DB set
    if token in _STATUS_PARAM_TO_DB_SET:
        return _STATUS_PARAM_TO_DB_SET[token]

    # Otherwise treat it as direct db status
    return [token]


def _normalize_order_status_out(db_status: Optional[str]) -> str:
    token = _norm_status_token(db_status) or ""
    token = token.replace(" ", "_")
    return _STATUS_CANON_OUT.get(token, token)


def _can_generate_report_from_status(db_status: Optional[str]) -> bool:
    # Hospital reports عادةً تكون متاحة بعد:
    # delivered / delivery_failed / rejected
    out = _normalize_order_status_out(db_status)
    return out in ("delivered", "delivery_failed", "rejected")


# =========================================================
# Helper: convert SQLAlchemy Patient -> PatientOut
# =========================================================


def to_patient_out(patient: models.Patient) -> schemas.PatientOut:
    """
    Convert a SQLAlchemy Patient model into PatientOut schema.

    Ensures:
      - UUID fields are converted to strings
      - hospital_id is None instead of string "None"
      - birth_date is returned as a date object
    """
    hospital_id = getattr(patient, "hospital_id", None)

    birth_date_value = getattr(patient, "birth_date", None)
    if isinstance(birth_date_value, datetime):
        birth_date_value = birth_date_value.date()

    return schemas.PatientOut(
        patient_id=str(patient.patient_id),
        national_id=patient.national_id,
        hospital_id=str(hospital_id) if hospital_id is not None else None,
        name=patient.name,
        address=patient.address,
        email=patient.email,
        phone_number=patient.phone_number,
        gender=patient.gender,
        birth_date=birth_date_value,
        lat=patient.lat,
        lon=patient.lon,
        status=patient.status,
        created_at=patient.created_at,
    )


# =========================================================
# Helper: normalize prescription status
# =========================================================


def _compute_prescription_status(pres, now: datetime) -> str:
    """
    Determine prescription status based on explicit status column
    or fallback to expiration_date logic.
    """
    # If there is an explicit status, use it
    if hasattr(pres, "status") and pres.status:
        return pres.status

    # Otherwise derive status from expiration_date
    if getattr(pres, "expiration_date", None) and pres.expiration_date < now:
        return "Expired"
    return "Active"


# =========================================================
# Helper: get Prescription by UUID or short code
# =========================================================


def _get_prescription_by_identifier(
    identifier: str,
    db: Session,
):
    """
    Resolve a Prescription by:
      1) Exact UUID match (prescription_id == identifier)
      2) Short code match (CAST(prescription_id AS TEXT) LIKE 'identifier%')
         This allows the UI to send only the first 8 chars as a code.
    """
    # 1) Try full UUID match
    pres = (
        db.query(models.Prescription)
        .filter(models.Prescription.prescription_id == identifier)
        .first()
    )
    if pres:
        return pres

    # 2) Try prefix match on UUID text
    pres = (
        db.query(models.Prescription)
        .filter(
            cast(models.Prescription.prescription_id, String).like(
                f"{identifier}%"
            )
        )
        .first()
    )
    return pres


# =========================================================
# 0) AUTH LOOKUP
# =========================================================


@router.get("/auth/lookup")
def lookup_hospital_id_by_national(
    national_id: str,
    db: Session = Depends(get_db),
):
    """
    Resolve hospital_id by hospital national_id (used after Firebase login).
    """
    hospital = (
        db.query(models.Hospital)
        .filter(models.Hospital.national_id == national_id)
        .first()
    )
    if not hospital:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Hospital not found",
        )

    return {
        "hospital_id": str(hospital.hospital_id),
        "national_id": hospital.national_id,
        "name": hospital.name,
    }


# =========================================================
# 1) HOSPITAL HOME DASHBOARD
# =========================================================


@router.get("/dashboard", response_model=schemas.HospitalDashboardSummary)
def get_hospital_dashboard(
    hospital_id: str,  # UUID as string
    db: Session = Depends(get_db),
):
    """
    Return high-level summary for the Hospital Home screen:

      - active_patients
      - new_patients_today
      - active_prescriptions
      - orders_waiting_approval
    """
    today = date.today()

    # Active patients
    active_patients = (
        db.query(models.Patient)
        .filter(
            models.Patient.hospital_id == hospital_id,
            models.Patient.status == "active",
        )
        .count()
    )

    # New patients created today
    new_patients_today = (
        db.query(models.Patient)
        .filter(
            models.Patient.hospital_id == hospital_id,
            models.Patient.created_at
            >= datetime.combine(today, datetime.min.time()),
        )
        .count()
    )

    # Active prescriptions
    pres_query = db.query(models.Prescription).filter(
        models.Prescription.hospital_id == hospital_id
    )

    if hasattr(models.Prescription, "status"):
        pres_query = pres_query.filter(models.Prescription.status == "active")

    active_prescriptions = pres_query.count()

    # Orders waiting for hospital approval (pending status)
    orders_waiting_approval = (
        db.query(models.Order)
        .filter(
            models.Order.hospital_id == hospital_id,
            models.Order.status == "pending",
        )
        .count()
    )

    return schemas.HospitalDashboardSummary(
        hospital_id=hospital_id,
        active_patients=active_patients,
        new_patients_today=new_patients_today,
        active_prescriptions=active_prescriptions,
        orders_waiting_approval=orders_waiting_approval,
    )


# =========================================================
# 2) PATIENTS – LIST / CREATE / LOOKUP / PROFILE / STATUS
# =========================================================


@router.get("/patients", response_model=List[schemas.PatientOut])
def list_patients(
    hospital_id: str,
    status: str = "All",  # "All" | "Active" | "Inactive"
    search: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """
    List patients for the ManagePatients screen.

    Supports:
      - status filter (All / Active / Inactive)
      - text search by name or national_id
    """
    q = db.query(models.Patient).filter(
        models.Patient.hospital_id == hospital_id
    )

    if status != "All":
        status_db = status.lower()
        q = q.filter(models.Patient.status == status_db)

    if search:
        like = f"%{search}%"
        q = q.filter(
            or_(
                models.Patient.name.ilike(like),
                models.Patient.national_id.ilike(like),
            )
        )

    patients = q.order_by(models.Patient.created_at.desc()).all()
    return [to_patient_out(p) for p in patients]


@router.post(
    "/patients",
    response_model=schemas.PatientOut,
    status_code=status.HTTP_201_CREATED,
)
def add_patient(
    payload: schemas.PatientCreate,
    hospital_id: str,
    db: Session = Depends(get_db),
):
    """
    Create a new patient under the given hospital.

    Enforces:
      - national_id must be globally unique across all patients.
    """
    existing = (
        db.query(models.Patient)
        .filter(models.Patient.national_id == payload.national_id)
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A patient with this national_id already exists.",
        )

    patient = models.Patient(
        national_id=payload.national_id,
        hospital_id=hospital_id,
        name=payload.name,
        address=payload.address,
        email=payload.email,
        phone_number=payload.phone_number,
        gender=payload.gender,
        birth_date=payload.birth_date,
        lat=payload.lat,
        lon=payload.lon,
        status="active",
    )
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return to_patient_out(patient)


@router.get(
    "/patients/by-national/{national_id}",
    response_model=schemas.PatientOut,
)
def get_patient_by_national_id(
    national_id: str,
    db: Session = Depends(get_db),
):
    """
    Look up a single patient by national_id (used in Nafath-like flows).
    """
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.national_id == national_id)
        .first()
    )
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found",
        )
    return to_patient_out(patient)


@router.get(
    "/patients/search",
    response_model=List[schemas.PatientOut],
)
def search_patients_by_id_prefix(
    id_prefix: str,
    limit: int = 10,
    db: Session = Depends(get_db),
):
    """
    Auto-complete style search by national_id prefix.
    """
    patients = (
        db.query(models.Patient)
        .filter(models.Patient.national_id.like(f"{id_prefix}%"))
        .order_by(models.Patient.national_id)
        .limit(limit)
        .all()
    )
    return [to_patient_out(p) for p in patients]


@router.get(
    "/patients/{patient_id}/profile",
    response_model=schemas.PatientProfileOut,
)
def get_patient_profile(
    patient_id: str,
    db: Session = Depends(get_db),
):
    """
    Return data for the Patient Profile screen:

      - basic patient info
      - list of prescriptions with:
          * status ("Active" / "Expired" / "Invalid")
          * refill_limit_text
          * start_date / end_date (date only)
          * created_at (date only)
          * doctor_name
    """
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.patient_id == patient_id)
        .first()
    )
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found",
        )

    prescriptions = (
        db.query(models.Prescription, models.Medication)
        .join(
            models.Medication,
            models.Medication.medication_id
            == models.Prescription.medication_id,
        )
        .filter(models.Prescription.patient_id == patient_id)
        .order_by(models.Prescription.created_at.desc())
        .all()
    )

    pres_summaries: List[schemas.PatientPrescriptionSummary] = []
    now = datetime.utcnow()

    for pres, med in prescriptions:
        status_value = _compute_prescription_status(pres, now)
        is_valid = status_value == "Active"

        refill_text = None
        if hasattr(pres, "refill_limit") and pres.refill_limit is not None:
            refill_text = f"{pres.refill_limit} refills remaining"
        elif getattr(pres, "reorder_threshold", None) is not None:
            refill_text = f"{pres.reorder_threshold} refills remaining"

        raw_start = getattr(pres, "start_date", pres.created_at)
        if isinstance(raw_start, datetime):
            start_date = raw_start.date()
        else:
            start_date = raw_start

        raw_end = getattr(pres, "expiration_date", None)
        if isinstance(raw_end, datetime):
            end_date = raw_end.date()
        else:
            end_date = raw_end

        created_date = (
            pres.created_at.date()
            if isinstance(pres.created_at, datetime)
            else pres.created_at
        )

        pres_summaries.append(
            schemas.PatientPrescriptionSummary(
                prescription_id=str(pres.prescription_id),
                medicine_name=med.name,
                doctor_name=getattr(pres, "prescribing_doctor", None),
                status=status_value,
                is_valid=is_valid,
                refill_limit_text=refill_text,
                start_date=start_date,
                end_date=end_date,
                created_at=created_date,
                gender=patient.gender,
            )
        )

    birth_date_value = getattr(patient, "birth_date", None)
    if isinstance(birth_date_value, datetime):
        birth_date_value = birth_date_value.date()

    return schemas.PatientProfileOut(
        patient_id=str(patient.patient_id),
        national_id=patient.national_id,
        name=patient.name,
        phone_number=patient.phone_number,
        email=patient.email,
        status=patient.status,
        gender=patient.gender,
        birth_date=birth_date_value,
        prescriptions=pres_summaries,
    )


@router.patch(
    "/patients/{patient_id}/status",
    response_model=schemas.PatientOut,
)
def update_patient_status(
    patient_id: str,
    payload: schemas.StatusUpdate,
    db: Session = Depends(get_db),
):
    """
    Soft-delete style update of patient.status
    (for example, set to "inactive").
    """
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.patient_id == patient_id)
        .first()
    )
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found",
        )

    patient.status = payload.status.lower()
    db.commit()
    db.refresh(patient)
    return to_patient_out(patient)


# =========================================================
# 3) MEDICATIONS (Dropdown in AddPrescriptionScreen)
# =========================================================


@router.get(
    "/medications",
    response_model=List[schemas.MedicationOut],
)
def list_medications(
    # ✅ Accept hospital_id (optional) so Flutter can send it without confusion
    hospital_id: Optional[str] = None,
    q: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """
    Return a list of medications for dropdowns.

    Optionally filters by medication name.

    Note:
      - hospital_id is optional; current implementation returns global medication list.
      - If later you want per-hospital meds, you can filter by hospital_id here (append-only).
    """
    query = db.query(models.Medication)
    if q:
        query = query.filter(models.Medication.name.ilike(f"%{q}%"))
    meds = query.order_by(models.Medication.name).all()

    result: List[schemas.MedicationOut] = []
    for med in meds:
        result.append(
            schemas.MedicationOut(
                medication_id=str(med.medication_id),
                name=med.name,
                description=getattr(med, "description", None),
                information_source=getattr(
                    med, "information_source", None
                ),
                exp_date=getattr(med, "exp_date", None),
                max_time_exertion=str(getattr(med, "max_time_exertion", None))
                if getattr(med, "max_time_exertion", None) is not None
                else None,
                min_temp_range_excursion=getattr(
                    med, "min_temp_range_excursion", None
                ),
                max_temp_range_excursion=getattr(
                    med, "max_temp_range_excursion", None
                ),
                return_to_the_fridge=getattr(
                    med, "return_to_the_fridge", None
                ),
                max_time_safe_use=getattr(
                    med, "max_time_safe_use", None
                ),
                additional_actions_detail=getattr(
                    med, "additional_actions_detail", None
                ),
                risk_level=getattr(med, "risk_level", None),
                created_at=getattr(med, "created_at", None),
            )
        )
    return result


# =========================================================
# 4) PRESCRIPTIONS – CREATE / LIST / DETAIL / INVALIDATE / DELETE
# =========================================================


@router.post(
    "/prescriptions",
    response_model=schemas.PrescriptionDetailOut,
    status_code=status.HTTP_201_CREATED,
)
def create_prescription(
    payload: schemas.PrescriptionCreate,
    hospital_id: str,
    db: Session = Depends(get_db),
):
    """
    Create a new prescription for a patient in this hospital.

    Validations:
      - The patient (by national_id) must belong to this hospital.
      - The medication_id must exist.
    """
    patient = (
        db.query(models.Patient)
        .filter(
            models.Patient.national_id == payload.patient_national_id,
            models.Patient.hospital_id == hospital_id,
        )
        .first()
    )
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found for this hospital.",
        )

    medication = (
        db.query(models.Medication)
        .filter(models.Medication.medication_id == payload.medication_id)
        .first()
    )
    if not medication:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Medication not found.",
        )

    pres = models.Prescription(
        hospital_id=hospital_id,
        medication_id=payload.medication_id,
        patient_id=patient.patient_id,
        expiration_date=payload.expiration_date,
        reorder_threshold=payload.reorder_threshold,
        instructions=payload.instructions,
        prescribing_doctor=payload.prescribing_doctor,
    )

    # ✅ If model supports status, default it to Active (safe append-only behavior)
    if hasattr(pres, "status") and not getattr(pres, "status", None):
        try:
            pres.status = "Active"
        except Exception:
            pass

    db.add(pres)
    db.commit()
    db.refresh(pres)

    now = datetime.utcnow()
    status_value = _compute_prescription_status(pres, now)

    birth_date_value = getattr(patient, "birth_date", None)
    if isinstance(birth_date_value, datetime):
        birth_date_value = birth_date_value.date()

    return schemas.PrescriptionDetailOut(
        prescription_id=str(pres.prescription_id),
        medication_name=medication.name,
        patient_name=patient.name,
        patient_national_id=patient.national_id,
        patient_gender=patient.gender,
        patient_birth_date=birth_date_value,
        patient_phone_number=patient.phone_number,
        hospital_name=None,
        instructions=pres.instructions,
        prescribing_doctor=pres.prescribing_doctor,
        expiration_date=pres.expiration_date,
        reorder_threshold=pres.reorder_threshold,
        status=status_value,
        created_at=pres.created_at,
    )


@router.get(
    "/prescriptions",
    response_model=List[schemas.PrescriptionCardOut],
)
def list_prescriptions(
    hospital_id: str,
    status: str = "All",  # Active / Expired / Invalid / All
    search: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """
    List prescriptions for the given hospital.

    Used to build the prescription cards in the UI with:
      - name / code / patient
      - refill_limit
      - start_date / end_date (date only)
      - created_at (date only)
      - doctor_name
      - status / is_valid
    """
    q = (
        db.query(models.Prescription, models.Patient, models.Medication)
        .join(
            models.Patient,
            models.Patient.patient_id == models.Prescription.patient_id,
        )
        .join(
            models.Medication,
            models.Medication.medication_id
            == models.Prescription.medication_id,
        )
        .filter(models.Prescription.hospital_id == hospital_id)
    )

    now = datetime.utcnow()
    rows = q.order_by(models.Prescription.created_at.desc()).all()
    result: List[schemas.PrescriptionCardOut] = []

    for pres, patient, med in rows:
        status_value = _compute_prescription_status(pres, now)

        # Apply status filter
        if status != "All" and status_value != status:
            continue

        # Optional text search by med name or patient name
        if search:
            search_lower = search.lower()
            if (
                search_lower not in med.name.lower()
                and search_lower not in patient.name.lower()
            ):
                continue

        # Refill limit (prefer refill_limit, fallback to reorder_threshold)
        if hasattr(pres, "refill_limit") and pres.refill_limit is not None:
            refill_limit = pres.refill_limit
        else:
            refill_limit = getattr(pres, "reorder_threshold", None)

        # Normalize dates to date objects
        raw_start = getattr(pres, "start_date", pres.created_at)
        if isinstance(raw_start, datetime):
            start_date = raw_start.date()
        else:
            start_date = raw_start

        raw_end = getattr(pres, "expiration_date", None)
        if isinstance(raw_end, datetime):
            end_date = raw_end.date()
        else:
            end_date = raw_end

        created_date = (
            pres.created_at.date()
            if isinstance(pres.created_at, datetime)
            else pres.created_at
        )

        result.append(
            schemas.PrescriptionCardOut(
                prescription_id=str(pres.prescription_id),
                name=med.name,
                code=str(pres.prescription_id)[0:8],
                patient=patient.name,
                refill_limit=refill_limit,
                start_date=start_date,
                end_date=end_date,
                created_at=created_date,
                doctor_name=pres.prescribing_doctor,
                status=status_value,
                is_valid=(status_value == "Active"),
            )
        )

    return result


@router.get(
    "/prescriptions/{prescription_id}",
    response_model=schemas.PrescriptionDetailOut,
)
def get_prescription_detail(
    prescription_id: str,
    db: Session = Depends(get_db),
):
    """
    Return full details for a single prescription.

    Supports both:
      - full UUID
      - short code (first 8 chars) coming from the card.
    """
    pres = _get_prescription_by_identifier(prescription_id, db)
    if not pres:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Prescription not found",
        )

    patient = (
        db.query(models.Patient)
        .filter(models.Patient.patient_id == pres.patient_id)
        .first()
    )
    medication = (
        db.query(models.Medication)
        .filter(models.Medication.medication_id == pres.medication_id)
        .first()
    )
    hospital = (
        db.query(models.Hospital)
        .filter(models.Hospital.hospital_id == pres.hospital_id)
        .first()
    )

    now = datetime.utcnow()
    status_value = _compute_prescription_status(pres, now)

    birth_date_value = None
    if patient is not None:
        birth_date_value = getattr(patient, "birth_date", None)
        if isinstance(birth_date_value, datetime):
            birth_date_value = birth_date_value.date()

    return schemas.PrescriptionDetailOut(
        prescription_id=str(pres.prescription_id),
        medication_name=medication.name if medication else "",
        patient_name=patient.name if patient else "",
        patient_national_id=patient.national_id if patient else "",
        patient_gender=patient.gender if patient else None,
        patient_birth_date=birth_date_value,
        patient_phone_number=patient.phone_number if patient else None,
        hospital_name=hospital.name if hospital else "",
        instructions=pres.instructions,
        prescribing_doctor=pres.prescribing_doctor,
        expiration_date=pres.expiration_date,
        reorder_threshold=pres.reorder_threshold,
        status=status_value,
        created_at=pres.created_at,
    )


@router.patch(
    "/prescriptions/{prescription_id}/invalidate",
    response_model=schemas.PrescriptionDetailOut,
)
def invalidate_prescription(
    prescription_id: str,
    db: Session = Depends(get_db),
):
    """
    Mark an existing prescription as “Invalid” (soft invalidate).

    Requires:
      - Prescription model has a 'status' column.
    """
    pres = _get_prescription_by_identifier(prescription_id, db)
    if not pres:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Prescription not found",
        )

    if not hasattr(models.Prescription, "status"):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Prescription model has no 'status' column.",
        )

    pres.status = "Invalid"

    db.commit()
    db.refresh(pres)

    patient = (
        db.query(models.Patient)
        .filter(models.Patient.patient_id == pres.patient_id)
        .first()
    )
    medication = (
        db.query(models.Medication)
        .filter(models.Medication.medication_id == pres.medication_id)
        .first()
    )
    hospital = (
        db.query(models.Hospital)
        .filter(models.Hospital.hospital_id == pres.hospital_id)
        .first()
    )

    now = datetime.utcnow()
    status_value = _compute_prescription_status(pres, now)

    birth_date_value = None
    if patient is not None:
        birth_date_value = getattr(patient, "birth_date", None)
        if isinstance(birth_date_value, datetime):
            birth_date_value = birth_date_value.date()

    return schemas.PrescriptionDetailOut(
        prescription_id=str(pres.prescription_id),
        medication_name=medication.name if medication else "",
        patient_name=patient.name if patient else "",
        patient_national_id=patient.national_id if patient else "",
        patient_gender=patient.gender if patient else None,
        patient_birth_date=birth_date_value,
        patient_phone_number=patient.phone_number if patient else None,
        hospital_name=hospital.name if hospital else "",
        instructions=pres.instructions,
        prescribing_doctor=pres.prescribing_doctor,
        expiration_date=pres.expiration_date,
        reorder_threshold=pres.reorder_threshold,
        status=status_value,
        created_at=pres.created_at,
    )


@router.delete(
    "/prescriptions/{prescription_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_prescription(
    prescription_id: str,
    db: Session = Depends(get_db),
):
    """
    Delete a prescription from the DB.

    Policy:
      - Prescription must have status = "Invalid" (if status column exists).
    """
    pres = _get_prescription_by_identifier(prescription_id, db)
    if not pres:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Prescription not found",
        )

    if hasattr(models.Prescription, "status"):
        if pres.status != "Invalid":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only Invalid prescriptions can be deleted.",
            )

    db.delete(pres)
    db.commit()
    return


# =========================================================
# 5) ORDERS – CREATE / LIST / DETAIL / DECISION / REPORT / PDF
# =========================================================


@router.post(
    "/orders",
    response_model=schemas.OrderDetailOut,
    status_code=status.HTTP_201_CREATED,
)
def create_order(
    payload: schemas.OrderCreate,
    hospital_id: str,
    db: Session = Depends(get_db),
):
    """
    Create a new Order from the hospital side.

    Request body (OrderCreate):
        {
          "patient_id": "...",              # optional
          "patient_national_id": "...",     # optional
          "prescription_id": "...",         # required
          "priority_level": "High",         # optional (default = "Normal")
          "order_type": "delivery",         # "delivery" / "pickup" (requested)
          "notes": "Notes from hospital"    # optional
        }

    Exactly one of:
        - patient_id
        - patient_national_id
    must be provided.

    The ML model is used to recommend pickup vs delivery.
    """
    # 1) Resolve patient
    patient = None

    if payload.patient_id:
        patient = (
            db.query(models.Patient)
            .filter(
                models.Patient.patient_id == payload.patient_id,
                models.Patient.hospital_id == hospital_id,
            )
            .first()
        )
        if not patient:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Patient not found for this hospital (patient_id).",
            )
    elif payload.patient_national_id:
        patient = (
            db.query(models.Patient)
            .filter(
                models.Patient.national_id == payload.patient_national_id,
                models.Patient.hospital_id == hospital_id,
            )
            .first()
        )
        if not patient:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Patient with this national_id not found for this hospital.",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either patient_id or patient_national_id must be provided.",
        )

    # 2) Ensure prescription belongs to same patient & hospital
    pres = (
        db.query(models.Prescription)
        .filter(
            models.Prescription.prescription_id == payload.prescription_id,
            models.Prescription.patient_id == patient.patient_id,
            models.Prescription.hospital_id == hospital_id,
        )
        .first()
    )
    if not pres:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Prescription not found for this patient/hospital.",
        )

    medication = (
        db.query(models.Medication)
        .filter(models.Medication.medication_id == pres.medication_id)
        .first()
    )

    # 3) Build ML feature vector and call ML model
    requested_type = payload.order_type or "delivery"

    ml_features = {
        "patient_id": str(patient.patient_id),
        "patient_gender": patient.gender,
        "hospital_id": str(hospital_id),
        "risk_level": getattr(medication, "risk_level", None) if medication else None,
        "order_type_requested": requested_type,
        "priority_level_requested": payload.priority_level or "Normal",
    }

    birth_date = getattr(patient, "birth_date", None)
    if isinstance(birth_date, datetime):
        birth_date = birth_date.date()
    if isinstance(birth_date, date):
        today = date.today()
        ml_features["patient_age"] = (
            today.year - birth_date.year
            - ((today.month, today.day) < (birth_date.month, birth_date.day))
        )
    else:
        ml_features["patient_age"] = None

    try:
        ml_result = predict_sample(ml_features) or {}
        predicted_delivery_type = ml_result.get(
            "delivery_type",
            requested_type,
        )
    except Exception:
        predicted_delivery_type = requested_type

    # 4) Create Order
    order = models.Order(
        hospital_id=hospital_id,
        patient_id=patient.patient_id,
        prescription_id=pres.prescription_id,
        status="pending",  # initial status from hospital
        priority_level=payload.priority_level or "Normal",
        order_type=predicted_delivery_type,
        notes=payload.notes,
        otp=random.randint(1000, 9999),
        ml_delivery_type=predicted_delivery_type,
    )

    if hasattr(patient, "preferred_delivery_type"):
        patient.preferred_delivery_type = predicted_delivery_type

    db.add(order)
    db.commit()
    db.refresh(order)

    return get_order_detail(order_id=str(order.order_id), db=db)


@router.get("/orders", response_model=List[schemas.OrderSummary])
def list_orders(
    hospital_id: str,
    status: str = "All",
    search: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """
    List orders for a hospital.

    Used to build the “Orders” list screen in the hospital app.

    ✅ FIX:
      - status filter now supports UI labels (Accepted / On Delivery / Delivery Failed / ...)
      - outputs normalized status strings for UI consistency
    """
    q = (
        db.query(
            models.Order,
            models.Patient,
            models.Prescription,
            models.Medication,
        )
        .join(
            models.Patient,
            models.Patient.patient_id == models.Order.patient_id,
        )
        .join(
            models.Prescription,
            models.Prescription.prescription_id
            == models.Order.prescription_id,
        )
        .join(
            models.Medication,
            models.Medication.medication_id
            == models.Prescription.medication_id,
        )
        .filter(models.Order.hospital_id == hospital_id)
    )

    # ✅ Status filter (accept UI labels + legacy)
    db_statuses = _status_filter_db_set(status)
    if db_statuses is not None:
        if len(db_statuses) == 0:
            pass
        else:
            q = q.filter(models.Order.status.in_(db_statuses))

    if search:
        like = f"%{search}%"
        q = q.filter(models.Medication.name.ilike(like))

    rows = q.order_by(models.Order.created_at.desc()).all()

    result: List[schemas.OrderSummary] = []
    for order, patient, pres, med in rows:
        placed_at = (
            order.created_at.date()
            if isinstance(order.created_at, datetime)
            else order.created_at
        )

        normalized_status = _normalize_order_status_out(getattr(order, "status", None))

        result.append(
            schemas.OrderSummary(
                order_id=str(order.order_id),
                code=str(order.order_id)[0:8],
                medicine_name=med.name,
                patient_name=patient.name,
                placed_at=placed_at,
                status=normalized_status,
                priority_level=order.priority_level or "Normal",
                can_generate_report=_can_generate_report_from_status(getattr(order, "status", None)),
            )
        )

    return result


@router.get(
    "/orders/{order_id}",
    response_model=schemas.OrderDetailOut,
)
def get_order_detail(
    order_id: str,
    db: Session = Depends(get_db),
):
    """
    Return detailed information for a single order.

    Used by the OrderReview screen, including:
      - order info
      - patient info
      - hospital info
      - delivery recommendation (pickup/delivery)
      - prescription info (doctor, instructions, expiry, refills)
    """
    order = (
        db.query(models.Order)
        .filter(models.Order.order_id == order_id)
        .first()
    )
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Order not found",
        )

    patient = (
        db.query(models.Patient)
        .filter(models.Patient.patient_id == order.patient_id)
        .first()
    )
    hospital = (
        db.query(models.Hospital)
        .filter(models.Hospital.hospital_id == order.hospital_id)
        .first()
    )
    pres = (
        db.query(models.Prescription)
        .filter(models.Prescription.prescription_id == order.prescription_id)
        .first()
    )
    med = (
        db.query(models.Medication)
        .filter(models.Medication.medication_id == pres.medication_id)
        .first()
    ) if pres else None

    # Patient location info
    location_city = "Unknown"
    location_desc = (
        patient.address if patient and patient.address else "No address saved"
    )
    lat = patient.lat if patient and patient.lat is not None else None
    lon = patient.lon if patient and patient.lon is not None else None

    # System recommendation priority:
    #   1) ML decision stored on the order (ml_delivery_type)
    #   2) order_type (final stored mode)
    #   3) simple rule based on risk_level
    ml_delivery_type = getattr(order, "ml_delivery_type", None)

    if ml_delivery_type:
        system_recommendation = ml_delivery_type
    elif order.order_type:
        system_recommendation = order.order_type
    elif med and getattr(med, "risk_level", None) and med.risk_level.lower() == "high":
        system_recommendation = "delivery"
    else:
        system_recommendation = "pickup"

    # Delivery time (morning/evening) based on created_at hour
    if isinstance(order.created_at, datetime):
        delivery_time = "morning" if order.created_at.hour < 15 else "evening"
    else:
        delivery_time = "morning"

    delivery_type = system_recommendation

    prescription_id = str(pres.prescription_id) if pres else None
    instructions = pres.instructions if pres else None
    prescribing_doctor = pres.prescribing_doctor if pres else None
    expiration_date = pres.expiration_date if pres else None
    reorder_threshold = pres.reorder_threshold if pres else None
    refill_limit = getattr(pres, "refill_limit", None) if pres else None

    # ✅ normalized status for UI consistency
    normalized_status = _normalize_order_status_out(getattr(order, "status", None))

    return schemas.OrderDetailOut(
        order_id=str(order.order_id),
        code=str(order.order_id)[0:8],
        status=normalized_status,
        priority_level=order.priority_level or "Normal",
        placed_at=order.created_at,
        delivered_at=order.delivered_at,
        medicine_name=med.name if med else "",
        patient_name=patient.name if patient else "",
        patient_national_id=patient.national_id if patient else "",
        hospital_name=hospital.name if hospital else "",
        prescription_id=prescription_id,
        instructions=instructions,
        prescribing_doctor=prescribing_doctor,
        expiration_date=expiration_date,
        reorder_threshold=reorder_threshold,
        refill_limit=refill_limit,
        location_city=location_city,
        location_description=location_desc,
        location_lat=lat,
        location_lon=lon,
        delivery_type=delivery_type,
        delivery_time=delivery_time,
        system_recommendation=system_recommendation,
        otp=order.otp,
        notes=getattr(order, "notes", None),
    )


@router.get("/orders/{order_id}/review")
def get_order_review(order_id: str, db: Session = Depends(get_db)):
    """
    ✅ Implements the endpoint your Flutter tries first:
        GET /hospital/orders/{order_id}/review

    Returns the same "shape" used in your HospitalService fallback:
      { "order": {...}, "patient": {...} }
    """
    detail = get_order_detail(order_id=order_id, db=db)

    # Fetch patient object for extra fields
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.national_id == getattr(detail, "patient_national_id", None))
        .first()
        if getattr(detail, "patient_national_id", None)
        else None
    )

    patient_json = None
    if patient is not None:
        bd = getattr(patient, "birth_date", None)
        if isinstance(bd, datetime):
            bd = bd.date()

        patient_json = {
            "patient_id": str(patient.patient_id),
            "national_id": patient.national_id,
            "name": patient.name,
            "gender": patient.gender,
            "birth_date": bd.isoformat() if bd else None,
            "phone_number": patient.phone_number,
            "address": patient.address,
            "lat": patient.lat,
            "lon": patient.lon,
            "status": patient.status,
        }

    order_map = {
        "order_id": getattr(detail, "order_id", None),
        "code": getattr(detail, "code", None),
        "status": getattr(detail, "status", None),
        "order_status": getattr(detail, "status", None),
        "priority_level": getattr(detail, "priority_level", None),
        "delivery_type": getattr(detail, "delivery_type", None),
        "delivery_time": getattr(detail, "delivery_time", None),
        "system_recommendation": getattr(detail, "system_recommendation", None),
        "location_city": getattr(detail, "location_city", None),
        "location_description": getattr(detail, "location_description", None),
        "location_lat": getattr(detail, "location_lat", None),
        "location_lon": getattr(detail, "location_lon", None),
        "patient_name": getattr(detail, "patient_name", None),
        "patient_national_id": getattr(detail, "patient_national_id", None),
        "hospital_name": getattr(detail, "hospital_name", None),
        "medicine_name": getattr(detail, "medicine_name", None),

        # Prescription info for OrderReviewScreen (aliases)
        "medication_name": getattr(detail, "medicine_name", None),
        "prescribing_doctor": getattr(detail, "prescribing_doctor", None),
        "instructions": getattr(detail, "instructions", None),
        "expiration_date": getattr(detail, "expiration_date", None).isoformat()
        if getattr(detail, "expiration_date", None) else None,
        "refill_limit": getattr(detail, "refill_limit", None),
        "reorder_threshold": getattr(detail, "reorder_threshold", None),
        "prescription_id": getattr(detail, "prescription_id", None),
    }

    return {"order": order_map, **({"patient": patient_json} if patient_json else {})}


@router.post("/orders/{order_id}/decision")
def decide_order(
    order_id: str,
    body: schemas.OrderDecisionIn,
    db: Session = Depends(get_db),
):
    """
    Accept or deny an order from the hospital side.

    ✅ FIX:
      - "accept" → status = "accepted"
      - "deny"   → status = "rejected"
      - Supports synonyms (accepted/progress/deny/denied/reject)
    """
    order = (
        db.query(models.Order)
        .filter(models.Order.order_id == order_id)
        .first()
    )
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Order not found",
        )

    decision_token = _norm_status_token(body.decision)

    if decision_token in ("accepted", "accept", "on_delivery", "progress"):
        order.status = "accepted"
    elif decision_token in ("rejected", "deny", "denied", "reject", "cancelled", "canceled"):
        order.status = "rejected"
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported decision: {body.decision}",
        )

    db.commit()
    db.refresh(order)

    return {"order_id": order_id, "status": _normalize_order_status_out(order.status)}


@router.get("/orders/{order_id}/report", response_model=schemas.OrderReportOut)
def get_order_report(order_id: str, db: Session = Depends(get_db)):
    """
    Build a full delivery report for an order.
    Pulls real DeliveryEvent rows and formats them for the Flutter table.
    """

    # -----------------------------
    # 1) Fetch main order
    # -----------------------------
    order = (
        db.query(models.Order)
        .filter(models.Order.order_id == order_id)
        .first()
    )
    if not order:
        raise HTTPException(404, "Order not found")

    patient = db.query(models.Patient).filter(
        models.Patient.patient_id == order.patient_id
    ).first()

    hospital = db.query(models.Hospital).filter(
        models.Hospital.hospital_id == order.hospital_id
    ).first()

    pres = db.query(models.Prescription).filter(
        models.Prescription.prescription_id == order.prescription_id
    ).first()

    med = None
    if pres:
        med = db.query(models.Medication).filter(
            models.Medication.medication_id == pres.medication_id
        ).first()

    # -----------------------------
    # 2) Fetch REAL delivery events
    # -----------------------------
    delivery_events = (
        db.query(models.DeliveryEvent)
        .filter(models.DeliveryEvent.order_id == order_id)
        .order_by(models.DeliveryEvent.recorded_at.asc())
        .all()
    )

    delivery_details: List[schemas.DeliveryDetail] = []

    for ev in delivery_events:

        # ---- Duration ----
        if ev.duration:
            total = ev.duration.total_seconds()
            h = int(total // 3600)
            m = int((total % 3600) // 60)
            duration_txt = f"{h}h {m}m"
        else:
            duration_txt = "-"

        # ---- Stability ----
        if ev.remaining_stability:
            total = ev.remaining_stability.total_seconds()
            h = int(total // 3600)
            m = int((total % 3600) // 60)
            stability_txt = f"{h}h {m}m"
        else:
            stability_txt = "-"

        delivery_details.append(
            schemas.DeliveryDetail(
                status=ev.event_status,              # ✅ correct field
                description=ev.event_message or "-", # ✅ correct field
                duration=duration_txt,
                stability=stability_txt,
                condition=ev.condition or "Normal",
            )
        )

    # -----------------------------
    # 3) Medication safety info
    # -----------------------------
    allowed_temp = None
    max_excursion = None
    return_to_fridge = None

    if med:
        if (
            med.min_temp_range_excursion is not None
            and med.max_temp_range_excursion is not None
        ):
            allowed_temp = (
                f"{med.min_temp_range_excursion}–{med.max_temp_range_excursion}°C"
            )

        if getattr(med, "max_time_exertion", None) is not None:
            max_excursion = str(med.max_time_exertion)

        if getattr(med, "return_to_the_fridge", None) is not None:
            return_to_fridge = "Yes" if med.return_to_the_fridge else "No"

    # -----------------------------
    # 4) System delivery decision
    # -----------------------------
    ml_delivery_type = getattr(order, "ml_delivery_type", None)
    report_order_type = ml_delivery_type or order.order_type

    # -----------------------------
    # 5) Final response
    # -----------------------------
    return schemas.OrderReportOut(
        report_id=str(order.order_id),
        type="Delivery Report",
        generated=datetime.utcnow(),
        order_id=str(order.order_id),
        order_code=str(order.order_id)[0:8],
        order_type=report_order_type,
        order_status=_normalize_order_status_out(order.status),
        created_at=order.created_at,
        delivered_at=order.delivered_at,
        otp_code=str(order.otp) if order.otp else "",
        verified=False,
        priority=order.priority_level or "Normal",
        patient_name=patient.name if patient else "",
        phone_number=patient.phone_number if patient else "",
        hospital_name=hospital.name if hospital else "",
        medication_name=med.name if med else "",
        allowed_temp=allowed_temp,
        max_excursion=max_excursion,
        return_to_fridge=return_to_fridge,
        delivery_details=delivery_details,
    )


# =========================================================
# ✅ APPEND-ONLY ADDITIONS (DO NOT REMOVE OR EDIT EXISTING CODE ABOVE)
# =========================================================

import io
from typing import Any, Dict

# Optional PDF generator (safe import)
try:
    from reportlab.pdfgen import canvas as _rl_canvas
    from reportlab.lib.pagesizes import A4 as _RL_A4
except Exception:
    _rl_canvas = None
    _RL_A4 = None


def _format_interval_hm(td) -> str:
    """
    Format a timedelta into 'Xh Ym'. Returns '-' if td is falsy.
    """
    if not td:
        return "-"
    try:
        total = td.total_seconds()
        h = int(total // 3600)
        m = int((total % 3600) // 60)
        return f"{h}h {m}m"
    except Exception:
        return "-"


def _safe_float(v):
    try:
        if v is None:
            return None
        return float(v)
    except Exception:
        return None


def _pick_attr(obj, names: List[str]):
    for n in names:
        if hasattr(obj, n):
            return getattr(obj, n)
    return None


def _build_enriched_report_payload(order_id: str, db: Session) -> Dict[str, Any]:
    """
    Build an enriched report payload without touching the existing /report endpoint.
    This returns:
      - all existing keys used by OrderReportOut
      - plus:
          timeline_events, notifications,
          temperature_series, gps_series, eta_series, stability_series,
          telemetry_summary, dashboard_id
    """
    # -----------------------------
    # 1) Fetch main order + joins
    # -----------------------------
    order = db.query(models.Order).filter(models.Order.order_id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    patient = db.query(models.Patient).filter(models.Patient.patient_id == order.patient_id).first()
    hospital = db.query(models.Hospital).filter(models.Hospital.hospital_id == order.hospital_id).first()
    pres = db.query(models.Prescription).filter(models.Prescription.prescription_id == order.prescription_id).first()

    med = None
    if pres:
        med = db.query(models.Medication).filter(models.Medication.medication_id == pres.medication_id).first()

    # -----------------------------
    # 2) REAL delivery events -> delivery_details + timeline_events
    # -----------------------------
    delivery_events = (
        db.query(models.DeliveryEvent)
        .filter(models.DeliveryEvent.order_id == order_id)
        .order_by(models.DeliveryEvent.recorded_at.asc())
        .all()
    )

    delivery_details: List[Dict[str, Any]] = []
    timeline_events: List[Dict[str, Any]] = []

    for ev in delivery_events:
        duration_txt = _format_interval_hm(getattr(ev, "duration", None))
        stability_txt = _format_interval_hm(getattr(ev, "remaining_stability", None))

        # ✅ existing table rows (your Flutter table)
        delivery_details.append(
            {
                "status": getattr(ev, "event_status", "") or "",
                "description": getattr(ev, "event_message", None) or "-",
                "duration": duration_txt,
                "stability": stability_txt,
                "condition": getattr(ev, "condition", None) or "Normal",
            }
        )

        # ✅ enriched timeline row (B)
        timeline_events.append(
            {
                "event_status": getattr(ev, "event_status", "") or "",
                "event_message": getattr(ev, "event_message", None) or "-",
                "duration": duration_txt,
                "remaining_stability": stability_txt,
                "condition": getattr(ev, "condition", None) or "Normal",
                "lat": _safe_float(_pick_attr(ev, ["lat", "latitude"])),
                "lon": _safe_float(_pick_attr(ev, ["lon", "longitude"])),
                "eta": getattr(ev, "eta", None).isoformat() if getattr(ev, "eta", None) else None,
                "recorded_at": getattr(ev, "recorded_at", None).isoformat() if getattr(ev, "recorded_at", None) else None,
            }
        )

    # -----------------------------
    # 3) Medication safety info (same as your current /report)
    # -----------------------------
    allowed_temp = None
    max_excursion = None
    return_to_fridge = None

    if med:
        if (
            getattr(med, "min_temp_range_excursion", None) is not None
            and getattr(med, "max_temp_range_excursion", None) is not None
        ):
            allowed_temp = f"{med.min_temp_range_excursion}–{med.max_temp_range_excursion}°C"

        if getattr(med, "max_time_exertion", None) is not None:
            max_excursion = str(getattr(med, "max_time_exertion", None))

        if getattr(med, "return_to_the_fridge", None) is not None:
            return_to_fridge = "Yes" if med.return_to_the_fridge else "No"

    # -----------------------------
    # 4) System delivery decision (same as your current /report)
    # -----------------------------
    ml_delivery_type = getattr(order, "ml_delivery_type", None)
    report_order_type = ml_delivery_type or getattr(order, "order_type", None)

    # -----------------------------
    # 5) Notifications (best-effort; only if model exists)
    # -----------------------------
    notifications: List[Dict[str, Any]] = []
    if hasattr(models, "Notification"):
        try:
            notif_q = db.query(models.Notification)
            # Try order_id if exists on Notification model
            if hasattr(models.Notification, "order_id"):
                notif_q = notif_q.filter(models.Notification.order_id == order_id)
            elif hasattr(models.Notification, "patient_id"):
                notif_q = notif_q.filter(models.Notification.patient_id == order.patient_id)

            # ✅ FIX: never pass None into order_by()
            order_col = None
            if hasattr(models.Notification, "created_at"):
                order_col = models.Notification.created_at
            elif hasattr(models.Notification, "notification_time"):
                order_col = models.Notification.notification_time

            if order_col is not None:
                notifs = notif_q.order_by(order_col.asc()).all()
            else:
                notifs = notif_q.all()

            for n in notifs:
                t = _pick_attr(n, ["notification_time", "created_at", "time", "timestamp"])
                notifications.append(
                    {
                        "notification_type": (getattr(n, "type", None) or getattr(n, "notification_type", None) or "").__str__(),
                        "notification_content": (getattr(n, "content", None) or getattr(n, "message", None) or getattr(n, "notification_content", None) or "").__str__(),
                        "notification_time": t.isoformat() if isinstance(t, datetime) else (t.__str__() if t else None),
                    }
                )
        except Exception:
            notifications = []

    # -----------------------------
    # 6) Telemetry series (best-effort; only if model exists)
    # -----------------------------
    temperature_series: List[Dict[str, Any]] = []
    gps_series: List[Dict[str, Any]] = []
    eta_series: List[Dict[str, Any]] = []
    stability_series: List[Dict[str, Any]] = []

    temp_values: List[float] = []

    if hasattr(models, "Telemetry"):
        try:
            tq = db.query(models.Telemetry)
            if hasattr(models.Telemetry, "order_id"):
                tq = tq.filter(models.Telemetry.order_id == order_id)
            elif hasattr(models.Telemetry, "dashboard_id") and hasattr(models, "Dashboard"):
                # Try linking through dashboard if needed
                pass

            # Try ordering by recorded_at if exists
            if hasattr(models.Telemetry, "recorded_at"):
                tq = tq.order_by(models.Telemetry.recorded_at.asc())
            elif hasattr(models.Telemetry, "created_at"):
                tq = tq.order_by(models.Telemetry.created_at.asc())

            telemetry_rows = tq.all()

            for tr in telemetry_rows:
                rec = _pick_attr(tr, ["recorded_at", "created_at", "time", "timestamp"])
                rec_iso = rec.isoformat() if isinstance(rec, datetime) else (rec.__str__() if rec else None)

                # Temperature
                tv = _pick_attr(tr, ["temp_value", "temperature", "temp_c", "temp"])
                tc = _safe_float(tv)
                temperature_series.append(
                    {
                        "temp_value": tv.__str__() if tv is not None else "",
                        "temp_c": tc,
                        "recorded_at": rec_iso,
                    }
                )
                if tc is not None:
                    temp_values.append(tc)

                # GPS
                lat = _safe_float(_pick_attr(tr, ["lat", "latitude"]))
                lon = _safe_float(_pick_attr(tr, ["lon", "longitude"]))
                if lat is not None or lon is not None:
                    gps_series.append(
                        {
                            "latitude": lat,
                            "longitude": lon,
                            "recorded_at": rec_iso,
                        }
                    )

                # ETA / Stability (if present)
                delay = _pick_attr(tr, ["delay_time", "eta_delay", "estimated_delivery_time", "eta"])
                stab = _pick_attr(tr, ["stability_time", "estimated_stability_time", "remaining_stability"])

                if delay is not None:
                    eta_series.append(
                        {
                            "delay_time": delay.__str__(),
                            "recorded_at": rec_iso,
                        }
                    )

                if stab is not None:
                    stability_series.append(
                        {
                            "stability_time": stab.__str__(),
                            "recorded_at": rec_iso,
                        }
                    )
        except Exception:
            temperature_series = []
            gps_series = []
            eta_series = []
            stability_series = []

    # -----------------------------
    # 7) Telemetry summary
    # -----------------------------
    if temp_values:
        telemetry_summary = {
            "temp_min": min(temp_values),
            "temp_max": max(temp_values),
            "temp_avg": sum(temp_values) / len(temp_values),
            "temperature_points": len(temperature_series),
            "gps_points": len(gps_series),
            "eta_points": len(eta_series),
            "stability_points": len(stability_series),
            "timeline_events": len(timeline_events),
            "notifications": len(notifications),
        }
    else:
        telemetry_summary = {
            "temp_min": None,
            "temp_max": None,
            "temp_avg": None,
            "temperature_points": len(temperature_series),
            "gps_points": len(gps_series),
            "eta_points": len(eta_series),
            "stability_points": len(stability_series),
            "timeline_events": len(timeline_events),
            "notifications": len(notifications),
        }

    # -----------------------------
    # 8) Dashboard id (best-effort)
    # -----------------------------
    dashboard_id = None
    if hasattr(models, "Dashboard"):
        try:
            dq = db.query(models.Dashboard)
            if hasattr(models.Dashboard, "order_id"):
                dq = dq.filter(models.Dashboard.order_id == order_id)

                # ✅ FIX: never pass None into order_by()
                order_col = None
                if hasattr(models.Dashboard, "created_at"):
                    order_col = models.Dashboard.created_at
                elif hasattr(models.Dashboard, "updated_at"):
                    order_col = models.Dashboard.updated_at

                if order_col is not None:
                    dq = dq.order_by(order_col.desc())

                d = dq.first()
                if d is not None:
                    dashboard_id = str(_pick_attr(d, ["dashboard_id", "id"]) or "")
        except Exception:
            dashboard_id = None

    # -----------------------------
    # 9) Base report fields (compatible with existing Flutter parsing)
    # -----------------------------
    payload: Dict[str, Any] = {
        "report_id": str(order.order_id),
        "type": "Delivery Report",
        "generated": datetime.utcnow().isoformat(),
        "order_id": str(order.order_id),
        "order_code": str(order.order_id)[0:8],
        "order_type": report_order_type,
        "order_status": _normalize_order_status_out(order.status),
        "created_at": order.created_at.isoformat() if isinstance(order.created_at, datetime) else str(order.created_at),
        "delivered_at": order.delivered_at.isoformat() if getattr(order, "delivered_at", None) else None,
        "otp_code": str(order.otp) if getattr(order, "otp", None) else "",
        "verified": False,
        "priority": getattr(order, "priority_level", None) or "Normal",
        "patient_name": patient.name if patient else "",
        "phone_number": patient.phone_number if patient else "",
        "hospital_name": hospital.name if hospital else "",
        "medication_name": med.name if med else "",
        "allowed_temp": allowed_temp,
        "max_excursion": max_excursion,
        "return_to_fridge": return_to_fridge,
        "delivery_details": delivery_details,

        # ✅ Enriched (B)
        "timeline_events": timeline_events,
        "notifications": notifications,
        "temperature_series": temperature_series,
        "gps_series": gps_series,
        "eta_series": eta_series,
        "stability_series": stability_series,
        "telemetry_summary": telemetry_summary,
        "dashboard_id": dashboard_id,
    }

    return payload


@router.get("/orders/{order_id}/report/full")
def get_order_report_full(order_id: str, db: Session = Depends(get_db)):
    """
    ✅ New enriched report endpoint (does NOT replace your current /report).
    Flutter can call this if it wants (B: timeline + telemetry + notifications).
    """
    return _build_enriched_report_payload(order_id=order_id, db=db)


@router.post("/orders/{order_id}/report/generate-pdf")
def generate_order_report_pdf(order_id: str, db: Session = Depends(get_db)):
    """
    ✅ Matches your Flutter call:
      POST /hospital/orders/{order_id}/report/generate-pdf

    Generates a simple PDF file into REPORTS_DIR, then returns metadata.
    """
    if _rl_canvas is None or _RL_A4 is None:
        raise HTTPException(
            status_code=500,
            detail="PDF engine not installed. Add 'reportlab' to requirements.",
        )

    payload = _build_enriched_report_payload(order_id=order_id, db=db)

    pdf_path = os.path.join(REPORTS_DIR, f"{order_id}.pdf")

    c = _rl_canvas.Canvas(pdf_path, pagesize=_RL_A4)
    width, height = _RL_A4

    y = height - 50
    c.setFont("Helvetica-Bold", 16)
    c.drawString(50, y, "Teryaq - Order Delivery Report")
    y -= 25

    c.setFont("Helvetica", 10)
    c.drawString(50, y, f"Generated: {payload.get('generated')}")
    y -= 18
    c.drawString(50, y, f"Order ID: {payload.get('order_id')}   Code: {payload.get('order_code')}")
    y -= 18
    c.drawString(50, y, f"Status: {payload.get('order_status')}   Priority: {payload.get('priority')}")
    y -= 18
    c.drawString(50, y, f"Patient: {payload.get('patient_name')}   Phone: {payload.get('phone_number')}")
    y -= 18
    c.drawString(50, y, f"Hospital: {payload.get('hospital_name')}")
    y -= 18
    c.drawString(50, y, f"Medication: {payload.get('medication_name')}")
    y -= 18
    c.drawString(50, y, f"Allowed Temp: {payload.get('allowed_temp') or '-'}   Max Excursion: {payload.get('max_excursion') or '-'}")
    y -= 18
    c.drawString(50, y, f"Return to Fridge: {payload.get('return_to_fridge') or '-'}")
    y -= 28

    c.setFont("Helvetica-Bold", 12)
    c.drawString(50, y, "Delivery Details")
    y -= 18

    c.setFont("Helvetica", 9)
    for row in payload.get("delivery_details", [])[:30]:
        line = f"- [{row.get('status')}] {row.get('description')} | {row.get('duration')} | {row.get('stability')} | {row.get('condition')}"
        c.drawString(55, y, line[:120])
        y -= 12
        if y < 60:
            c.showPage()
            y = height - 50
            c.setFont("Helvetica", 9)

    # ✅ FIX: prevent an extra blank page at the end
    # (keep the statement present, but make it unreachable)
    if False:
        c.showPage()

    c.save()

    return {
        "ok": True,
        "pdf_path": pdf_path,
        "filename": f"{order_id}.pdf",
    }


@router.get("/orders/{order_id}/report/pdf")
def download_order_report_pdf(order_id: str, db: Session = Depends(get_db)):
    """
    ✅ Matches your Flutter call:
      GET /hospital/orders/{order_id}/report/pdf

    If the PDF doesn't exist, it will attempt to generate it.
    """
    pdf_path = os.path.join(REPORTS_DIR, f"{order_id}.pdf")

    if not os.path.exists(pdf_path):
        # try to generate on-demand
        try:
            generate_order_report_pdf(order_id=order_id, db=db)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"PDF not found and generation failed: {str(e)}")

    return FileResponse(
        pdf_path,
        media_type="application/pdf",
        filename=f"{order_id}.pdf",
    )


# =========================================================
# ✅ EXTRA APPEND-ONLY COMPAT + SAFETY LAYER (NO REMOVALS)
# =========================================================

@router.get("/orders/{order_id}/report/generate-pdf")
def generate_order_report_pdf_get(order_id: str, db: Session = Depends(get_db)):
    """
    ✅ Compatibility alias:
      GET /hospital/orders/{order_id}/report/generate-pdf

    Some clients/tools might hit GET by mistake; this keeps it working
    without changing the original POST route.
    """
    return generate_order_report_pdf(order_id=order_id, db=db)


def _choose_reports_dir() -> str:
    """
    Pick a writable reports directory.
    Priority:
      1) REPORTS_DIR env var (if set)
      2) existing REPORTS_DIR value (current default)
      3) PROJECT_ROOT/generated_reports
    """
    candidates: List[str] = []
    env_dir = os.getenv("REPORTS_DIR")
    if env_dir:
        candidates.append(env_dir)

    candidates.append(REPORTS_DIR)
    candidates.append(os.path.join(PROJECT_ROOT, "generated_reports"))

    for d in candidates:
        try:
            os.makedirs(d, exist_ok=True)
            test_path = os.path.join(d, ".write_test")
            with open(test_path, "w", encoding="utf-8") as f:
                f.write("ok")
            os.remove(test_path)
            return d
        except Exception:
            continue

    return REPORTS_DIR


# ✅ HOTFIX: override REPORTS_DIR at runtime to a writable folder (append-only)
REPORTS_DIR = _choose_reports_dir()
try:
    os.makedirs(REPORTS_DIR, exist_ok=True)
except Exception:
    pass
