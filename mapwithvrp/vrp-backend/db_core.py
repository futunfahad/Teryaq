# db_core.py
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

def get_engine():
    user = os.getenv("DB_USER", "postgres")
    pwd  = os.getenv("DB_PASSWORD", "mysecretpassword")
    host = os.getenv("DB_HOST", "postgres")
    port = os.getenv("DB_PORT", "5432")
    db   = os.getenv("DB_NAME", "med_delivery")
    
    # For running local tests (optional)
    if os.getenv("RUN_LOCAL", "false").lower() == "true":
        host = "host.docker.internal"

    uri = f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}"
    return create_engine(uri, pool_pre_ping=True)

engine = get_engine()
