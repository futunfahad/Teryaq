# Teryaq (تِرياق) — Smart Cold-Chain Medication Delivery & Monitoring System

Teryaq is a multi-role healthcare logistics system for **temperature-sensitive medication delivery**. It combines Flutter mobile apps, a FastAPI backend, a PostgreSQL database, a self-hosted OpenStreetMap stack (TileServer-GL + OSRM), real-time IoT telemetry (temperature + GPS), and safety workflows that protect medication integrity throughout delivery.

---

## Demo
- Demo link: https://www.canva.com/design/DAG74NkUXW8/Ht80OQyIMl1U-HDLrD5nAw/view?utm_content=DAG74NkUXW8&utm_campaign=designshare&utm_medium=link2&utm_source=uniquelinks&utlId=h0cafe79df0#43

---

## System Architecture

![Teryaq Architecture](architecture.png)

---

## What the system solves
- Maintains **cold-chain safety** by tracking temperature excursions and remaining stability time during delivery.
- Supports the full lifecycle: **prescribing → ordering → approval → dispatch → tracking → OTP handover → reporting**.
- Provides **live maps and routing** using a self-hosted OSM stack for reliability and performance.
- Includes a **chatbot assistant** for UI navigation and medication storage/safety guidance using deterministic logic with controlled LLM rephrasing.

---

## How each user uses Teryaq

### Patient
- Login using National ID + password (secured via Firebase Authentication).
- View home overview (latest order status, next refill, notifications, chatbot access).
- View prescriptions and place orders (Delivery or Pickup; recommendation can be provided based on location).
- Track orders with timeline and progress.
- Dashboard shows temperature, ETA, and remaining stability time with privacy rules (map shown only when appropriate).
- View reports and export as PDF when available.

### Hospital
- Login using National ID + password.
- Manage patients (search/view/add/remove).
- Manage prescriptions (create/view/invalidate/remove invalid).
- Review and decide on orders (accept/deny) and access reports.

### Driver
- Login using National ID + password (token-secured API).
- Start daily deliveries and view assigned orders.
- Use delivery dashboard (map + temperature + ETA + stability).
- Mark delivered using OTP verification.
- Report issues; delivery can be marked failed if medication becomes unsafe, with return-to-hospital workflow supported.

---

## Technical architecture

### Mobile applications
- Flutter + Dart
- Bilingual support (English & Arabic) with in-app language toggle
- Consistent navigation patterns across Patient/Hospital/Driver

### Backend services
- FastAPI provides:
  - Firebase token verification
  - Order & prescription management
  - Notifications and reporting
  - Integrations for routing, telemetry, and optimization modules

### Data layer
- PostgreSQL stores:
  - Users, medications, prescriptions, orders
  - Telemetry logs (GPS + temperature)
  - Dashboard time-series tables (`estimated_delivery_time`, `estimated_stability_time`)
  - Notifications, delivery events, reports

### Containerization & development operations
- Docker + Docker Compose for consistent multi-service execution
- Ngrok used during development for real-device testing against local backend

---

## Mapping & routing (self-hosted OSM stack)
- OpenStreetMap data is the base dataset
- TileServer-GL serves locally hosted tiles for fast and reliable map rendering
- OSRM computes routes and durations for polylines and ETA

---

## Remaining stability duration monitoring
- Tracks medication excursion limits (time and temperature range).
- Starts excursion timing when temperature goes outside the allowed range.
- Flags unsafe if:
  - Maximum excursion time is consumed, or
  - A severe temperature violation persists (~1 minute over upper bound).
- Logs events and triggers alerts for rapid response and reporting.

---

## Chatbot assistant
1. Input normalization + language detection
2. Deterministic intent routing (UI navigation vs medication question)
3. Fuzzy matching to find best UI answer or medication match
4. Rule-based storage vs safety classification
5. Controlled LLM rephrasing (rephrase only; no new facts)

---

## How ETA is produced in the system
ETA can be obtained through **two paths**, depending on the screen:

- **Driver live dashboard (FlutterMap):** ETA is computed **client-side** by calling OSRM through the gateway:
  - Request: `GET {GATEWAY}/route/v1/driving/{fromLon},{fromLat};{toLon},{toLat}`
  - Source field: `routes[0].duration` (seconds)
  - The app converts it into minutes/hours for display.

- **Backend dashboard card (FastAPI):** ETA is served from the database as the latest recorded value:
  - Table: `estimated_delivery_time`
  - Column used in code: `delay_time`
  - Selected as: latest row by `recorded_at DESC`
  - Formatted using `format_interval_hm(...)`.

---

## Running the system (development)
> This project uses Firebase Authentication and protected API routes. **Firebase tokens must be configured** before the apps can authenticate successfully.

### Firebase token setup (required)
1. Create a Firebase project and enable Email/Password authentication.
2. Add your Firebase Admin service account key to the backend environment (or container), and initialize Firebase Admin in the backend.
3. Ensure the mobile apps are configured with Firebase (`google-services.json` for Android) and are pointing to the correct Firebase project.
4. Driver/Patient/Hospital login will generate an **ID token**, which must be sent to the backend in:
   - `Authorization: Bearer <FIREBASE_ID_TOKEN>`

If tokens are not configured, secured endpoints (e.g., `/driver/me`) will return `401 Unauthorized`.

---

## Routing Data Setup (OSRM)

Due to size limitations, OSRM routing data is not stored in this repository.

### Generate routing data locally
1. Download Saudi Arabia OSM data:  
   https://download.geofabrik.de/asia/saudi-arabia.html

2. Place the file in:  
   `mapwithvrp/flutter_application_1/osrm-data/`

3. Run:
   ```bash
   bash build_osrm.sh
