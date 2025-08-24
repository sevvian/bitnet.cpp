#
# Dockerfile for building and running bitnet.cpp
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
    python3.9 \
    python3-pip \
    python3.9-venv \
    cmake \
    build-essential

# R1: Install clang-18 as specified in the bitnet.cpp documentation.
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    rm llvm.sh

# Set up the application directory
WORKDIR /app

# R3: Clone the BitNet repository with its submodules.
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# R2: Create a Python virtual environment and install dependencies.
RUN python3.9 -m venv /app/venv
# Add venv to the PATH for subsequent commands
ENV PATH="/app/venv/bin:$PATH"
RUN pip install --no-cache-dir -r requirements.txt
# huggingface-cli is required for downloading models.
RUN pip install --no-cache-dir "huggingface-hub[cli]"

# R4: Download the specified GGUF model from Hugging Face.
# Using a pre-quantized GGUF model simplifies the setup process.
# We disable symlinks to ensure files are fully copied within the Docker layer.
RUN huggingface-cli download microsoft/BitNet-b1.58-2B-4T-gguf --local-dir /app/models/BitNet-b1.58-2B-4T-gguf --local-dir-use-symlinks False

# R3: Build the bitnet.cpp project using CMake and Clang.
# R6: This builds for a generic x86_64 architecture. When this Dockerfile is
#     built on the target Intel N5105, the compiler may apply native optimizations.
RUN mkdir build && \
    cd build && \
    CC=clang-18 CXX=clang++-18 cmake .. && \
    cmake --build . --config Release

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
    python3.9 \
    python3.9-venv \
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
# The 'main' executable is the core C++ inference engine.
COPY --from=builder --chown=bitnet:bitnet /app/build/bin/main /app/bin/main
# The Python scripts orchestrate the inference process.
COPY --from=builder --chown=bitnet:bitnet /app/run_inference.py /app/run_inference.py
# The 'bitnet' directory contains Python modules imported by run_inference.py.
COPY --from=builder --chown=bitnet:bitnet /app/bitnet /app/bitnet

# R4: Copy the downloaded model into the final image.
COPY --from=builder --chown=bitnet:bitnet /app/models /app/models

# R5: Copy the entrypoint script and make it executable.
COPY --chown=bitnet:bitnet scripts/run.sh /app/run.sh
RUN chmod +x /app/run.sh

# Set the PATH to include the virtual environment's bin directory.
ENV PATH="/app/venv/bin:$PATH"

# R5: Define the entrypoint to our custom script for inference execution.
ENTRYPOINT ["/app/run.sh"]

# Set a default command to run in conversation mode with a system prompt.
# This can be easily overridden when running the container.
CMD ["-p", "You are a helpful assistant.", "-cnv"]
