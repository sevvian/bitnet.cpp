#
# Dockerfile for building bitnet.cpp with a web API
# FINAL VERIFIED PRODUCTION VERSION - Based on diagnostic audit of build artifacts.
#

# ==============================================================================
# R7: Production Grade - Use a multi-stage build to keep the final image small.
# Stage 1: Builder
# ==============================================================================
FROM ubuntu:22.04 AS builder

# Set a non-interactive frontend for package installations
ENV DEBIAN_FRONTEND=noninteractive

# R1: Install system dependencies.
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
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    rm llvm.sh

# Create a dedicated source directory for isolation.
WORKDIR /src

# R3: Clone the BitNet repository.
RUN git clone --recursive https://github.com/microsoft/BitNet.git

# Change working directory into the cloned repo.
WORKDIR /src/BitNet

# R2: Install Python dependencies into a venv.
RUN python3.10 -m venv venv
SHELL ["/bin/bash", "-c"]
RUN source venv/bin/activate && \
    pip install --no-cache-dir -r requirements.txt

# R3: Generate the LUT kernels.
RUN source venv/bin/activate && \
    python utils/codegen_tl2.py \
      --model bitnet_b1_58-3B \
      --BM 160,320,320 \
      --BK 96,96,96 \
      --bm 32,32,32

# R3: Build with Clang.
RUN mkdir build && \
    cd build && \
    export CC=clang-18 CXX=clang++-18 && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . --parallel $(nproc)

# ---!!! FINAL ARTIFACT GATHERING STEP !!!---
# The build is successful, but libraries are scattered. We will find all .so files
# and copy them to a clean 'install' directory for easy packaging.
RUN mkdir -p /install/lib && \
    find /src/BitNet/build -name "*.so" -exec cp {} /install/lib/ \;

# Install API dependencies in the same venv.
COPY ./api/requirements.txt /tmp/api_requirements.txt
RUN source venv/bin/activate && \
    pip install --no-cache-dir -r /tmp/api_requirements.txt


# ==============================================================================
# Stage 2: Final Image
# ==============================================================================
FROM ubuntu:22.04

# Install only essential runtime dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    libstdc++6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create a dedicated, non-root user for security.
RUN useradd -m -s /bin/bash bitnet
WORKDIR /app

# Create the final directory structure for our application.
RUN mkdir -p /app/build/bin /app/lib

# Copy the necessary artifacts from the builder stage.
COPY --from=builder /src/BitNet/venv /app/venv
COPY --from=builder /src/BitNet/build/bin/llama-cli /app/build/bin/llama-cli
# MODIFIED: Copy ALL shared libraries from our clean '/install/lib' directory.
COPY --from=builder /install/lib/*.so /app/lib/
COPY --from=builder /src/BitNet/run_inference.py /app/run_inference.py

# Copy our application code.
COPY ./api /app/api
COPY ./frontend /app/frontend
COPY ./scripts/run.sh /app/run.sh

# R11: Create the directory that will serve as the mount point for the model.
RUN mkdir -p /app/models

# Set correct permissions and ownership as root BEFORE switching user.
RUN chmod +x /app/build/bin/llama-cli /app/run.sh && \
    chown -R bitnet:bitnet /app

# Switch to the non-root user as the FINAL step.
USER bitnet

# Set the LD_LIBRARY_PATH to tell the OS where to find our custom shared libraries.
ENV LD_LIBRARY_PATH=/app/lib
# Set the PATH for our python environment.
ENV PATH="/app/venv/bin:$PATH"

# Expose the API port.
EXPOSE 8000

# Define the entrypoint.
ENTRYPOINT ["/app/run.sh"]
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
