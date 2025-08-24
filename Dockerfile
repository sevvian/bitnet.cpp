#
# Dockerfile for building and running bitnet.cpp with a web API
# FINAL VERIFIED PRODUCTION VERSION - Includes shared library dependency.
#

# ==============================================================================
# R7: Production Grade - Use a multi-stage build to keep the final image small.
# Stage 1: Builder
# This stage compiles the C++ inference engine in an isolated directory.
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

# R3: Build the bitnet.cpp C++ project.
RUN mkdir build && \
    cd build && \
    cmake -DBITNET_X86_TL2=ON .. && \
    cmake --build . --config Release

# R2: Install Python dependencies.
RUN python3.10 -m venv /src/BitNet/venv
ENV PATH="/src/BitNet/venv/bin:$PATH"
COPY ./api/requirements.txt /tmp/api_requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -r /tmp/api_requirements.txt


# ==============================================================================
# Stage 2: Final Image
# This stage creates the final, minimal runtime image without the model.
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

# Create the directory structure the application and its libraries expect.
RUN mkdir -p /app/build/bin /app/build/lib

# Copy the necessary artifacts from the builder stage.
COPY --from=builder /src/BitNet/venv /app/venv
COPY --from=builder /src/BitNet/build/bin/llama-cli /app/build/bin/llama-cli
# MODIFIED: Copy the essential shared library dependency.
COPY --from=builder /src/BitNet/build/lib/libllama.so /app/build/lib/libllama.so
COPY --from=builder /src/BitNet/run_inference.py /app/run_inference.py

# The API, frontend, and scripts are copied from the local build context.
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

# MODIFIED: Set the LD_LIBRARY_PATH to tell the OS where to find our custom shared library.
ENV LD_LIBRARY_PATH=/app/build/lib
# Set the PATH for our executables and python environment.
ENV PATH="/app/venv/bin:$PATH"

# Expose the API port.
EXPOSE 8000

# Define the entrypoint.
ENTRYPOINT ["/app/run.sh"]
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
