#
# Dockerfile for building and running bitnet.cpp with a web API
# FINAL LEAN VERSION - Corrected COPY paths
#

# ==============================================================================
# R7: Production Grade - Use a multi-stage build to keep the final image small.
# Stage 1: Builder
# This stage compiles the C++ inference engine ONLY.
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

# Set up the application directory
WORKDIR /app

# R3: Clone the BitNet repository with its submodules.
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# R3: Generate the required C++ kernel source files. This is a lightweight, mandatory step.
RUN python3.10 utils/codegen_tl2.py --model "bitnet_b1_58-3B" --BM "160,320,320" --BK "96,96,96" --bm "32,32,32"

# R3: Build the bitnet.cpp C++ project using CMake and Clang.
RUN mkdir build && \
    cd build && \
    cmake -DBN_BUILD=ON .. && \
    cmake --build . --config Release

# R2: Install Python dependencies for our application.
# First, create the virtual environment.
RUN python3.10 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

# Copy the requirements files into the context BEFORE trying to install them.
COPY ./requirements.txt /app/requirements.txt
COPY ./api/requirements.txt /app/api/requirements.txt

# Now, install the dependencies since the files are present.
RUN pip install --no-cache-dir -r /app/requirements.txt && \
    pip install --no-cache-dir -r /app/api/requirements.txt


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
USER bitnet
WORKDIR /app

# MODIFIED: Corrected the COPY commands. All source paths for --from=builder
# must exist in the builder stage.
COPY --from=builder --chown=bitnet:bitnet /app/venv /app/venv
COPY --from=builder --chown=bitnet:bitnet /app/build/bin/main /app/bin/main
COPY --from=builder --chown=bitnet:bitnet /app/run_inference.py /app/run_inference.py
COPY --from=builder --chown=bitnet:bitnet /app/bitnet /app/bitnet
# The API and frontend code are copied from the local build context, not the builder stage.
COPY ./api /app/api
COPY ./frontend /app/frontend
COPY ./scripts/run.sh /app/run.sh
RUN chmod +x /app/run.sh

# R11: Create the directory that will serve as the mount point for the model.
RUN mkdir -p /app/models

# Set the PATH.
ENV PATH="/app/venv/bin:$PATH"

# Expose the API port.
EXPOSE 8000

# Define the entrypoint.
ENTRYPOINT ["/app/run.sh"]
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
