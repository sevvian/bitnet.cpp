#!/usr/bin/env bash
set -euo pipefail


: "${THREADS:=4}"
: "${CTX_SIZE:=2048}"
: "${TEMPERATURE:=0.7}"
: "${PORT:=8000}"


# Ensure model exists; if not, print guidance
if ! ls /workspace/models/*/ggml-model-*.gguf >/dev/null 2>&1; then
echo "[entrypoint] No GGUF model found under /workspace/models/*/ggml-model-*.gguf" >&2
echo "You can place one manually, or exec into the container and run:"
echo " huggingface-cli download microsoft/BitNet-b1.58-2B-4T-gguf --local-dir /workspace/models/BitNet-b1.58-2B-4T"
fi


# Start REST API
exec python /workspace/app/server.py --threads "$THREADS" --ctx-size "$CTX_SIZE" --temperature "$TEMPERATURE" --port "$PORT"
