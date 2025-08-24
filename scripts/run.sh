#!/bin/bash
# R7: Production Grade - Use set -e to exit immediately if a command fails.
set -e

#
# R5, R8: Web Service Entrypoint Script
#
# This script serves as the entrypoint for the Docker container.
# It verifies the model exists, activates the Python environment,
# and then executes the command passed to it ($@).
#

# R11: Define the path to the model and verify it exists before starting.
# This check is crucial because the model is a runtime dependency via volume mount.
MODEL_PATH="/app/models/ggml-model-i2_s.gguf"

if [ ! -f "$MODEL_PATH" ]; then
    echo "---"
    echo "FATAL ERROR: Model file not found at $MODEL_PATH"
    echo "Please ensure you have downloaded the GGUF model and that the volume mount in docker-compose.yml is correct."
    echo "See README.md for instructions."
    echo "---"
    exit 1
fi

# Activate the Python virtual environment.
source /app/venv/bin/activate

# Execute the command passed as arguments to this script
exec "$@"
