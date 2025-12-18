import time, random, requests

BACKEND="http://localhost:8088"

ORDER_ID="40ccd06d-3faf-45ae-b04c-09fd9f3e7646"

eta = 1200  # 20 min
temp = 5.0

print(requests.post(f"{BACKEND}/stability/start", params={
    "order_id": ORDER_ID,
    "eta_seconds": eta
}).json())

for i in range(100):
    temp += random.uniform(-0.2, 0.5)
    eta = max(0, eta - 10)

    resp = requests.post(f"{BACKEND}/stability/update", params={
        "temp": temp,
        "lat": 24.71,
        "lon": 46.67,
        "eta_seconds": eta
    }).json()

    print(resp)

    if resp["status"] != "ok":
        break

    time.sleep(1)

print(requests.post(f"{BACKEND}/stability/finish").json())
