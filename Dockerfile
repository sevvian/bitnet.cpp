# Base: Ubuntu 24.04 (has recent clang / cmake)
FROM ubuntu:24.04


ARG DEBIAN_FRONTEND=noninteractive
ARG HF_REPO=microsoft/BitNet-b1.58-2B-4T-gguf
ARG MODEL_SUBDIR=BitNet-b1.58-2B-4T
ARG QUANT=i2_s


# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
git ca-certificates curl wget build-essential \
python3 python3-pip python3-venv \
cmake ninja-build \
clang-18 lld-18 libomp-18-dev \
git-lfs \
&& rm -rf /var/lib/apt/lists/*


# Default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1


# Workspace
WORKDIR /workspace


# Clone BitNet with submodules
RUN git lfs install && \
git clone --recursive https://github.com/microsoft/BitNet.git && \
cd BitNet && git submodule update --init --recursive


# Python deps (hosted tools/scripts)
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir --break-system-packages -r /workspace/requirements.txt



# Build bitnet.cpp (CPU, NO AVX/F16C/FMA for Tremont)
# We go through the repo’s Python build path which calls CMake under the hood.
ENV CC=clang-18 CXX=clang++-18


# Pre-fetch model into mounted /workspace/models (if present). Will also work offline.
RUN mkdir -p /workspace/models/${MODEL_SUBDIR}


# Optional: fetch model at build time (skippable if you prefer volume-only)
# Using huggingface-cli honors HF_TOKEN if set at build-time.
RUN if [ -n "$HF_REPO" ]; then \
huggingface-cli download "$HF_REPO" --local-dir /workspace/models/${MODEL_SUBDIR} || true ; \
fi


# Prepare environment (quantization and paths)
RUN cd BitNet && \
python setup_env.py -md /workspace/models/${MODEL_SUBDIR} -q ${QUANT} || true


# Explicit CMake build with safe flags for N5105 (no AVX/AVX2/F16C/FMA)
RUN cmake -S BitNet -B BitNet/build \
-G Ninja \
-DCMAKE_C_COMPILER=clang-18 \
-DCMAKE_CXX_COMPILER=clang++-18 \
-DCMAKE_BUILD_TYPE=Release \
-DLLAMA_NATIVE=OFF \
-DLLAMA_AVX=OFF \
-DLLAMA_AVX2=OFF \
-DLLAMA_F16C=OFF \
-DLLAMA_FMA=OFF \
-DLLAMA_OPENMP=ON \
&& cmake --build BitNet/build --target all


# App server
COPY app /workspace/app
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod +x /workspace/entrypoint.sh


ENV PATH="/workspace/BitNet/build/bin:$PATH"


EXPOSE 8000


# Non-root user
RUN useradd -m -u 1000 runner && chown -R runner:runner /workspace
USER runner


ENTRYPOINT ["/workspace/entrypoint.sh"]
