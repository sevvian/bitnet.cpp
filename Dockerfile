#
# Dockerfile for building bitnet.cpp with a web API
# FINAL VERIFIED PRODUCTION VERSION
#

# ==============================================================================
# Stage 1: Builder
# ==============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ca-certificates python3.10 python3-pip python3.10-venv \
    cmake build-essential lsb-release software-properties-common gnupg
RUN wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 18 && rm llvm.sh

WORKDIR /src
RUN git clone --recursive https://github.com/microsoft/BitNet.git
WORKDIR /src/BitNet

RUN python3.10 -m venv venv
SHELL ["/bin/bash", "-c"]
RUN source venv/bin/activate && pip install --no-cache-dir -r requirements.txt

RUN source venv/bin/activate && \
    python utils/codegen_tl2.py --model bitnet_b1_58-3B --BM 160,320,320 --BK 96,96,96 --bm 32,32,32

RUN mkdir build && cd build && \
    export CC=clang-18 CXX=clang++-18 && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . --parallel $(nproc)

COPY ./api/requirements.txt /tmp/api_requirements.txt
RUN source venv/bin/activate && pip install --no-cache-dir -r /tmp/api_requirements.txt

# ==============================================================================
# Stage 2: Final Image
# ==============================================================================
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 libstdc++6 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash bitnet
WORKDIR /app

RUN mkdir -p /app/build/bin

COPY --from=builder /src/BitNet/venv /app/venv
COPY --from=builder /src/BitNet/build/bin/llama-cli /app/build/bin/llama-cli
COPY --from=builder /src/BitNet/run_inference.py /app/run_inference.py

COPY ./api /app/api
COPY ./frontend /app/frontend
COPY ./scripts/run.sh /app/run.sh
# MODIFIED: Copy our new grammar file into the container.
COPY ./grammar /app/grammar

RUN mkdir -p /app/models
RUN chmod +x /app/build/bin/llama-cli /app/run.sh && \
    chown -R bitnet:bitnet /app
USER bitnet

ENV PATH="/app/venv/bin:$PATH"
EXPOSE 8000
ENTRYPOINT ["/app/run.sh"]
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
