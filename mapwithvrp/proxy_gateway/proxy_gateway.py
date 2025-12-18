from fastapi import FastAPI, Request
from fastapi.responses import Response, JSONResponse
import httpx

app = FastAPI()

@app.get("/test")
async def test():
    return {"status": "Gateway running on 8088"}


@app.api_route("/{path:path}", methods=["GET", "POST"])
async def proxy(path: str, request: Request):
    print(f"🔁 Proxy → /{path}")

    # ---------------------------------------
    # 🔥 ROUTE MATCHING LOGIC (UPDATED)
    # ---------------------------------------
    
    # 1) Driver VRP endpoint
    # Example: /driver/hgs?driver_id=xxx
    if path.startswith("driver/hgs"):
        upstream = f"http://vrp_backend:9000/{path}"

    # 2) Normal HGS route
    elif path.startswith("hgs"):
        upstream = f"http://vrp_backend:9000/{path}"

    # 3) OSRM routing
    elif path.startswith("route"):
        upstream = f"http://osrm_backend:5000/{path}"

    # 4) Tileserver GL
    elif path.startswith("tiles/"):
        sub = path[len("tiles/"):]
        upstream = f"http://tileserver_gl:2000/{sub}"
        # ---------------------------------
    # 🧊 New: Stability Monitor Forwarding
    # ---------------------------------
    elif path.startswith("stability"):
        upstream = f"http://vrp_backend:9000/{path}"

    # 5) Unknown
    else:
        return JSONResponse({"error": f"Unknown route: /{path}"}, status_code=404)

    # ---------------------------------------
    # 🔁 EXECUTE PROXY REQUEST
    # ---------------------------------------
    try:
        async with httpx.AsyncClient() as client:
            upstream_resp = await client.request(
                method=request.method,
                url=upstream,
                content=await request.body(),
                params=request.query_params,
                headers={
                    k: v
                    for k, v in request.headers.items()
                    if k.lower() != "host"  # avoid overwriting upstream host
                },
                timeout=60,
            )

        # ---------------------------------------
        # FIX: Only forward content-type
        # ---------------------------------------
        content_type = upstream_resp.headers.get(
            "content-type", "application/octet-stream"
        )

        return Response(
            content=upstream_resp.content,
            status_code=upstream_resp.status_code,
            media_type=content_type,
        )

    except Exception as e:
        print("❌ PROXY ERROR:", e)
        return JSONResponse({"error": str(e)}, status_code=502)
