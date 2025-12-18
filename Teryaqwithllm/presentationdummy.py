import os
import time
import uuid
import random
from datetime import datetime, timedelta, date
import psycopg2
import json
from faker import Faker
import math
from urllib.request import urlopen
from urllib.parse import quote

# ==========================================================
# 1) PostgreSQL Connection
# ==========================================================

DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
DB_USER = os.getenv("POSTGRES_USER", "postgres")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "mysecretpassword")
DB_NAME = os.getenv("POSTGRES_DB", "med_delivery")
DB_PORT = os.getenv("POSTGRES_PORT", "5432")

print(f"🔌 Connecting to DB at {DB_HOST}:{DB_PORT} (DB={DB_NAME})")
# ==========================================================
# Shared time base for today (used by route + history)
# ==========================================================
today = datetime.now().date()
base_today = datetime.combine(today, datetime.min.time())

conn = None
for _ in range(10):
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            host=DB_HOST,
            port=DB_PORT,
        )
        print("✅ Connected to PostgreSQL!")
        break
    except Exception as e:
        print("⏳ Waiting for DB:", e)
        time.sleep(3)

if conn is None:
    raise RuntimeError("❌ Could not connect to database.")

cur = conn.cursor()

# ==========================================================
# 0) CLEAR ALL EXISTING DATA
# ==========================================================

print("🧹 Clearing existing data...")

cur.execute("""
TRUNCATE TABLE
    delivery_event,
    "Order",
    patient,
    driver,
    hospital,
    medication,
    hospital_medication,
    prescription,
    dashboard,
    gps,
    temperature,
    estimated_delivery_time,
    estimated_stability_time,
    notification,
    report,
    requests,
    staging_incoming_data,
    production_table
RESTART IDENTITY CASCADE;
""")

conn.commit()

# ==========================================================
# 2) Wait for ALL Required Tables
# ==========================================================

REQUIRED_TABLES = [
    "hospital",
    "patient",
    "driver",
    "medication",
    "hospital_medication",
    "prescription",
    "dashboard",
    "gps",
    "temperature",
    "estimated_delivery_time",
    "estimated_stability_time",
    "\"Order\"",
    "notification",
    "report",
    "requests",
    "staging_incoming_data",
    "production_table",
    "delivery_event",
]

def table_exists(table_name: str) -> bool:
    cur.execute("SELECT to_regclass(%s);", (table_name,))
    return cur.fetchone()[0] is not None

print("⏳ Waiting for all required tables to be created...")

for attempt in range(40):
    missing = [t for t in REQUIRED_TABLES if not table_exists(t)]
    if not missing:
        print("✅ All tables exist! Continuing with seeding...")
        break
    print(f"⏳ Still waiting... Missing tables: {missing}")
    time.sleep(2)
else:
    raise RuntimeError(f"❌ Timed out waiting for tables: {missing}")

# ==========================================================
# 3) Utilities & Presentation Constants
# ==========================================================

fake = Faker("en_US")
random.seed(42)

def gen_uuid() -> str:
    return str(uuid.uuid4())

def phone_sa() -> str:
    return f"+9665{random.randint(10000000, 99999999)}"

def safe_str(s: str, n: int) -> str:
    return (s or "")[:n]

# Main identities requested
MAIN_PATIENT_NID = "1111111111"
MAIN_HOSPITAL_NID = "2222222222"
MAIN_DRIVER_NID  = "3333333333"

generated_national_ids = {
    MAIN_HOSPITAL_NID,
    MAIN_PATIENT_NID,
    MAIN_DRIVER_NID,
}

def gen_national_id_10() -> str:
    while True:
        nid = f"{random.randint(10**9, (10**10) - 1)}"
        if nid not in generated_national_ids:
            generated_national_ids.add(nid)
            return nid

ARABIC_NAMES = [
    "Mohammed", "Ahmad", "Fahad", "Nasser",
    "Yara", "Haifa", "Layan", "Relam",
    "Farah", "Futun", "Sara", "Lama",
]
ARABIC_LAST = [
    "Al-Qahtani", "Al-Harbi", "Al-Mutairi",
    "Al-Shammari", "Al-Otaibi", "Al-Anazi",
    "Al-Shehri", "Al-Dosari",
]

def random_arabic_full_name() -> str:
    return f"{random.choice(ARABIC_NAMES)} {random.choice(ARABIC_LAST)}"

# -----------------------------
# Presentation Medication Catalog (removed the word "demo")
# -----------------------------
MED_CATALOG = [
    dict(
        name="Lantus SoloStar (Insulin Glargine)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=30,
        return_fridge=True,
        actions="Keep refrigerated (2–8°C). Avoid freezing. If excursion occurs, contact hospital/pharmacy."
    ),
    dict(
        name="NovoRapid FlexPen (Insulin Aspart)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=30,
        return_fridge=True,
        actions="Store in fridge (2–8°C). Do not freeze. Protect from heat and sunlight."
    ),
    dict(
        name="Humalog KwikPen (Insulin Lispro)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=30,
        return_fridge=True,
        actions="Refrigerate (2–8°C). Discard if frozen or exposed to high temperatures."
    ),
    dict(
        name="Tresiba FlexTouch (Insulin Degludec)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=45,
        return_fridge=True,
        actions="Cold-chain required. Do not freeze. Limit room-temperature exposure."
    ),
    dict(
        name="Ozempic (Semaglutide)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=45,
        return_fridge=True,
        actions="Keep refrigerated (2–8°C). Do not freeze. If warm exposure occurs, verify with pharmacist."
    ),
    dict(
        name="Trulicity (Dulaglutide)",
        risk="High",
        exc_min=2, exc_max=8,
        exert_min=45,
        return_fridge=True,
        actions="Store refrigerated. Protect from heat. Do not use if appearance changes."
    ),
    dict(
        name="Adalimumab Pen (Biologic)",
        risk="Critical",
        exc_min=2, exc_max=8,
        exert_min=20,
        return_fridge=True,
        actions="High sensitivity biologic. Strict cold-chain. If excursion happens, quarantine and contact hospital."
    ),
    dict(
        name="Vaccines Pack (Cold-chain)",
        risk="Critical",
        exc_min=2, exc_max=8,
        exert_min=15,
        return_fridge=True,
        actions="Strict cold-chain. Any excursion requires immediate review by hospital pharmacy."
    ),
    dict(
        name="Metformin XR 500mg",
        risk="Medium",
        exc_min=15, exc_max=30,
        exert_min=480,
        return_fridge=False,
        actions="Store at room temperature. Keep dry, away from heat. No refrigeration required."
    ),
    dict(
        name="Amoxicillin 500mg",
        risk="Medium",
        exc_min=15, exc_max=30,
        exert_min=480,
        return_fridge=False,
        actions="Store at room temperature. Keep away from moisture and heat."
    ),
]

MEDICATION_NAME_POOL = [
    "Novolog FlexPen", "Mixtard 30", "Levemir FlexPen", "Toujeo SoloStar",
    "Glucophage", "Januvia", "Victoza", "Fiasp", "Ryzodeg 70/30",
]

# Presentation map points
BASE_LAT = 25.902679
BASE_LON = 45.381901

POINTS = {
    "A": (BASE_LAT + 0.0045, BASE_LON + 0.0040),
    "B": (BASE_LAT + 0.0065, BASE_LON - 0.0040),
    "C": (BASE_LAT - 0.0050, BASE_LON + 0.0050),
    "D": (BASE_LAT - 0.0070, BASE_LON - 0.0035),
}

def random_address() -> str:
    return f"{random.randint(10,999)} Street, Riyadh, SA"

def random_coords(radius_km: float = 3.0) -> tuple[float, float]:
    d = radius_km / 111.0
    lat = BASE_LAT + random.uniform(-d, d)
    lon = BASE_LON + random.uniform(-d, d)
    return round(lat, 6), round(lon, 6)

# ==========================================================
# 4) Containers (reduced bulk)
# ==========================================================

NUM_HOSPITALS = 3
PATIENTS_PER_HOSPITAL = 3     # reduced
DRIVERS_PER_HOSPITAL  = 2     # reduced

hospital_ids = []
hospital_info = {}
patients_by_hospital = {}
drivers_by_hospital = {}
driver_ids = []
patient_info = {}
driver_info = {}

prescriptions = []

main_hospital_id = None
main_patient_id = None
main_driver_id = None

main_medication_ids = []
main_med_name_to_id = {}
main_prescription_ids = []

orders_meta = {}
otp_info = {}

def pick_priority() -> str:
    r = random.random()
    if r < 0.6:
        return "Normal"
    elif r < 0.9:
        return "High"
    else:
        return "Critical"

def compute_delivery_minutes(scenario: str, stability_minutes: int) -> int:
    stability_minutes = max(int(stability_minutes or 0), 1)
    if scenario == "normal":
        hi = max(stability_minutes - 15, 16)
        lo = min(30, hi)
        return random.randint(lo, hi)
    if scenario == "excursion":
        lo = min(30, stability_minutes)
        hi = max(lo, stability_minutes)
        return random.randint(lo, hi)
    if scenario == "delay":
        return random.randint(stability_minutes + 10, stability_minutes + 120)
    return random.randint(stability_minutes + 20, stability_minutes + 150)

def random_temp_value(scenario: str) -> float:
    base = random.uniform(2.0, 7.8)
    if scenario in ["excursion", "both"] and random.random() < 0.7:
        return round(random.uniform(8.6, 14.5), 2)  # biased out-of-range for presentation
    if scenario == "near_limit" and random.random() < 0.8:
        return round(random.uniform(7.9, 8.4), 2)   # close to max range (2–8)
    return round(base, 2)

RIYADH_HOSPITALS = [
    ("King Fahad Medical City", "King Fahad Road, Riyadh", 25.907388, 45.380306),
    ("King Saud Medical City", "Al Suwaidi, Riyadh", 24.633000, 46.716000),
    ("King Khalid University Hospital", "KSU, Riyadh", 24.722000, 46.627000),
]

# ==========================================================
# Helpers — Stability from Medication.max_time_exertion
# ==========================================================

def get_med_stability_minutes_from_prescription(prescription_id: str) -> int:
    if not prescription_id:
        return 0
    cur.execute(
        """
        SELECT m.max_time_exertion
        FROM prescription p
        JOIN medication m ON m.medication_id = p.medication_id
        WHERE p.prescription_id = %s
        LIMIT 1
        """,
        (prescription_id,),
    )
    row = cur.fetchone()
    if not row or row[0] is None:
        return 0
    val = row[0]
    if isinstance(val, timedelta):
        return int(val.total_seconds() // 60)
    try:
        s = str(val).strip().lower()
        if ":" in s:
            hh, mm, *_ = s.split(":")
            return int(hh) * 60 + int(mm)
        digits = "".join(ch for ch in s if ch.isdigit())
        return int(digits) if digits else 0
    except Exception:
        return 0

def insert_medication_and_link(
    *,
    hospital_id: str,
    med_name: str,
    risk: str,
    exc_min: int,
    exc_max: int,
    exert_min: int,
    return_fridge: bool,
    actions: str,
) -> str:
    medication_id = gen_uuid()
    max_time_exertion_val = timedelta(minutes=int(exert_min))

    cur.execute(
        """
        INSERT INTO Medication (
            medication_id, name, description, information_source,
            exp_date, max_time_exertion,
            min_temp_range_excursion, max_temp_range_excursion,
            return_to_the_fridge, max_time_safe_use,
            additional_actions_detail, risk_level
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            medication_id,
            med_name,
            safe_str(f"{med_name} | Storage {exc_min}–{exc_max}°C | Max excursion {exert_min} min", 250),
            "MOH",
            datetime.now() + timedelta(days=random.randint(180, 720)),
            max_time_exertion_val,
            exc_min, exc_max,
            bool(return_fridge),
            True,
            safe_str(actions, 200),
            risk,
        ),
    )

    cur.execute(
        """
        INSERT INTO Hospital_Medication (hospital_id, medication_id, availability)
        VALUES (%s,%s,%s)
        """,
        (hospital_id, medication_id, True),
    )

    return medication_id

def insert_notification(order_id: str, ntype: str, content: str, minutes_ago: int):
    cur.execute(
        """
        INSERT INTO Notification (
            notification_id, order_id, notification_type,
            notification_content, notification_time
        ) VALUES (%s,%s,%s,%s, NOW() - INTERVAL %s)
        """,
        (gen_uuid(), order_id, ntype, content, f"'{int(minutes_ago)} minutes'"),
    )

# ==========================================================
# 5) Create Hospitals, Minimal Patients/Drivers, Medications, Prescriptions
# ==========================================================

print("🏥 Seeding Hospitals, Patients, Drivers, Medications, Prescriptions ...")

# Ensure we always include KFMC as main hospital
chosen_hospitals = RIYADH_HOSPITALS[:NUM_HOSPITALS]

for name, addr, h_lat, h_lon in chosen_hospitals:
    hospital_id = gen_uuid()
    hospital_ids.append(hospital_id)
    hospital_info[hospital_id] = {"name": name, "address": addr}

    if name == "King Fahad Medical City":
        national_id = MAIN_HOSPITAL_NID
        main_hospital_id = hospital_id
        firebase_uid = "HOSP_FIXED_MAIN_UID"
    else:
        national_id = gen_national_id_10()
        firebase_uid = "HOSP_" + uuid.uuid4().hex

    cur.execute(
        """
        INSERT INTO Hospital (
            hospital_id, firebase_uid, national_id, name, address,
            email, phone_number, lat, lon, status
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            hospital_id,
            firebase_uid,
            national_id,
            name,
            addr,
            fake.email(),
            phone_sa(),
            h_lat,
            h_lon,
            "active",
        ),
    )

    # Patients (minimal)
    patients_by_hospital[hospital_id] = []
    for _ in range(PATIENTS_PER_HOSPITAL):
        patient_id = gen_uuid()
        p_firebase_uid = "PAT_" + uuid.uuid4().hex
        p_national_id = gen_national_id_10()
        plat, plon = random_coords()
        pname = random_arabic_full_name()
        birth_date = fake.date_of_birth(minimum_age=1, maximum_age=90)

        cur.execute(
            """
            INSERT INTO Patient (
                patient_id, firebase_uid, national_id, hospital_id,
                name, address, email, phone_number, gender, birth_date,
                lat, lon, preferred_delivery_type, status
            )
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                patient_id, p_firebase_uid, p_national_id, hospital_id,
                pname, random_address(), fake.email(), phone_sa(),
                random.choice(["Male", "Female"]),
                birth_date, plat, plon,
                "delivery", "active",
            ),
        )

        patients_by_hospital[hospital_id].append(patient_id)
        patient_info[patient_id] = {"name": pname, "national_id": p_national_id}

    # Drivers (minimal)
    drivers_by_hospital[hospital_id] = []
    for _ in range(DRIVERS_PER_HOSPITAL):
        driver_id = gen_uuid()
        d_firebase_uid = "DRV_" + uuid.uuid4().hex
        d_national_id = gen_national_id_10()
        dlat, dlon = random_coords()
        dname = random_arabic_full_name()

        cur.execute(
            """
            INSERT INTO Driver (
                driver_id, firebase_uid, national_id, hospital_id,
                name, email, phone_number, address,
                lat, lon, status
            )
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                driver_id, d_firebase_uid, d_national_id, hospital_id,
                dname, fake.email(), phone_sa(), random_address(),
                dlat, dlon, "active",
            ),
        )

        drivers_by_hospital[hospital_id].append(driver_id)
        driver_ids.append(driver_id)
        driver_info[driver_id] = {"name": dname, "national_id": d_national_id}

    # For non-main hospitals: light medication + prescriptions
    if hospital_id != main_hospital_id:
        used_names = set()
        for _ in range(6):
            if random.random() < 0.6:
                spec = random.choice(MED_CATALOG)
                med_name = spec["name"]
                if med_name in used_names:
                    med_name = f"{med_name} ({random.randint(2, 99)})"
                used_names.add(med_name)

                medication_id = insert_medication_and_link(
                    hospital_id=hospital_id,
                    med_name=med_name,
                    risk=spec["risk"],
                    exc_min=int(spec["exc_min"]),
                    exc_max=int(spec["exc_max"]),
                    exert_min=int(spec["exert_min"]),
                    return_fridge=bool(spec["return_fridge"]),
                    actions=spec["actions"],
                )
            else:
                med_name = random.choice(MEDICATION_NAME_POOL)
                if med_name in used_names:
                    med_name = f"{med_name} ({random.randint(2, 99)})"
                used_names.add(med_name)

                temp_sensitive = random.random() < 0.5
                exc_min, exc_max = (2, 8) if temp_sensitive else (15, 30)
                exert_min = random.randint(120, 720)
                risk = "High" if temp_sensitive else "Medium"

                medication_id = insert_medication_and_link(
                    hospital_id=hospital_id,
                    med_name=med_name,
                    risk=risk,
                    exc_min=int(exc_min),
                    exc_max=int(exc_max),
                    exert_min=int(exert_min),
                    return_fridge=bool(temp_sensitive),
                    actions=safe_str(fake.text(120), 200),
                )

            # 1 prescription per med (minimal)
            presc_id = gen_uuid()
            patient_id = random.choice(patients_by_hospital[hospital_id])
            cur.execute(
                """
                INSERT INTO Prescription (
                    prescription_id, hospital_id, medication_id, patient_id,
                    expiration_date, reorder_threshold, instructions, prescribing_doctor, status
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    presc_id,
                    hospital_id,
                    medication_id,
                    patient_id,
                    datetime.now() + timedelta(days=random.randint(90, 365)),
                    random.randint(1, 5),
                    "Use as prescribed.",
                    random_arabic_full_name(),
                    "active",
                ),
            )
            prescriptions.append({
                "prescription_id": presc_id,
                "hospital_id": hospital_id,
                "patient_id": patient_id,
            })

# ==========================================================
# 5.5) MAIN presentation hospital/patient/driver + curated meds
# ==========================================================

print("🎯 Creating MAIN presentation patient/driver ...")

# Main patient (Point A)
a_lat, a_lon = POINTS["A"]
main_patient_id = gen_uuid()

cur.execute(
    """
    INSERT INTO Patient (
        patient_id, firebase_uid, national_id, hospital_id,
        name, address, email, phone_number, gender, birth_date,
        lat, lon, preferred_delivery_type, status
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
    """,
    (
        main_patient_id,
        "PAT_FIXED_MAIN_UID",
        MAIN_PATIENT_NID,
        main_hospital_id,
        "Mohammed Al-Qahtani",
        "Point A, Riyadh",
        "main_patient@teryag.com",
        "+966500000111",
        "Male",
        datetime(1999, 1, 1),
        a_lat, a_lon,
        "delivery", "active",
    ),
)

patient_info[main_patient_id] = {"name": "Mohammed Al-Qahtani", "national_id": MAIN_PATIENT_NID}

# Main driver
main_driver_id = gen_uuid()
cur.execute(
    """
    INSERT INTO Driver (
        driver_id, firebase_uid, national_id, hospital_id,
        name, email, phone_number, address,
        lat, lon, status
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
    """,
    (
        main_driver_id,
        "DRV_FIXED_MAIN_UID",
        MAIN_DRIVER_NID,
        main_hospital_id,
        "Ahmad Al-Harbi",
        "main_driver@teryag.com",
        "+966500000333",
        "Driver starting point",
        BASE_LAT, BASE_LON,
        "active",
    ),
)
driver_info[main_driver_id] = {"name": "Ahmad Al-Harbi", "national_id": MAIN_DRIVER_NID}

# Curated meds for MAIN hospital
print("💊 Seeding MAIN hospital curated medications...")
main_catalog = MED_CATALOG[:]  # keep 10 items defined
for spec in main_catalog:
    med_id = insert_medication_and_link(
        hospital_id=main_hospital_id,
        med_name=spec["name"],
        risk=spec["risk"],
        exc_min=int(spec["exc_min"]),
        exc_max=int(spec["exc_max"]),
        exert_min=int(spec["exert_min"]),
        return_fridge=bool(spec["return_fridge"]),
        actions=spec["actions"],
    )
    main_medication_ids.append(med_id)
    main_med_name_to_id[spec["name"]] = med_id

DOCTORS = [
    "Dr. Sara Al-Otaibi",
    "Dr. Fahad Al-Mutairi",
    "Dr. Nasser Al-Harbi",
]

def build_instructions(med_name: str) -> str:
    mn = med_name.lower()
    if "insulin" in mn:
        return "Inject as directed. Store refrigerated (2–8°C)."
    if "ozempic" in mn or "trulicity" in mn:
        return "Inject once weekly as directed. Keep refrigerated."
    if "vaccine" in mn:
        return "Maintain strict cold-chain. Administer per hospital schedule."
    if "adalimumab" in mn:
        return "Keep refrigerated. Administer per specialist instruction."
    return "Use as prescribed."

# Prescriptions for MAIN patient (some with 0 days left)
print("📄 Creating MAIN patient prescriptions (including 0 days left)...")

today = datetime.now().date()
end_of_today = datetime.combine(today, datetime.max.time()).replace(microsecond=0)
main_prescription_ids = []

# create MANY prescriptions (duplicates allowed)
NUM_MAIN_PRESCRIPTIONS = 25        # total cards you want
ZERO_DAYS_LEFT_COUNT   = 8         # how many should show "0 days left"

all_main_med_items = list(main_med_name_to_id.items())
if not all_main_med_items:
    raise RuntimeError("No curated medications found for MAIN hospital; cannot create prescriptions.")

for i in range(NUM_MAIN_PRESCRIPTIONS):
    presc_id = gen_uuid()

    # pick a medication (allows repeats so you can have > 10 prescriptions)
    med_name, med_id = random.choice(all_main_med_items)

    # first K prescriptions expire today => "0 days left"
    if i < ZERO_DAYS_LEFT_COUNT:
        exp = end_of_today
    else:
        exp = datetime.now() + timedelta(days=random.randint(30, 365))

    presc_status = "active"

    cur.execute(
        """
        INSERT INTO Prescription (
            prescription_id, hospital_id, medication_id, patient_id,
            expiration_date, reorder_threshold, instructions, prescribing_doctor, status
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            presc_id,
            main_hospital_id,
            med_id,
            main_patient_id,
            exp,
            random.randint(1, 6),
            build_instructions(med_name),
            random.choice(DOCTORS),
            presc_status,
        ),
    )

    main_prescription_ids.append(presc_id)

# hard verification (same transaction)
cur.execute("SELECT COUNT(*) FROM prescription WHERE patient_id = %s", (main_patient_id,))
print("✅ MAIN prescriptions inserted for main_patient_id:", cur.fetchone()[0])



# ==========================================================
# OSRM + Geo helpers (for MAIN dashboard ETA realism)
# ==========================================================

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "http://localhost5000")  # change if needed
OSRM_PROFILE  = os.getenv("OSRM_PROFILE", "driving")

def _meters_to_latlon_delta(lat: float, meters: float) -> tuple[float, float]:
    # approx conversion
    dlat = meters / 111_111.0
    dlon = meters / (111_111.0 * max(math.cos(math.radians(lat)), 1e-6))
    return dlat, dlon

def jitter_point(lat: float, lon: float, jitter_m: float) -> tuple[float, float]:
    if jitter_m <= 0:
        return lat, lon
    angle = random.uniform(0, 2 * math.pi)
    radius = random.uniform(0, jitter_m)
    dlat, dlon = _meters_to_latlon_delta(lat, radius)
    return (lat + math.sin(angle) * dlat, lon + math.cos(angle) * dlon)

def haversine_km(lat1, lon1, lat2, lon2) -> float:
    R = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(a))

def osrm_route_minutes(lat1: float, lon1: float, lat2: float, lon2: float) -> int | None:
    """
    Returns OSRM route duration in minutes (rounded), or None on failure.
    IMPORTANT: OSRM expects lon,lat order in the URL.
    """
    try:
        coords = f"{lon1},{lat1};{lon2},{lat2}"
        url = f"{OSRM_BASE_URL}/route/v1/{OSRM_PROFILE}/{quote(coords)}?overview=false"
        with urlopen(url, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        routes = data.get("routes") or []
        if not routes:
            return None
        dur_s = routes[0].get("duration")
        if dur_s is None:
            return None
        mins = int(round(float(dur_s) / 60.0))
        return max(1, mins)
    except Exception:
        return None

def get_driver_latlon(driver_id: str) -> tuple[float | None, float | None]:
    cur.execute("SELECT lat, lon FROM driver WHERE driver_id = %s LIMIT 1", (driver_id,))
    r = cur.fetchone()
    if not r:
        return None, None
    return (float(r[0]) if r[0] is not None else None, float(r[1]) if r[1] is not None else None)

def get_patient_latlon(patient_id: str) -> tuple[float | None, float | None]:
    cur.execute("SELECT lat, lon FROM patient WHERE patient_id = %s LIMIT 1", (patient_id,))
    r = cur.fetchone()
    if not r:
        return None, None
    return (float(r[0]) if r[0] is not None else None, float(r[1]) if r[1] is not None else None)

def get_hospital_latlon(hospital_id: str) -> tuple[float | None, float | None]:
    cur.execute("SELECT lat, lon FROM hospital WHERE hospital_id = %s LIMIT 1", (hospital_id,))
    r = cur.fetchone()
    if not r:
        return None, None
    return (float(r[0]) if r[0] is not None else None, float(r[1]) if r[1] is not None else None)

def calc_main_eta_minutes(*, driver_id: str, patient_id: str | None, hospital_id: str, scenario: str) -> int:
    """
    MAIN-only ETA:
    - Gets origin (driver.lat/lon) and destination (patient.lat/lon; fallback hospital.lat/lon)
    - If DEBUG_FORCE_NEAR_COORDS=1, forces both points near DEBUG_TARGET_* with meter jitter
    - Uses OSRM duration; fallback to haversine + city-speed model
    - Applies scenario delays in a controlled way
    """
    dlat, dlon = get_driver_latlon(driver_id)
    if patient_id:
        plat, plon = get_patient_latlon(patient_id)
    else:
        plat, plon = None, None

    if plat is None or plon is None:
        plat, plon = get_hospital_latlon(hospital_id)

    # If debug forced, override both points near the target (but slightly different)
    if DEBUG_FORCE_NEAR_COORDS:
        dlat, dlon = jitter_point(DEBUG_TARGET_LAT, DEBUG_TARGET_LON, DEBUG_JITTER_METERS)
        plat, plon = jitter_point(DEBUG_TARGET_LAT, DEBUG_TARGET_LON, DEBUG_JITTER_METERS)

    # Safety fallback if still missing
    if None in (dlat, dlon, plat, plon):
        return 20  # safe default

    # OSRM first
    eta = osrm_route_minutes(dlat, dlon, plat, plon)

    # Fallback: haversine distance with city speed (35 km/h)
    if eta is None:
        km = haversine_km(dlat, dlon, plat, plon)
        eta = max(3, int(round((km / 35.0) * 60.0)))  # at least 3 min

    # Scenario adjustments (kept reasonable)
    if scenario == "delay":
        eta += random.randint(15, 60)
    elif scenario == "both":
        eta += random.randint(25, 90)
    elif scenario == "excursion":
        eta += random.randint(0, 10)
    # "normal" / "near_limit": no extra delay

    return max(1, int(eta))

# ==========================================================
# 6) CREATE ORDER FUNCTION (clean descriptions + better notifications)
# ==========================================================

def create_order(
    *, hospital_id, patient_id, driver_id, prescription_id,
    status, scenario, created_at,
    order_type="delivery", patient_delivery_time="morning",
    ml_delivery_type=None, priority=None, notes_suffix="", is_main=False,
):
    if ml_delivery_type is None:
        ml_delivery_type = order_type
    if priority is None:
        priority = pick_priority()

    stability = get_med_stability_minutes_from_prescription(prescription_id)
    if not stability or stability <= 0:
        stability = random.randint(120, 240)

    delivery = compute_delivery_minutes(scenario, stability)
    delivered_at = created_at + timedelta(minutes=delivery) if status == "delivered" else None

    dashboard_id = gen_uuid()
    order_id = gen_uuid()
    otp = random.randint(1000, 9999)

    cur.execute("INSERT INTO Dashboard (dashboard_id) VALUES (%s)", (dashboard_id,))

    description = f"Order ({status})"  # removed "Demo"
    notes = f"scenario={scenario}"
    if is_main:
        notes += " [MAIN]"
    if notes_suffix:
        notes += f" | {notes_suffix}"

    cur.execute(
        """
        INSERT INTO "Order" (
            order_id, driver_id, patient_id, hospital_id, prescription_id,
            dashboard_id, description, notes,
            priority_level, order_type, patient_delivery_time,
            ml_delivery_type, OTP, status,
            created_at, delivered_at
        ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            order_id, driver_id, patient_id, hospital_id, prescription_id,
            dashboard_id, description, notes, priority,
            order_type, patient_delivery_time, ml_delivery_type,
            otp, status, created_at, delivered_at,
        ),
    )

    orders_meta[order_id] = {
        "hospital_id": hospital_id,
        "patient_id": patient_id,
        "driver_id": driver_id,
        "scenario": scenario,
        "status": status,
        "is_main": is_main,
        "dashboard_id": dashboard_id,
    }

    otp_info[order_id] = {
        "otp": otp,
        "status": status,
        "patient_id": patient_id,
        "driver_id": driver_id,
    }

    # Temperature & GPS series
    for _ in range(random.randint(10, 16)):
        minutes_ago = random.randint(5, 180)
        temp_val = random_temp_value(scenario)
        cur.execute(
            """
            INSERT INTO Temperature (temperature_id, dashboard_id, temp_value, recorded_at)
            VALUES (%s,%s,%s, NOW() - INTERVAL %s)
            """,
            (gen_uuid(), dashboard_id, float(temp_val), f"'{int(minutes_ago)} minutes'"),
        )

    for _ in range(random.randint(10, 16)):
        lat, lon = random_coords()
        minutes_ago = random.randint(5, 180)
        cur.execute(
            """
            INSERT INTO GPS (gps_id, dashboard_id, latitude, longitude, recorded_at)
            VALUES (%s,%s,%s,%s, NOW() - INTERVAL %s)
            """,
            (gen_uuid(), dashboard_id, lat, lon, f"'{int(minutes_ago)} minutes'"),
        )

    cur.execute(
        """
        INSERT INTO estimated_delivery_time (estimated_delivery_id, dashboard_id, delay_time, recorded_at)
        VALUES (%s,%s,%s,NOW())
        """,
        (gen_uuid(), dashboard_id, timedelta(minutes=delivery)),
    )

    cur.execute(
        """
        INSERT INTO estimated_stability_time (estimated_stability_id, dashboard_id, stability_time, recorded_at)
        VALUES (%s,%s,%s,NOW())
        """,
        (gen_uuid(), dashboard_id, timedelta(minutes=stability)),
    )

    # -----------------------------
    # Notifications (presentation-ready)
    # -----------------------------
    if patient_id == main_patient_id:
        # Success (green)
        insert_notification(order_id, "success", "Order was created.", 60)
        insert_notification(order_id, "success", "Order has been placed successfully.", 55)

        # Warning (yellow)
        if status in ("on_delivery", "on_route", "accepted"):
            insert_notification(order_id, "warning", "Temperature is close to getting out of range.", 18)

        if scenario in ("excursion", "both") or status in ("delivery_failed",):
            insert_notification(order_id, "warning", "Temperature out of range.", 12)

        # Danger (red)
        if status == "rejected":
            insert_notification(order_id, "danger", "Order has been rejected.", 8)

        if status == "delivery_failed":
            insert_notification(order_id, "danger", "Delivery failed. Please contact support.", 6)

    else:
        # Keep others minimal
        insert_notification(order_id, "success", "Order was created.", 45)

    # Report
    cur.execute(
        """
        INSERT INTO Report (report_id, order_id, report_type, report_content)
        VALUES (%s,%s,%s,%s)
        """,
        (
            gen_uuid(), order_id, "auto",
            f"scenario={scenario}, delivery={delivery}min, stability={stability}min",
        ),
    )

    # Delivery events (only for some statuses)
    if status in ("delivered", "delivery_failed", "on_delivery", "on_route"):

        base_lat, base_lon = random_coords()

        cur.execute(
            """
            INSERT INTO delivery_event (
                event_id, order_id, event_status, event_message, duration,
                remaining_stability, condition, lat, lon, eta, recorded_at
            ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                gen_uuid(), order_id, "Start",
                "Driver departed", timedelta(minutes=0),
                timedelta(minutes=stability), "Normal",
                base_lat, base_lon,
                created_at + timedelta(minutes=max(delivery - 20, 5)),
                created_at,
            ),
        )

        mid_time = created_at + timedelta(minutes=max(delivery // 2, 10))
        cur.execute(
            """
            INSERT INTO delivery_event (
                event_id, order_id, event_status, event_message, duration,
                remaining_stability, condition, lat, lon, eta, recorded_at
            ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                gen_uuid(), order_id, "in Route",
                "Driver on the way",
                timedelta(minutes=max(delivery // 2, 10)),
                timedelta(minutes=max(stability - (delivery // 2), 0)),
                "Normal",
                base_lat + random.uniform(-0.01, 0.01),
                base_lon + random.uniform(-0.01, 0.01),
                created_at + timedelta(minutes=max(delivery - 5, 3)),
                mid_time,
            ),
        )

        final_time = delivered_at or (created_at + timedelta(minutes=delivery))
        if status == "delivered":
            e_status, e_msg, e_cond = "Arrived", "Driver arrived", "Normal"
        elif status == "delivery_failed":
            e_status, e_msg, e_cond = "Warning", "Delivery failed", "Risk"
        else:
            e_status, e_msg, e_cond = "on Route", "Driver on route", "Normal"

        cur.execute(
            """
            INSERT INTO delivery_event (
                event_id, order_id, event_status, event_message, duration,
                remaining_stability, condition, lat, lon, eta, recorded_at
            ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                gen_uuid(), order_id, e_status, e_msg,
                timedelta(minutes=delivery),
                timedelta(minutes=max(stability - delivery, 0)),
                e_cond,
                base_lat + random.uniform(-0.02, 0.02),
                base_lon + random.uniform(-0.02, 0.02),
                final_time, final_time,
            ),
        )

    return order_id

# ==========================================================
# 7) MAIN patient orders (requested statuses)
# ==========================================================

print("🚚 Creating MAIN patient orders with requested statuses...")

today_dt = datetime.combine(datetime.now().date(), datetime.min.time())
t0 = today_dt + timedelta(hours=10)

# Ensure we have enough prescriptions
def any_main_prescription():
    return random.choice(main_prescription_ids)

# Required statuses for MAIN patient:
required_statuses = [
    ("pending",        "normal"),
    ("accepted",       "near_limit"),
    ("on_delivery",    "near_limit"),
    ("on_route",       "normal"),
    ("delivery_failed","both"),
    ("rejected",       "normal"),
]

for i, (st, scen) in enumerate(required_statuses):
    create_order(
        hospital_id=main_hospital_id,
        patient_id=main_patient_id,
        driver_id=main_driver_id,
        prescription_id=any_main_prescription(),
        status=st,
        scenario=scen,
        created_at=t0 + timedelta(minutes=20*i),
        notes_suffix=f"Main patient status {st}",
        is_main=True,
    )

# ==========================================================
# 8) Minimal extra orders for other hospitals (very light)
# ==========================================================

print("📦 Creating a few delivered orders for other hospitals...")

for pres in prescriptions[:6]:
    hospital_id = pres["hospital_id"]
    patient_id = pres["patient_id"]
    presc_id = pres["prescription_id"]
    drivers = drivers_by_hospital.get(hospital_id, [])
    if not drivers:
        continue
    driver_id = random.choice(drivers)

    created_at = today_dt - timedelta(days=random.randint(2, 10), hours=random.randint(9, 18))
    create_order(
        hospital_id=hospital_id,
        patient_id=patient_id,
        driver_id=driver_id,
        prescription_id=presc_id,
        status="delivered",
        scenario="normal",
        created_at=created_at,
        notes_suffix="Historical delivered order",
    )

# ==========================================================
# 8) HISTORY ORDERS FOR MAIN PATIENT
# ==========================================================

print("📜 Creating extra history orders for main patient...")

history_statuses = ["pending", "delivery_failed", "rejected", "delivered"]  # ✅ add delivered

for idx, s in enumerate(history_statuses):
    created_at = base_today - timedelta(days=idx + 1, hours=9)
    presc_id = random.choice(main_prescription_ids)
    scenario = "both" if s == "delivery_failed" else "normal"

    create_order(
        hospital_id=main_hospital_id,
        patient_id=main_patient_id,
        driver_id=main_driver_id,
        prescription_id=presc_id,
        status=s,
        scenario=scenario,
        created_at=created_at,
        notes_suffix=f"History state {s}",
        is_main=True,
    )

# ==========================================================
# 9) Requests + staging/production (kept)
# ==========================================================

print("📝 Generating a few Requests...")

REQ_STATUSES = ["pending", "approved", "rejected", "resolved"]
for order_id, meta in list(orders_meta.items())[:6]:
    if random.random() < 0.5:
        req_status = random.choice(REQ_STATUSES)
        content = f"Request '{req_status}' for order {order_id}"
        cur.execute(
            """
            INSERT INTO Requests (request_id, hospital_id, order_id, status, request_content)
            VALUES (%s,%s,%s,%s,%s)
            """,
            (gen_uuid(), meta["hospital_id"], order_id, req_status, content),
        )

cur.execute(
    """
    INSERT INTO staging_incoming_data (data, status)
    VALUES (%s,%s)
    """,
    (json.dumps({"sample": "staging_payload", "ts": datetime.now().isoformat()}), "pending"),
)

cur.execute(
    """
    INSERT INTO production_table (data)
    VALUES (%s)
    """,
    (json.dumps({"sample": "production_record", "ts": datetime.now().isoformat()}),),
)

# ==========================================================
# 10) COMMIT + PRINT OTP LIST
# ==========================================================

conn.commit()

print("\n=====================================")
print("🔐 OTP LIST FOR ALL ORDERS")
print("=====================================\n")

for order_id, info in otp_info.items():
    pid = info["patient_id"]
    did = info["driver_id"]
    otp = info["otp"]
    status = info["status"]

    pnat = patient_info.get(pid, {}).get("national_id", "N/A")
    pname = patient_info.get(pid, {}).get("name", "Unknown")

    dnat = driver_info.get(did, {}).get("national_id", "N/A")
    dname = driver_info.get(did, {}).get("name", "Unknown")

    print(
        f"Order: {order_id} | OTP: {otp} | Status: {status} | "
        f"Patient: {pname} ({pnat}) | Driver: {dname} ({dnat})"
    )

cur.close()
conn.close()

print("\n🎉 ALL PRESENTATION DATA INSERTED SUCCESSFULLY!")
print("\n🎯 Main logins (as requested):")
print(f"   • Hospital: {MAIN_HOSPITAL_NID}")
print(f"   • Patient : {MAIN_PATIENT_NID}")
print(f"   • Driver  : {MAIN_DRIVER_NID}")
