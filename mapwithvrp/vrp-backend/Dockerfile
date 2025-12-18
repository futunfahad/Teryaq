# ==============================
# VRP Backend Dockerfile
# ==============================

FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y \
    g++ \
    build-essential \
    cmake \
    meson \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "9000", "--reload"]
