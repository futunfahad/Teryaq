import json
import httpx
import asyncio

OLLAMA_URL = "http://localhost:11434"
OLLAMA_MODEL = "iKhalid/ALLaM:7b-q3_K_S"

async def stream_reply(prompt: str):
    async with httpx.AsyncClient(timeout=None) as client:
        async with client.stream(
            "POST",
            f"{OLLAMA_URL}/api/generate",
            json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": True},
        ) as response:
            async for line in response.aiter_lines():
                if not line:
                    continue
                if line.startswith("data:"):
                    line = line[5:].strip()
                if not line or line == "[DONE]":
                    break
                try:
                    obj = json.loads(line)
                    token = obj.get("response", "")
                    if token:
                        yield token
                    if obj.get("done"):
                        break
                except json.JSONDecodeError:
                    continue
