import argparse
import subprocess
import shlex
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
import os
from pathlib import Path


app = FastAPI(title="bitnet.cpp API (CPU)")


class GenerateRequest(BaseModel):
prompt: str
max_new_tokens: int = 128
system: str | None = None
temperature: float | None = None
threads: int | None = None
ctx_size: int | None = None


class GenerateResponse(BaseModel):
output: str


# Locate a gguf model (prefer i2_s if present)


def find_model() -> str:
paths = list(Path("/workspace/models").glob("*/ggml-model-*.gguf"))
if not paths:
raise RuntimeError("No GGUF model found under /workspace/models/*/ggml-model-*.gguf")
# Prefer i2_s if available
for p in paths:
if "i2_s" in p.name:
return str(p)
return str(paths[0])


MODEL_PATH = os.environ.get("MODEL_PATH", find_model())


@app.get("/healthz")
async def healthz():
return {"status": "ok", "model": MODEL_PATH}


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest):
model = MODEL_PATH
threads = req.threads or int(os.environ.get("THREADS", "4"))
ctx = req.ctx_size or int(os.environ.get("CTX_SIZE", "2048"))
temp = req.temperature or float(os.environ.get("TEMPERATURE", "0.7"))


sys_prompt = req.system or "You are a helpful assistant."
# Use bitnet.cpp runner
cmd = [
"python", "run_inference.py",
"-m", model,
"-n", str(req.max_new_tokens),
"-p", sys_prompt + "\n\n" + req.prompt,
"-t", str(threads),
"-c", str(ctx),
"-temp", str(temp),
]
# Prefer conversation mode for instruct models
if "instruct" in model.lower() or "-chat" in model.lower():
cmd.append("-cnv")


proc = subprocess.run(cmd, cwd="/workspace/BitNet", capture_output=True, text=True)
if proc.returncode != 0:
raise RuntimeError(f"bitnet runner failed: {proc.stderr}")
# The script prints the generation; return stdout
return GenerateResponse(output=proc.stdout.strip())


if __name__ == "__main__":
ap = argparse.ArgumentParser()
ap.add_argument("--threads", type=int, default=int(os.environ.get("THREADS", "4")))
ap.add_argument("--ctx-size", type=int, default=int(os.environ.get("CTX_SIZE", "2048")))
ap.add_argument("--temperature", type=float, default=float(os.environ.get("TEMPERATURE", "0.7")))
ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8000")))
args = ap.parse_args()
uvicorn.run(app, host="0.0.0.0", port=args.port)
