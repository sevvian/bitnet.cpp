#
# Dockerfile for building bitnet.cpp with a web API
# FINAL DIAGNOSTIC VERSION: This file will audit its own build output to find the exact
# location of the compiled binaries AND all shared libraries.
#

# ==============================================================================
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

# ---!!! THIS IS THE NEW DIAGNOSTIC STEP !!!---
# Since we know the build succeeds, we will now find all the artifacts.
RUN echo "--- [DIAGNOSTIC AUDIT START] ---" && \
    echo "--- Auditing build output directory recursively: /src/BitNet/build/ ---" && \
    ls -lR /src/BitNet/build/ && \
    echo "--- [DIAGNOSTIC AUDIT END] ---"

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

# The COPY commands below will be corrected after the diagnostic audit.
# For now, we expect them to fail, which is part of the plan.
RUN mkdir -p /app/build/bin /app/lib

COPY --from=builder /src/BitNet/venv /app/venv
COPY --from=builder /src/BitNet/build/bin/llama-cli /app/build/bin/llama-cli
COPY --from=builder /src/BitNet/build/lib/*.so /app/lib/
COPY --from=builder /src/BitNet/run_inference.py /app/run_inference.py
COPY ./api /app/api
COPY ./frontend /app/frontend
COPY ./scripts/run.sh /app/run.sh

RUN mkdir -p /app/models
RUN chmod +x /app/build/bin/llama-cli /app/run.sh && \
    chown -R bitnet:bitnet /app
USER bitnet
ENV LD_LIBRARY_PATH=/app/lib
ENV PATH="/app/venv/bin:$PATH"
EXPOSE 8000
ENTRYPOINT ["/app/run.sh"]
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
