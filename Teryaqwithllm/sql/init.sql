-- =============================================================================
-- 🧱 RESET + EXTENSION
-- =============================================================================
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
SET search_path TO public;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- 🏥 HOSPITAL TABLE
-- =============================================================================
CREATE TABLE Hospital (
    hospital_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firebase_uid    VARCHAR(255) UNIQUE,
    national_id     VARCHAR(20) UNIQUE,
    name            VARCHAR(100) NOT NULL,
    address         VARCHAR(200),
    email           VARCHAR(80),
    phone_number    VARCHAR(20),
    lat             DECIMAL(10,6),
    lon             DECIMAL(10,6),
    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT NOW()   -- created timestamp (display format handled in app, English)
);

-- =============================================================================
-- 👤 PATIENT TABLE
-- =============================================================================
CREATE TABLE Patient (
    patient_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firebase_uid    VARCHAR(255) UNIQUE,
    national_id     VARCHAR(20) UNIQUE NOT NULL,

    hospital_id     UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,

    name            VARCHAR(100),
    address         VARCHAR(200),
    email           VARCHAR(80),
    phone_number    VARCHAR(20),
    gender          VARCHAR(10),              -- gender used in reports (UI can display in English)
    birth_date      DATE,                     -- patient date of birth for reports & profile

    lat             DECIMAL(10,6),
    lon             DECIMAL(10,6),

    -- ✅ اختياري: يقدر يخزن تفضيل المريض (delivery / pickup)
    preferred_delivery_type VARCHAR(20),

    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT NOW()   -- patient creation time (shown in English format in app)
);

-- =============================================================================
-- 🚚 DRIVER TABLE (LOGIN + MAP READY)
-- =============================================================================
CREATE TABLE Driver (
    driver_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    firebase_uid    VARCHAR(255) UNIQUE NOT NULL,
    national_id     VARCHAR(20) UNIQUE NOT NULL,

    hospital_id     UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,

    name            VARCHAR(100),
    email           VARCHAR(80),
    phone_number    VARCHAR(20),
    address         VARCHAR(200),

    lat             DECIMAL(10,6),
    lon             DECIMAL(10,6),

    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 💊 MEDICATION TABLE
-- =============================================================================
CREATE TABLE Medication (
    medication_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name               VARCHAR(150),
    description        TEXT,
    information_source  VARCHAR(150),

    exp_date           TIMESTAMP,             -- expiration date of the medication
    max_time_exertion  INTERVAL,              -- maximum allowed excursion time
    min_temp_range_excursion INT,             -- min allowed temperature (for allowedTemp)
    max_temp_range_excursion INT,             -- max allowed temperature (for allowedTemp)
    return_to_the_fridge BOOLEAN,             -- whether it can be returned to the fridge (returnToFridge)
    max_time_safe_use  BOOLEAN,
    additional_actions_detail TEXT,

    risk_level         VARCHAR(20),
    created_at         TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 🏥 HOSPITAL MEDICATION LINK TABLE
-- =============================================================================
CREATE TABLE Hospital_Medication (
    hospital_id   UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,
    medication_id UUID REFERENCES Medication(medication_id) ON DELETE CASCADE,
    availability  BOOLEAN,
    PRIMARY KEY (hospital_id, medication_id)
);

-- =============================================================================
-- 📜 PRESCRIPTION
-- =============================================================================
CREATE TABLE Prescription (
    prescription_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    hospital_id       UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,
    medication_id     UUID REFERENCES Medication(medication_id) ON DELETE CASCADE,
    patient_id        UUID REFERENCES Patient(patient_id) ON DELETE CASCADE,

    expiration_date   TIMESTAMP,        -- maps to "valid until" field in the app/report
    reorder_threshold INT,              -- maps to "refill limit" in the app/report
    instructions      TEXT,             -- notes / instructions shown to patient (report "notes")
    prescribing_doctor VARCHAR(80),     -- doctor name shown in report and prescription detail

    -- ✅ NEW: status for Active / Expired / Invalid
    status            VARCHAR(20) DEFAULT 'active',

    created_at        TIMESTAMP DEFAULT NOW()   -- prescription creation date
);

-- =============================================================================
-- 📊 DASHBOARD
-- =============================================================================
CREATE TABLE Dashboard (
    dashboard_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at   TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 📡 TELEMETRY TABLES
-- =============================================================================
CREATE TABLE GPS (
    gps_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dashboard_id UUID REFERENCES Dashboard(dashboard_id) ON DELETE CASCADE,
    latitude     DECIMAL(10,6),
    longitude    DECIMAL(10,6),
    recorded_at  TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_gps_dash ON GPS(dashboard_id);

CREATE TABLE Temperature (
    temperature_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dashboard_id   UUID REFERENCES Dashboard(dashboard_id) ON DELETE CASCADE,
    temp_value     VARCHAR(30),
    recorded_at    TIMESTAMP DEFAULT NOW()
);

CREATE TABLE estimated_delivery_time (
    estimated_delivery_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dashboard_id          UUID REFERENCES Dashboard(dashboard_id) ON DELETE CASCADE,
    delay_time            INTERVAL,
    recorded_at           TIMESTAMP DEFAULT NOW()
);

CREATE TABLE estimated_stability_time (
    estimated_stability_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dashboard_id           UUID REFERENCES Dashboard(dashboard_id) ON DELETE CASCADE,
    stability_time         INTERVAL,
    recorded_at            TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 📦 ORDER
-- =============================================================================
CREATE TABLE "Order" (
    order_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    driver_id       UUID REFERENCES Driver(driver_id) ON DELETE CASCADE,
    patient_id      UUID REFERENCES Patient(patient_id) ON DELETE CASCADE,
    hospital_id     UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,
    prescription_id UUID REFERENCES Prescription(prescription_id) ON DELETE CASCADE,
    dashboard_id    UUID UNIQUE REFERENCES Dashboard(dashboard_id) ON DELETE CASCADE,

    description     TEXT,               -- general order description
    notes           TEXT,               -- hospital/doctor notes

    priority_level  VARCHAR(20),
    order_type      VARCHAR(20),
    patient_delivery_time VARCHAR(20),
    -- ML recommendation (delivery / pickup)
    ml_delivery_type VARCHAR(20),

    OTP             INT,
    status          VARCHAR(30),

    created_at      TIMESTAMP DEFAULT NOW(),
    delivered_at    TIMESTAMP
);

-- =============================================================================
-- 🔔 NOTIFICATION
-- =============================================================================
CREATE TABLE Notification (
    notification_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id             UUID REFERENCES "Order"(order_id) ON DELETE CASCADE,
    notification_type    VARCHAR(30),
    notification_content TEXT,
    notification_time    TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 📝 REPORT
-- =============================================================================
CREATE TABLE Report (
    report_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID REFERENCES "Order"(order_id) ON DELETE CASCADE,
    report_type     VARCHAR(20),        -- e.g. "delivery", "stability"
    report_content  TEXT,               -- can store JSON / details
    created_at      TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 📥 REQUESTS
-- =============================================================================
CREATE TABLE Requests (
    request_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hospital_id     UUID REFERENCES Hospital(hospital_id) ON DELETE CASCADE,
    order_id        UUID REFERENCES "Order"(order_id) ON DELETE CASCADE,
    status          VARCHAR(30),
    request_content TEXT,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 🔄 STAGING + PRODUCTION
-- =============================================================================
CREATE TABLE staging_incoming_data (
    id         SERIAL PRIMARY KEY,
    data       JSONB NOT NULL,
    status     VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE production_table (
    id         SERIAL PRIMARY KEY,
    data       JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 🚚 DELIVERY EVENT (FOR PRESENTATION / STABILITY DEMO)
-- =============================================================================
CREATE TABLE delivery_event (
    event_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID REFERENCES "Order"(order_id) ON DELETE CASCADE,

    event_status        VARCHAR(30),         -- Start | on Route | Warning | Arrived
    event_message       TEXT,                -- e.g. from notification-style messages
    duration            INTERVAL,            -- e.g. "15 minutes"
    remaining_stability INTERVAL,            -- e.g. "1 hour 45 minutes"
    condition           VARCHAR(20),         -- Normal | Risk

    lat                 DECIMAL(10,6),
    lon                 DECIMAL(10,6),
    eta                 TIMESTAMP,           -- ETA at this moment

    recorded_at         TIMESTAMP DEFAULT NOW()
);
