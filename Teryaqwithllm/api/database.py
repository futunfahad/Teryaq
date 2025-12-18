import os
import psycopg2
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.automap import automap_base

# ======================================================
# 🔗 DATABASE CONFIG
# ======================================================
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "mysecretpassword")
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "med_delivery")

DATABASE_URL = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# ======================================================
# 🔥 SQLAlchemy Engine + Session
# ======================================================
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)

# ======================================================
# 📌 AUTOMAP (Reflect DB Models Automatically)
# ======================================================
Base = automap_base()
Base.prepare(autoload_with=engine)

# ✅ Print reflected keys once (helps you see the real names)
print("AUTOMAP CLASSES:", sorted(Base.classes.keys()))

# ======================================================
# ✅ Reflected models
# ======================================================
Hospital = Base.classes.hospital
Patient = Base.classes.patient
Driver = Base.classes.driver
Medication = Base.classes.medication
Prescription = Base.classes.prescription
Hospital_Medication = Base.classes.hospital_medication

# ---- Resolve "Order" safely (quoted table often maps to Order / order_) ----
Order = (
    getattr(Base.classes, "Order", None)
    or getattr(Base.classes, "order", None)
    or getattr(Base.classes, "order_", None)
    or getattr(Base.classes, "orders", None)
)

if Order is None:
    raise RuntimeError(
        f"Order table class not found in automap. Available: {sorted(Base.classes.keys())}"
    )

# Optional tables (only if they exist)
Notification = getattr(Base.classes, "notification", None)
Report = getattr(Base.classes, "report", None)
DeliveryEvent = getattr(Base.classes, "delivery_event", None)

# ======================================================
# FastAPI Dependency
# ======================================================
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ======================================================
# 🧩 Raw psycopg2 Connection (for manual SQL queries)
# ======================================================
def get_db_connection():
    conn = psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        port=DB_PORT,
    )
    return conn
