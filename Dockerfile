FROM ubuntu:22.04

# Build args (passed by GitHub Actions)
ARG BUILD_THREADS=4
ARG BUILD_TYPE=Release

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git curl wget python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Clone bitnet.cpp
WORKDIR /app
RUN git clone https://github.com/microsoft/BitNet.git bitnet && \
    cd bitnet && \
    git submodule update --init --recursive

# Build
WORKDIR /app/bitnet
RUN mkdir build && cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DLLAMA_AVX=OFF \
        -DLLAMA_AVX2=OFF \
        -DLLAMA_F16C=OFF \
        -DLLAMA_FMA=OFF \
        -DLLAMA_OPENMP=ON \
    && make -j${BUILD_THREADS}

# Expose port for API usage (adjust if needed)
EXPOSE 8000

# Default command (can be replaced in docker run)
CMD ["./build/bin/llama-bench", "--help"]
