#!/usr/bin/env bash
#
# Test STT Service installer in a disposable Docker sandbox
# GPU passthrough enabled - requires nvidia-container-toolkit
#
# Usage:
#   ./test-sandbox.sh              # Interactive shell in fresh Ubuntu
#   ./test-sandbox.sh --auto       # Run installer non-interactively
#   ./test-sandbox.sh --clean      # Remove test container/image
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONTAINER_NAME="stt-test-sandbox"
IMAGE_NAME="stt-test-ubuntu"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}▶${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

show_help() {
    cat << 'EOF'
STT Service Test Sandbox

Creates a minimal Ubuntu 24.04 container with GPU access for testing the installer.
The installer handles all CUDA setup - this tests the full installation flow.
The container is disposable - delete it anytime with --clean.

USAGE:
    ./test-sandbox.sh              Interactive shell (recommended for first test)
    ./test-sandbox.sh --auto       Run installer automatically (non-interactive)
    ./test-sandbox.sh --clean      Remove container and image

INSIDE THE CONTAINER:
    # Test the curl install (uses local files, not GitHub)
    bash /mnt/install.sh

    # Or test with options
    STT_NONINTERACTIVE=1 bash /mnt/install.sh
    bash /mnt/install.sh --help
    bash /mnt/install.sh --uninstall

    # Verify GPU access
    nvidia-smi

    # Exit when done
    exit

NOTES:
    - Container mounts this project at /mnt (read-only)
    - Install goes to ~/stt-service inside container
    - GPU is passed through via --gpus all
    - Container persists between runs (use --clean to remove)
EOF
}

build_image() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        info "Using existing test image: $IMAGE_NAME"
        return
    fi

    info "Building test image (Ubuntu 24.04 - minimal, no CUDA)..."
    docker build -t "$IMAGE_NAME" - << 'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Truly minimal - installer handles CUDA, PortAudio, everything
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create test user (non-root, with sudo)
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER testuser
WORKDIR /home/testuser

CMD ["/bin/bash"]
DOCKERFILE
    info "Image built: $IMAGE_NAME"
}

run_interactive() {
    build_image

    info "Starting interactive sandbox..."
    info "Project mounted at /mnt (read-only)"
    echo ""
    warn "Test commands to run inside:"
    echo "  bash /mnt/install.sh           # Interactive install"
    echo "  bash /mnt/install.sh --help    # Show help"
    echo "  nvidia-smi                     # Verify GPU"
    echo ""

    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        --gpus all \
        -v "$PROJECT_DIR:/mnt:ro" \
        -e "HOME=/home/testuser" \
        "$IMAGE_NAME" \
        bash
}

run_auto() {
    build_image

    info "Running non-interactive install test..."

    docker run --rm \
        --name "$CONTAINER_NAME" \
        --gpus all \
        -v "$PROJECT_DIR:/mnt:ro" \
        -e "HOME=/home/testuser" \
        -e "STT_NONINTERACTIVE=1" \
        "$IMAGE_NAME" \
        bash -c '
            echo "=== GPU Check ==="
            nvidia-smi -L || echo "WARNING: nvidia-smi not available (expected in container without full CUDA)"
            echo ""
            echo "=== Running Installer ==="
            bash /mnt/install.sh
            echo ""
            echo "=== Verifying Installation ==="
            ls -la ~/stt-service/ || echo "Install dir not found"
            echo ""
            echo "=== Testing Uninstall ==="
            bash /mnt/install.sh --uninstall
        '
}

clean() {
    info "Cleaning up sandbox..."

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm -f "$CONTAINER_NAME"
        info "Removed container: $CONTAINER_NAME"
    fi

    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        docker rmi "$IMAGE_NAME"
        info "Removed image: $IMAGE_NAME"
    fi

    info "Cleanup complete"
}

# Main
case "${1:-}" in
    -h|--help)
        show_help
        ;;
    --auto)
        run_auto
        ;;
    --clean)
        clean
        ;;
    "")
        run_interactive
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run with --help for usage"
        exit 1
        ;;
esac
