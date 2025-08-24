# Base image
FROM ubuntu:22.04

# Set non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    cmake \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    clang-18 \
    lld-18 \
    ninja-build \
    wget \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set workspace
WORKDIR /workspace

# Clone BitNet repo + submodules
RUN git clone https://github.com/microsoft/BitNet.git && \
    cd BitNet && \
    git submodule sync --recursive && \
    git submodule update --init --recursive --force

# Install Python deps first (gguf-py)
RUN pip3 install --no-cache-dir ./BitNet/3rdparty/llama.cpp/gguf-py

# Copy custom API & frontend
COPY ./api /workspace/api
COPY ./frontend /workspace/frontend
COPY requirements.txt /workspace/requirements.txt

# Install Python requirements
RUN python3 -m venv /workspace/venv && \
    . /workspace/venv/bin/activate && \
    pip install --no-cache-dir -r /workspace/requirements.txt

# Ensure models directory exists
RUN mkdir -p /workspace/models/BitNet-b1.58-2B-4T

# Download model (using hf CLI)
RUN if [ -n "microsoft/BitNet-b1.58-2B-4T-gguf" ]; then \
        huggingface-cli download "microsoft/BitNet-b1.58-2B-4T-gguf" --local-dir /workspace/models/BitNet-b1.58-2B-4T || true ; \
    fi

# Run BitNet setup environment
RUN cd BitNet && python3 setup_env.py -md /workspace/models/BitNet-b1.58-2B-4T -q i2_s

# Generate missing LUT kernels if absent
RUN cd BitNet && \
    if [ ! -f include/bitnet-lut-kernels.h ]; then \
        echo "Generating missing LUT kernels header..." && \
        python3 scripts/gen_lut.py; \
    fi

# Build BitNet with CMake
RUN cd BitNet && mkdir -p build && cd build && \
    cmake -G Ninja .. \
    -DCMAKE_C_COMPILER=clang-18 \
    -DCMAKE_CXX_COMPILER=clang++-18 \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_NATIVE=OFF \
    -DLLAMA_AVX=OFF \
    -DLLAMA_AVX2=OFF \
    -DLLAMA_F16C=OFF \
    -DLLAMA_FMA=OFF \
    -DLLAMA_OPENMP=ON && \
    ninja

# Expose API port
EXPOSE 8000

# Set default command to run API (assumes FastAPI/uvicorn)
WORKDIR /workspace/api
CMD ["/workspace/venv/bin/uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
