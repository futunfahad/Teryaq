import os
import json
import re
import pandas as pd
import psycopg2
from sqlalchemy import create_engine, text
from hijri_converter import convert
from transformers import pipeline
from rapidfuzz import process, fuzz
from dotenv import load_dotenv

# =====================================================
# 1. Database connection
# =====================================================
def get_engine():
    load_dotenv()
    user = os.getenv("DB_USER", "postgres")
    pwd = os.getenv("DB_PASSWORD", "mysecretpassword")
    host = os.getenv("DB_HOST", "localhost")
    port = os.getenv("DB_PORT", "5432")
    db   = os.getenv("DB_NAME", "med_delivery")
    return create_engine(f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}")


# =====================================================
# 2. Column Mapping (Dictionary + Fallback LLM)
# =====================================================
COLUMN_MAPPING = {
    "drug": "medication", "med": "medication", "medication": "medication", "دواء": "medication",
    "full_name": "patient_name", "patientname": "patient_name", "اسم_المريض": "patient_name",
    "dob": "date_of_birth", "birthday": "date_of_birth", "birth_date": "date_of_birth",
    "dateofbirth": "date_of_birth", "تاريخ_الميلاد": "date_of_birth",
    "hospitalid": "hospital_id", "hospital_id": "hospital_id", "مستشفى": "hospital_id",
    "external_id": "patient_external_id", "patientid": "patient_external_id"
}

classifier = pipeline(
    "zero-shot-classification",
    model="facebook/bart-large-mnli"
)

def map_columns(df: pd.DataFrame) -> pd.DataFrame:
    mapped = {}
    used = set()
    for col in df.columns:
        key = col.strip().lower()
        if key in COLUMN_MAPPING:
            new_col = COLUMN_MAPPING[key]
        else:
            result = classifier(
                col,
                candidate_labels=["patient_name", "date_of_birth", "medication", "hospital_id", "patient_external_id"]
            )
            new_col = result["labels"][0]

        # لو الاسم مكرر نضيف suffix
        if new_col in used:
            i = 2
            while f"{new_col}_{i}" in used:
                i += 1
            new_col = f"{new_col}_{i}"

        mapped[col] = new_col
        used.add(new_col)

    print("[INFO] Column mapping:", mapped)
    return df.rename(columns=mapped)


# =====================================================
# 3. Date Normalization (Hijri + Gregorian)
# =====================================================
AR_HIJRI_MONTHS = {
    "محرم": 1, "صفر": 2, "ربيع الأول": 3, "ربيع الاول": 3, "ربيع الآخر": 4,
    "ربيع الاخر": 4, "جمادى الأولى": 5, "جمادى الاولى": 5, "جمادى الآخرة": 6,
    "جمادى الاخرة": 6, "رجب": 7, "شعبان": 8, "رمضان": 9, "شوال": 10,
    "ذو القعدة": 11, "ذو الحجة": 12, "ذى القعدة": 11, "ذى الحجة": 12
}

def normalize_date(date_str: str):
    if not date_str or str(date_str).strip() == "":
        return None
    s = str(date_str).strip()

    try:  # Gregorian direct
        dt = pd.to_datetime(s, errors="coerce")
        if pd.notna(dt):
            return dt.date()
    except Exception:
        pass

    # Hijri in Arabic words (e.g. "10 رجب 1447")
    m = re.search(r"(\d{1,2})\s+([^\s]+)\s+(\d{3,4})", s)
    if m:
        d = int(m.group(1))
        month_name = m.group(2).replace("ـ", "").strip()
        y = int(m.group(3))
        month = AR_HIJRI_MONTHS.get(month_name, None)
        if month:
            g = convert.Hijri(y, month, d).to_gregorian()
            return pd.to_datetime(f"{g.year}-{g.month}-{g.day}").date()

    # Hijri digits (1447-07-15)
    digits = re.findall(r"\d+", s)
    if len(digits) == 3 and len(digits[0]) <= 4 and int(digits[0]) < 1600:
        try:
            hy, hm, hd = map(int, digits)
            g = convert.Hijri(hy, hm, hd).to_gregorian()
            return pd.to_datetime(f"{g.year}-{g.month}-{g.day}").date()
        except Exception:
            pass

    return None


# =====================================================
# 4. Medication Normalization
# =====================================================
CANONICAL_MEDS = ["Paracetamol", "Ibuprofen", "Aspirin", "Amoxicillin"]

ARABIC_TO_ENGLISH = {
    "باراسيتامول": "Paracetamol",
    "ايبوبروفين": "Ibuprofen",
    "اسبرين": "Aspirin",
    "اموكسيسيلين": "Amoxicillin",
}

def normalize_medication(raw: str):
    if not raw:
        return raw
    raw = raw.strip()

    if raw in ARABIC_TO_ENGLISH:
        return ARABIC_TO_ENGLISH[raw]

    match, score, _ = process.extractOne(raw, CANONICAL_MEDS, scorer=fuzz.WRatio)
    return match if score >= 80 else raw


# =====================================================
# 5. File Loader (CSV, Excel, JSON)
# =====================================================
def load_file(path: str) -> pd.DataFrame:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".csv":
        return pd.read_csv(path)
    elif ext in (".xlsx", ".xls"):
        return pd.read_excel(path)
    elif ext == ".json":
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return pd.DataFrame(data if isinstance(data, list) else [data])
    else:
        raise ValueError(f"Unsupported file format: {ext}")


# =====================================================
# 6. Full Pipeline: Normalize and Insert into Staging
# =====================================================
def normalize_and_load(file_path: str, source_hospital: str):
    df = load_file(file_path)
    print("[RAW DATA]")
    print(df.head())

    df = map_columns(df)

    # احذف أي duplicate columns نهائياً
    df = df.loc[:, ~df.columns.duplicated()]

    if "date_of_birth" in df.columns:
        df["date_of_birth"] = df["date_of_birth"].apply(normalize_date)
    if "medication" in df.columns:
        df["medication"] = df["medication"].apply(normalize_medication)

    print("\n[NORMALIZED DATA]")
    print(df.head())

    engine = get_engine()
    with engine.begin() as conn:
        for _, row in df.iterrows():
            conn.execute(text("""
                INSERT INTO staging_incoming_data (data, status, created_at)
                VALUES (:data, 'pending', NOW())
            """), {"data": row.to_json(force_ascii=False)})


# =====================================================
# Example Run
# =====================================================
if __name__ == "__main__":
    file_path = "data/patients.csv"
    normalize_and_load(file_path, "HospitalA")
