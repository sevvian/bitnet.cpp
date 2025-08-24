#!/bin/bash
# R7: Production Grade - Use set -e to exit immediately if a command fails.
set -e

#
# R5: Inference Execution Entrypoint Script
#
# This script serves as the entrypoint for the Docker container.
# It activates the Python environment and executes the inference script,
# passing along any user-provided arguments.
#

# Define the path to the default model file inside the container.
DEFAULT_MODEL_PATH="/app/models/BitNet-b1.58-2B-4T-gguf/ggml-model-i2_s.gguf"

# Check if the model file exists at the expected path.
if [ ! -f "$DEFAULT_MODEL_PATH" ]; then
    echo "Error: Model file not found at $DEFAULT_MODEL_PATH"
    echo "Please ensure the model exists. If using a volume mount, check the './models' directory on your host."
    exit 1
fi

# Activate the Python virtual environment.
source /app/venv/bin/activate

# Execute the run_inference.py script.
# The model path is provided first, followed by all arguments ($@) passed
# to this script (from the `docker run` or `docker-compose` command).
# This provides flexibility to the user.
echo "=========================================="
echo "Starting bitnet.cpp inference engine..."
echo "Model: $DEFAULT_MODEL_PATH"
echo "Arguments: $@"
echo "=========================================="
echo ""

python run_inference.py -m "$DEFAULT_MODEL_PATH" "$@"
