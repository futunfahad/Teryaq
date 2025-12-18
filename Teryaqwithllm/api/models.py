# ============================================================
# models.py — AUTOMAP FOR REAL POSTGRESQL STRUCTURE
# ============================================================
import os
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.automap import automap_base
from sqlalchemy import create_engine
from sqlalchemy import Column, String, Text, DateTime, Numeric, Interval, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship, backref
from datetime import datetime
import uuid

# ============================================================
# DATABASE CONFIG
# ============================================================

DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "mysecretpassword")
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "med_delivery")

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# ============================================================
# ENGINE & SESSION
# ============================================================

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# ============================================================
# AUTOMAP BASE (REFLECTION)
# ============================================================

Base = automap_base()

# Reflect all tables from the real PostgreSQL database
Base.prepare(autoload_with=engine)

# ============================================================
# REFLECTED TABLES (MATCHING REAL DATABASE)
# ============================================================

# Core entities
Hospital            = Base.classes.hospital
Patient             = Base.classes.patient
Driver              = Base.classes.driver
Medication          = Base.classes.medication
Prescription        = Base.classes.prescription

# Link table
Hospital_Medication = Base.classes.hospital_medication

# Dashboard + Telemetry
Dashboard                = Base.classes.dashboard
Gps                      = Base.classes.gps
Estimated_Delivery_Time  = Base.classes.estimated_delivery_time
Estimated_Stability_Time = Base.classes.estimated_stability_time

# Orders + Logs
Order          = Base.classes.Order              # MUST BE CASE-SENSITIVE ("Order")
Notification   = Base.classes.notification
Report         = Base.classes.report

# Production (optional)
Production_Table = Base.classes.production_table

# Staging table (optional)
try:
    Staging_Incoming_Data = Base.classes.staging_incoming_data
except AttributeError:
    Staging_Incoming_Data = None  # table does not exist




# =========================================================
# 🚚 DeliveryEvent Model (for hospital report table rows)
# =========================================================

DeliveryEvent = Base.classes.delivery_event




# ============================================================
# DB DEPENDENCY FOR FASTAPI
# ============================================================

def get_db():
    """
    Provides a SQLAlchemy DB session for FastAPI dependency injection.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
