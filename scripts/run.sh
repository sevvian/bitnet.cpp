#!/bin/bash
# R7: Production Grade - Use set -e to exit immediately if a command fails.
set -e

#
# R5, R8: Web Service Entrypoint Script
#
# This script serves as the entrypoint for the Docker container.
# It activates the Python environment and then executes the command passed to it ($@).
# By default, this will be the uvicorn server command defined in the Dockerfile CMD.
#

# Activate the Python virtual environment.
source /app/venv/bin/activate

# Execute the command passed as arguments to this script
exec "$@"
