# Teryaq (تِرياق) — Smart Cold-Chain Medication Delivery & Monitoring System

Teryaq is a multi-role healthcare logistics system for **temperature-sensitive medication delivery**. It combines Flutter mobile apps, a FastAPI backend, a PostgreSQL database, a self-hosted OpenStreetMap stack (TileServer-GL + OSRM), real-time IoT telemetry (temperature + GPS), and safety workflows that protect medication integrity throughout delivery.

---

## Demo 
The demo link provides additional details about the project and includes a recorded video demonstrating the live application workflow, showcasing the actual user interface and real usage of each screen in action.
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
## Running the System (Development)

- Start all backend services using **Docker / Docker Compose**.
- Backend services are exposed on a **local network IP** (e.g. `192.168.x.x`), not `localhost`.

### Required configuration
- Update all backend IPs and ports in the **Flutter frontend** to match the Docker backend, including:
  - FastAPI API base URL
  - TileServer-GL / OSRM gateway URL
- If the backend IP changes, the frontend constants and request headers must be updated.

### Firebase Authentication (required)
1. Create a Firebase project and enable **Email/Password Authentication**.
2. Add the Firebase **Admin SDK service account key** to the backend environment.
3. Configure Firebase in the Flutter app (`google-services.json` for Android).
4. All secured requests must include:

Authorization: Bearer <FIREBASE_ID_TOKEN>


### Routing Data Setup (OSRM)
Routing data is not stored in this repository.

1. Download Saudi Arabia OSM data:  
https://download.geofabrik.de/asia/saudi-arabia.html
2. Place the file in:

mapwithvrp/flutter_application_1/osrm-data/

3. Build routing data:
```bash
bash build_osrm.sh
