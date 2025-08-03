# Dockerfile for building llama.cpp with CUDA and multimodal support
# Version is specified at runtime, not build time
FROM nvidia/cuda:12.9.1-devel-ubuntu22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    libcurl4-openssl-dev \
    libgomp1 \
    unzip \
    pkg-config \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /workspace

# Create output directory
RUN mkdir -p /output

# Create the build script that will be run at runtime
COPY <<'EOF' /build-llama.sh
#!/bin/bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Error: VERSION parameter is required"
    echo "Usage: docker run ... <image> <version>"
    echo "Example: docker run ... llama-cpp-builder 3875"
    exit 1
fi

echo "Building llama.cpp version: $VERSION"

# Clean workspace
rm -rf /workspace/llama.cpp*

# Download and extract llama.cpp source code
cd /workspace
echo "Downloading llama.cpp version: $VERSION"
wget -O llama-cpp.tar.gz "https://github.com/ggerganov/llama.cpp/archive/refs/tags/b${VERSION}.tar.gz"
tar -xzf llama-cpp.tar.gz
mv llama.cpp-b${VERSION} llama.cpp
rm llama-cpp.tar.gz

# Initialize git repository and tag the version
cd /workspace/llama.cpp
echo "Initializing git repository and tagging version..."
git init
git config  user.email "builder@docker.local"
git config  user.name "Docker Builder"
git add .
git commit -m "Commit for version b${VERSION}"
git tag "b${VERSION}"

echo "Configuring build with CUDA and multimodal support..."
cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_CUDA=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_CURL=ON \
    -DLLAMA_MULTIMODAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined \
    .

echo "Building llama.cpp (this may take several minutes)..."
cmake --build build --config Release -j$(nproc)

# Clean output directory
rm -rf /output/*

# Copy built binaries to output directory (excluding test files)
echo "Copying binaries to output directory..."
find build/bin -type f -executable ! -name "test-*" -exec cp {} /output/ \; 2>/dev/null || true

# Copy shared libraries
echo "Copying shared libraries..."
find build -name "*.so" -exec cp {} /output/ \; 2>/dev/null || true

# Set permissions on output binaries
chmod +x /output/* 2>/dev/null || true

echo "Build completed successfully!"
echo "Built binaries:"
ls -la /output/

# Create version info file
echo "$VERSION" > /output/.version

# Run verification
/verify.sh
EOF

RUN chmod +x /build-llama.sh

# Create a verification script
COPY <<'EOF' /verify.sh
#!/bin/bash
echo "========================================="
echo "Llama.cpp Build Verification"
echo "========================================="
echo "CUDA support: $(nvidia-smi > /dev/null 2>&1 && echo "Available" || echo "Not available")"
echo "Built binaries:"
ls -la /output/
echo ""
if [ -f /output/.version ]; then
    echo "Built version: $(cat /output/.version)"
fi
if [ -f /output/llama-cli ]; then
    echo ""
    echo "Testing llama-cli version:"
    /output/llama-cli --version 2>&1 || echo "Version check failed"
fi
echo "========================================="
EOF

RUN chmod +x /verify.sh

# Set the output directory as a volume mount point
VOLUME ["/output"]

# Set entrypoint to the build script
ENTRYPOINT ["/build-llama.sh"]

# Build instructions:
# docker build -t llama-cpp-builder -f cuda-builder.Dockerfile .
# 
# Run with version parameter and volume mount:
# docker run --gpus all -v $(pwd)/output:/output llama-cpp-builder 3875
#
# Or run interactively for debugging:
# docker run --gpus all -it -v $(pwd)/output:/output --entrypoint /bin/bash llama-cpp-builder