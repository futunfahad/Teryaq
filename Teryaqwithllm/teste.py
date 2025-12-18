import psycopg2
import uuid
from datetime import datetime, timedelta

# ==========================================
# FIXED HOSPITAL ID (from your earlier message)
# ==========================================
HOSPITAL_ID = "506d9934-5b10-4218-a17b-85b676ff82a1"

# ==========================================
# Connect to PostgreSQL
# ==========================================
conn = psycopg2.connect(
    dbname="med_delivery",
    user="postgres",
    password="mysecretpassword",
    host="localhost",   # change if running in Docker: host="postgres_container"
    port="5432"
)
cur = conn.cursor()

# ==========================================
# 1) Create Patient
# ==========================================
patient_id = str(uuid.uuid4())
cur.execute("""
    INSERT INTO patient (
        patient_id, hospital_id, national_id, name,
        phone_number, gender, lat, lon, status
    )
    VALUES (%s, %s, %s, %s, '0550000000', 'female', 24.71, 46.68, 'active')
""", (
    patient_id,
    HOSPITAL_ID,
    "P-" + patient_id[:8],  # auto national id
    "Test Patient " + patient_id[:4]
))

# ==========================================
# 2) Create Medication
# ==========================================
medication_id = str(uuid.uuid4())
cur.execute("""
    INSERT INTO medication (
        medication_id, name, description, information_source,
        min_temp_range_excursion, max_temp_range_excursion,
        return_to_the_fridge, risk_level
    )
    VALUES (%s, 'Insulin', 'Demo medication', 'system',
            2, 8, TRUE, 'High')
""", (medication_id,))

# ==========================================
# 3) Create Prescription
# ==========================================
prescription_id = str(uuid.uuid4())
cur.execute("""
    INSERT INTO prescription (
        prescription_id, hospital_id, medication_id, patient_id,
        expiration_date, reorder_threshold, instructions,
        prescribing_doctor, status
    )
    VALUES (%s, %s, %s, %s,
            NOW() + interval '7 days', 2, 'Take as instructed',
            'Dr. AI', 'Active')
""", (
    prescription_id,
    HOSPITAL_ID,
    medication_id,
    patient_id
))

# ==========================================
# 4) Create Order
# ==========================================
order_id = str(uuid.uuid4())
cur.execute("""
    INSERT INTO "Order" (
        order_id, driver_id, patient_id, hospital_id, prescription_id,
        dashboard_id, description, notes,
        priority_level, order_type, ml_delivery_type,
        otp, status, created_at
    )
    VALUES (
        %s, NULL, %s, %s, %s,
        NULL, 'Auto-created order', 'N/A',
        'High', 'delivery', 'delivery',
        1234, 'completed', NOW()
    )
""", (
    order_id,
    patient_id,
    HOSPITAL_ID,
    prescription_id
))

print("Created order:", order_id)

# ==========================================
# 5) Insert Delivery Events
# ==========================================

events = [
    ("Packed", "Order prepared and packed", "Normal", 0, 30),
    ("Driver Assigned", "Driver assigned to pickup", "Normal", 15, 29),
    ("on Route", "Driver on route to destination", "Normal", 22, 28),
    ("Warning", "Temperature rising above threshold", "Risk", 27, 27),
    ("Arrival", "Driver arrived at patient area", "Normal", 28, 26),
    ("Delivered", "Delivered successfully", "Normal", 30, 25),
]

base_lat = 24.7200
base_lon = 46.6800

for i, (status, message, condition, mins, stability) in enumerate(events):
    cur.execute("""
        INSERT INTO delivery_event (
            event_id, order_id, event_status, event_message,
            condition, lat, lon, eta, recorded_at,
            duration, remaining_stability
        )
        VALUES (
            uuid_generate_v4(), %s, %s, %s, %s,
            %s, %s,
            NOW() + interval '%s minutes',
            NOW(),
            interval '%s minutes',
            interval '%s minutes'
        )
    """, (
        order_id,
        status,
        message,
        condition,
        base_lat + (i * 0.002),
        base_lon + (i * 0.002),
        mins,
        mins,
        stability,
    ))

print("Inserted all delivery events.")

conn.commit()
cur.close()
conn.close()

print("\n=================================")
print(" ALL INSERTS COMPLETED SUCCESSFULLY ")
print(" Order ID:", order_id)
print(" Patient ID:", patient_id)
print(" Prescription ID:", prescription_id)
print("=================================")
