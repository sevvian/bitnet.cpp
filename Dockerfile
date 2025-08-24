#
# Dockerfile for building and running bitnet.cpp with a web API
#

# ==============================================================================
# R7: Production Grade - Use a multi-stage build to keep the final image small.
# Stage 1: Builder
# This stage installs all build-time dependencies, clones the source code,
# builds the C++ project, and downloads the model.
# ==============================================================================
# Use a specific version for reproducibility.
FROM ubuntu:22.04 AS builder

# Set a non-interactive frontend for package installations
ENV DEBIAN_FRONTEND=noninteractive

# R1: Install system dependencies required for the build.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    ca-certificates \
    python3.10 \
    python3-pip \
    python3.10-venv \
    cmake \
    build-essential \
    lsb-release \
    software-properties-common \
    gnupg

# R1: Install clang-18 as specified in the bitnet.cpp documentation.
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    rm llvm.sh

# Set up the application directory
WORKDIR /app

# R3: Clone the BitNet repository with its submodules.
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# R2: Create a Python virtual environment and install dependencies for bitnet.cpp.
RUN python3.10 -m venv /app/venv
# Add venv to the PATH for subsequent commands
ENV PATH="/app/venv/bin:$PATH"
RUN pip install --no-cache-dir -r requirements.txt
# huggingface-cli is required for downloading models.
RUN pip install --no-cache-dir "huggingface-hub[cli]"

# R4: MODIFIED - Download the BASE model repository, not the pre-quantized GGUF.
# This is required as input for the setup_env.py script.
RUN huggingface-cli download microsoft/BitNet-b1.58-2B-4T --local-dir /app/models/BitNet-b1.58-2B-4T --local-dir-use-symlinks False

# R3: MODIFIED - Execute the setup_env.py script. THIS IS THE CRITICAL FIX.
# This script prepares the environment by quantizing the model AND, crucially,
# generating or linking the source files (like bitnet-lut-kernels.h) needed by CMake.
RUN python setup_env.py -md /app/models/BitNet-b1.58-2B-4T -q i2_s

# R3: Build the bitnet.cpp project using CMake and Clang.
# The -DBN_BUILD=ON flag is still required to instruct CMake to use the BitNet-specific build paths.
RUN mkdir build && \
    cd build && \
    CC=clang-18 CXX=clang++-18 cmake -DBN_BUILD=ON .. && \
    cmake --build . --config Release

# Copy API and frontend code into the builder stage
COPY ./api /app/api
COPY ./frontend /app/frontend

# R2: Install API-specific Python dependencies
RUN pip install --no-cache-dir -r /app/api/requirements.txt


# ==============================================================================
# Stage 2: Final Image
# This stage creates the final, minimal runtime image. It copies only the
# necessary artifacts from the builder stage.
# ==============================================================================
FROM ubuntu:22.04

# Set a non-interactive frontend for package installations
ENV DEBIAN_FRONTEND=noninteractive

# R7: Production Grade - Install only essential runtime dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-venv \
    libstdc++6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# R7: Production Grade - Create a dedicated, non-root user for security.
RUN useradd -m -s /bin/bash bitnet
USER bitnet
WORKDIR /app

# Copy the Python virtual environment from the builder stage.
COPY --from=builder --chown=bitnet:bitnet /app/venv /app/venv

# Copy the compiled C++ executables and Python scripts required for inference.
COPY --from=builder --chown=bitnet:bitnet /app/build/bin/main /app/bin/main
COPY --from=builder --chown=bitnet:bitnet /app/run_inference.py /app/run_inference.py
COPY --from=builder --chown=bitnet:bitnet /app/bitnet /app/bitnet

# R4: Copy the processed model directory into the final image.
# The GGUF file will be located inside this directory after setup_env.py runs.
COPY --from=builder --chown=bitnet:bitnet /app/models /app/models

# Copy the API and frontend code
COPY --from=builder --chown=bitnet:bitnet /app/api /app/api
COPY --from=builder --chown=bitnet:bitnet /app/frontend /app/frontend

# Copy the entrypoint script and make it executable.
COPY --chown=bitnet:bitnet scripts/run.sh /app/run.sh
RUN chmod +x /app/run.sh

# Set the PATH to include the virtual environment's bin directory.
ENV PATH="/app/venv/bin:$PATH"

# R8: Expose the port the API will run on.
EXPOSE 8000

# R5, R8: Define the entrypoint to our custom script which now starts the web server.
ENTRYPOINT ["/app/run.sh"]

# Default command for the entrypoint script (starts the server).
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
