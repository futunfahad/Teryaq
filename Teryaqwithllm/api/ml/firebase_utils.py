import os

# ==========================
# Paths & constants
# ==========================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ARTIFACTS_DIR = os.path.join(BASE_DIR, "artifacts")

MODEL_FILE = "model.joblib"
META_FILE = "meta.joblib"

LOCAL_MODEL_PATH = os.path.join(ARTIFACTS_DIR, MODEL_FILE)
LOCAL_META_PATH = os.path.join(ARTIFACTS_DIR, META_FILE)


# ==========================
# Local-only mode (Firebase disabled)
# ==========================

def init_firebase():
    """
    Firebase disabled — local model only.
    """
    return


def model_exists_local() -> bool:
    """
    Check if both model and meta files exist locally.
    """
    return os.path.exists(LOCAL_MODEL_PATH) and os.path.exists(LOCAL_META_PATH)


def upload_model_to_firebase():
    """
    Disabled — we only save locally.
    """
    os.makedirs(ARTIFACTS_DIR, exist_ok=True)

    return {
        "model_path": LOCAL_MODEL_PATH,
        "meta_path": LOCAL_META_PATH,
        "firebase": False
    }


def download_model_from_firebase():
    """
    Disabled — the model is read only from local storage.
    """
    if not model_exists_local():
        raise RuntimeError(
            f"❌ Local model not found at {LOCAL_MODEL_PATH}. "
            "Train a model first using /ml/train."
        )

    return {
        "model_path": LOCAL_MODEL_PATH,
        "meta_path": LOCAL_META_PATH,
        "firebase": False
    }
