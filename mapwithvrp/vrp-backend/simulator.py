import math
import time
import argparse
import requests
from pathlib import Path

# ----------------------------
# Geometry helpers
# ----------------------------
def haversine_m(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))

def bearing_deg(lat1, lon1, lat2, lon2):
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    brng = math.degrees(math.atan2(y, x))
    return (brng + 360) % 360

# ----------------------------
# OSRM route (through gateway)
# ----------------------------
def fetch_osrm_route(gateway_base, start_lat, start_lon, end_lat, end_lon, timeout=30):
    url = (
        f"{gateway_base}/route/v1/driving/"
        f"{start_lon},{start_lat};{end_lon},{end_lat}"
        f"?overview=full&geometries=geojson"
    )
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    data = r.json()

    routes = data.get("routes") or []
    if not routes:
        raise RuntimeError("OSRM returned no routes")

    coords = routes[0]["geometry"]["coordinates"]  # [lon, lat]
    if not coords or len(coords) < 2:
        raise RuntimeError("OSRM returned too-short geometry")

    return [(float(c[1]), float(c[0])) for c in coords]  # [(lat, lon), ...]

# ----------------------------
# POST /iot/data (FastAPI)
# ----------------------------
def post_iot(api_base, order_id, lat, lon, temp_c, humidity, speed_mps, direction, timeout=15):
    url = f"{api_base}/iot/data"

    # Use form fields (works with your Form(...) endpoint)
    data = {
        "temperature": f"{temp_c:.2f}",
        "humidity": f"{humidity:.2f}",
        "latitude": f"{lat:.6f}",
        "longitude": f"{lon:.6f}",
        "speed": f"{speed_mps:.2f}",
        "direction": f"{direction:.2f}",
        "order_id": order_id,
    }

    r = requests.post(url, data=data, timeout=timeout)
    if r.status_code >= 400:
        print("IOT ERROR:", r.status_code, r.text)
        return None

    return r.json()

# ----------------------------
# Stability endpoints (gateway)
# ----------------------------
def stability_start(gateway_base, order_id, timeout=10):
    url = f"{gateway_base}/stability/start?order_id={order_id}"
    r = requests.post(url, timeout=timeout)
    # Some implementations return 200/201; accept any 2xx
    if not (200 <= r.status_code < 300):
        raise RuntimeError(f"stability/start failed: {r.status_code} {r.text}")
    return True

def stability_update(gateway_base, order_id, temp_c, lat, lon, timeout=10):
    url = f"{gateway_base}/stability/update?order_id={order_id}"
    payload = {"temp": temp_c, "lat": lat, "lon": lon}
    r = requests.post(url, json=payload, timeout=timeout)
    if not (200 <= r.status_code < 300):
        raise RuntimeError(f"stability/update failed: {r.status_code} {r.text}")
    return r.json()

# ----------------------------
# Live overrides via files
# ----------------------------
def read_override_float(path: Path):
    try:
        if not path.exists():
            return None
        s = path.read_text(encoding="utf-8").strip()
        if not s:
            return None
        return float(s)
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--order_id", required=True)
    ap.add_argument("--api_base", required=True, help="FastAPI base, e.g. http://192.168.8.177:8000")
    ap.add_argument("--gateway_base", required=True, help="Gateway base, e.g. http://192.168.8.177:8088")

    ap.add_argument("--start_lat", type=float, required=True)
    ap.add_argument("--start_lon", type=float, required=True)
    ap.add_argument("--end_lat", type=float, required=True)
    ap.add_argument("--end_lon", type=float, required=True)

    ap.add_argument("--interval", type=float, default=2.0, help="seconds between ticks")
    ap.add_argument("--speed_mps", type=float, default=8.0, help="meters/second (change anytime via speed.txt)")
    ap.add_argument("--temp", type=float, default=7.0, help="Celsius (change anytime via temp.txt)")
    ap.add_argument("--humidity", type=float, default=55.0)

    ap.add_argument("--stability_threshold", type=float, default=8.0, help="Countdown starts only if temp > threshold")
    ap.add_argument("--use_stability", action="store_true", help="call /stability/start + /stability/update")

    args = ap.parse_args()

    temp_file = Path("temp.txt")
    speed_file = Path("speed.txt")

    print("=== Simulator ===")
    print(f"order_id={args.order_id}")
    print(f"api_base={args.api_base}")
    print(f"gateway_base={args.gateway_base}")
    print(f"route: ({args.start_lat},{args.start_lon}) -> ({args.end_lat},{args.end_lon})")
    print("To change live values while running:")
    print("  - write a number into temp.txt (e.g. 10.5)")
    print("  - write a number into speed.txt (m/s) (e.g. 3.0)")
    print()

    route = fetch_osrm_route(args.gateway_base, args.start_lat, args.start_lon, args.end_lat, args.end_lon)
    print(f"route_points={len(route)} interval={args.interval}s")

    if args.use_stability:
        stability_start(args.gateway_base, args.order_id)
        print("stability session started ✅")

    # movement variables
    idx = 0
    cur_lat, cur_lon = route[0]
    last_lat, last_lon = cur_lat, cur_lon

    while idx < len(route) - 1:
        # live overrides
        temp_override = read_override_float(temp_file)
        speed_override = read_override_float(speed_file)

        temp_c = temp_override if temp_override is not None else args.temp
        speed_mps = speed_override if speed_override is not None else args.speed_mps

        # step distance for this tick
        step_dist = speed_mps * args.interval
        remaining = step_dist

        while remaining > 0 and idx < len(route) - 1:
            nlat, nlon = route[idx + 1]
            seg = haversine_m(cur_lat, cur_lon, nlat, nlon)

            if seg <= remaining:
                remaining -= seg
                cur_lat, cur_lon = nlat, nlon
                idx += 1
            else:
                t = remaining / seg if seg > 0 else 1.0
                cur_lat = cur_lat + (nlat - cur_lat) * t
                cur_lon = cur_lon + (nlon - cur_lon) * t
                remaining = 0

        direction = bearing_deg(last_lat, last_lon, cur_lat, cur_lon)

        # 1) Push telemetry to /iot/data (drives dashboard movement if you update driver.lat/lon in router)
        iot_resp = post_iot(
            args.api_base,
            args.order_id,
            cur_lat,
            cur_lon,
            temp_c,
            args.humidity,
            speed_mps,
            direction,
        )

        # 2) Push stability update (behaves like old Flutter code)
        stability_resp = None
        if args.use_stability:
            # Your requirement: countdown should not start until temp > 8
            # We still send updates; the backend should keep timer_started=false when temp <= threshold.
            stability_resp = stability_update(args.gateway_base, args.order_id, temp_c, cur_lat, cur_lon)

        alert = stability_resp.get("alert") if isinstance(stability_resp, dict) else None
        remaining_sec = stability_resp.get("remaining_seconds") if isinstance(stability_resp, dict) else None
        timer_started = stability_resp.get("timer_started") if isinstance(stability_resp, dict) else None

        print(
            f"lat={cur_lat:.6f} lon={cur_lon:.6f} "
            f"temp={temp_c:.2f}C speed={speed_mps:.2f}m/s dir={direction:.1f} "
            f"| iot_ok={iot_resp.get('status')} "
            f"| stability_started={timer_started} remaining={remaining_sec} alert={alert}"
        )

        # If stability says spoiled, you can stop or keep going (your choice)
        if alert in ("MAX_EXCURSION_EXCEEDED", "STABILITY_TIME_EXPIRED"):
            print("🚨 Stability failure alert received. Stopping simulation.")
            break

        last_lat, last_lon = cur_lat, cur_lon
        
        time.sleep(args.interval)

    print("Simulation ended.")

if __name__ == "__main__":
    main()
