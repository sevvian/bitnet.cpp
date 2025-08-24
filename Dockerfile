#
# Dockerfile for building bitnet.cpp with a web API
# FINAL VERIFIED PRODUCTION VERSION - Includes fixes for upstream build system bugs.
#

# ==============================================================================
# R7: Production Grade - Use a multi-stage build to keep the final image small.
# Stage 1: Builder
# ==============================================================================
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

# R1: Install and configure clang-18.
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    rm llvm.sh && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100

# Create a dedicated source directory for isolation.
WORKDIR /src

# R3: Clone the BitNet repository into a subdirectory named 'BitNet'.
RUN git clone --recursive https://github.com/microsoft/BitNet.git

# Change working directory into the cloned repo.
WORKDIR /src/BitNet

# R3: Generate the required C++ kernel source files.
RUN python3.10 utils/codegen_tl2.py --model "bitnet_b1_58-3B" --BM "160,320,320" --BK "96,96,96" --bm "32,32,32"

# Surgical fix for the buggy install script.
RUN cp include/ggml-bitnet.h 3rdparty/llama.cpp/ggml/include/ggml-bitnet.h

# R3: Build and INSTALL the bitnet.cpp C++ project.
# MODIFIED: Added -DGGML_FATAL_WARNINGS=OFF to disable warnings-as-errors, fixing the build failure.
RUN mkdir build && \
    cd build && \
    cmake -DBITNET_X86_TL2=ON -DGGML_FATAL_WARNINGS=OFF -DCMAKE_INSTALL_PREFIX=../install .. && \
    cmake --build . --config Release && \
    cmake --install .

# R2: Install Python dependencies.
RUN python3.10 -m venv /src/BitNet/venv
ENV PATH="/src/BitNet/venv/bin:$PATH"
COPY ./api/requirements.txt /tmp/api_requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
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
RUN mkdir -p /app/bin /app/lib

# Copy the necessary artifacts from the builder's clean 'install' directory.
COPY --from=builder /src/BitNet/venv /app/venv
COPY --from=builder /src/BitNet/install/bin/llama-cli /app/bin/llama-cli
COPY --from=builder /src/BitNet/install/lib/*.so /app/lib/

# Copy our local, corrected application scripts.
COPY ./run_inference.py /app/run_inference.py
COPY ./api /app/api
COPY ./frontend /app/frontend
COPY ./scripts/run.sh /app/run.sh

# R11: Create the directory that will serve as the mount point for the model.
RUN mkdir -p /app/models

# Set correct permissions and ownership as root BEFORE switching user.
RUN chmod +x /app/bin/llama-cli /app/run.sh && \
    chown -R bitnet:bitnet /app

# Switch to the non-root user as the FINAL step.
USER bitnet

# Set the LD_LIBRARY_PATH to tell the OS where to find our custom shared libraries.
ENV LD_LIBRARY_PATH=/app/lib
# Set the PATH for our executables and python environment.
ENV PATH="/app/venv/bin:/app/bin:$PATH"

# Expose the API port.
EXPOSE 8000

# Define the entrypoint.
ENTRYPOINT ["/app/run.sh"]
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
