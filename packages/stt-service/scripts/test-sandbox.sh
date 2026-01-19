#!/usr/bin/env bash
#
# Test STT Service installer in a disposable Docker sandbox
# GPU passthrough enabled - requires nvidia-container-toolkit
#
# Usage:
#   ./test-sandbox.sh              # Interactive shell in fresh Ubuntu
#   ./test-sandbox.sh --attach     # Attach new shell to running container
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

check_prerequisites() {
    # Check for nvidia-container-toolkit
    if ! docker info 2>/dev/null | grep -q "nvidia"; then
        warn "nvidia-container-toolkit may not be installed or configured"
        echo "  Install with: sudo apt install nvidia-container-toolkit"
        echo "  Then restart docker: sudo systemctl restart docker"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

show_help() {
    cat << 'EOF'
STT Service Test Sandbox

Creates a CUDA 13 Ubuntu 24.04 container with GPU access for testing the installer.
Base image provides CUDA runtime; installer adds CUDA 12 compat libs for onnxruntime.
The container is disposable - delete it anytime with --clean.

USAGE:
    ./test-sandbox.sh              Interactive shell (recommended for first test)
    ./test-sandbox.sh --auto       Install and start server, then attach to test audio
    ./test-sandbox.sh --attach     Attach new shell to running container
    ./test-sandbox.sh --clean      Remove container and image

QUICK START (--auto):
    # Terminal 1: Install and start server
    ./test-sandbox.sh --auto

    # Terminal 2: Attach and test audio
    ./test-sandbox.sh --attach
    cd ~/stt-service && ./scripts/stt-client.sh

MANUAL MODE (default):
    # Inside the container:
    bash /mnt/install.sh           # Run installer
    cd ~/stt-service
    ./scripts/stt-server.sh        # Start server

    # In another terminal:
    ./test-sandbox.sh --attach
    cd ~/stt-service && ./scripts/stt-client.sh

NOTES:
    - Container mounts this project at /mnt (read-only)
    - Install goes to ~/stt-service inside container
    - GPU is passed through via --gpus all
    - Audio is passed through via PulseAudio and ALSA
    - After updating this script, run --clean to rebuild the image
EOF
}

build_image() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        info "Using existing test image: $IMAGE_NAME"
        return
    fi

    info "Building test image (CUDA 13 Ubuntu 24.04 with runtime)..."
    docker build -t "$IMAGE_NAME" - << 'DOCKERFILE'
FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# Minimal packages - CUDA runtime provided by base image
# Installer will add CUDA 12 compat libs for onnxruntime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    pulseaudio-utils \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# Create test user (non-root, with sudo, in audio group)
RUN useradd -m -s /bin/bash -G audio testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER testuser
WORKDIR /home/testuser

CMD ["/bin/bash"]
DOCKERFILE
    info "Image built: $IMAGE_NAME"
}

run_interactive() {
    check_prerequisites
    build_image

    info "Starting interactive sandbox..."
    info "Project mounted at /mnt (read-only)"
    echo ""
    warn "Test commands to run inside:"
    echo "  bash /mnt/install.sh           # Interactive install"
    echo "  bash /mnt/install.sh --help    # Show help"
    echo "  nvidia-smi                     # Verify GPU"
    echo ""

    local uid=$(id -u)
    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        --gpus all \
        -v "$PROJECT_DIR:/mnt:ro" \
        -e "HOME=/home/testuser" \
        --device /dev/snd \
        --group-add audio \
        -v "/run/user/$uid/pulse:/run/user/$uid/pulse" \
        -e "PULSE_SERVER=unix:/run/user/$uid/pulse/native" \
        "$IMAGE_NAME" \
        bash
}

attach_to_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "No running container found: $CONTAINER_NAME"
        info "Start one first with: ./test-sandbox.sh"
        exit 1
    fi

    info "Attaching to running container..."
    local uid=$(id -u)
    docker exec -it \
        -e "PULSE_SERVER=unix:/run/user/$uid/pulse/native" \
        "$CONTAINER_NAME" bash
}

run_auto() {
    check_prerequisites
    build_image

    info "Installing and starting server (non-interactive)..."
    echo ""

    local uid=$(id -u)

    # Remove any existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Start container in background with install + server
    docker run -d \
        --name "$CONTAINER_NAME" \
        --gpus all \
        -v "$PROJECT_DIR:/mnt:ro" \
        -e "HOME=/home/testuser" \
        -e "STT_NONINTERACTIVE=1" \
        --device /dev/snd \
        --group-add audio \
        -v "/run/user/$uid/pulse:/run/user/$uid/pulse" \
        -e "PULSE_SERVER=unix:/run/user/$uid/pulse/native" \
        "$IMAGE_NAME" \
        bash -c '
            # Install
            bash /mnt/install.sh

            # Source PATH for uv
            export PATH="$HOME/.local/bin:$PATH"

            # Start server (foreground to keep container alive)
            cd ~/stt-service
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo "  Server starting... attach with: ./test-sandbox.sh --attach"
            echo "════════════════════════════════════════════════════════════"
            echo ""
            ./scripts/stt-server.sh
        '

    info "Container started in background"
    info "Tailing logs (Ctrl+C to stop watching, container keeps running)..."
    echo ""
    warn "To test audio, open another terminal and run:"
    echo "  ./test-sandbox.sh --attach"
    echo "  cd ~/stt-service && ./scripts/stt-client.sh"
    echo ""

    # Follow logs until user hits Ctrl+C
    docker logs -f "$CONTAINER_NAME" || true

    echo ""
    info "Container still running. Attach with: ./test-sandbox.sh --attach"
    info "Stop with: ./test-sandbox.sh --clean"
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
    --attach)
        attach_to_container
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
