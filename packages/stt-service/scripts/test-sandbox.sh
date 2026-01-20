#!/usr/bin/env bash
#
# Test STT Service installer in a disposable Docker sandbox
# GPU passthrough enabled - requires nvidia-container-toolkit
#
# Usage:
#   ./test-sandbox.sh              # Interactive shell in fresh Ubuntu
#   ./test-sandbox.sh --attach     # Attach new shell to running container
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
The container is disposable - delete it anytime with --clean.

USAGE:
    ./test-sandbox.sh              Interactive shell
    ./test-sandbox.sh --attach     Attach new shell to running container
    ./test-sandbox.sh --clean      Remove container and image

TESTING THE CURL INSTALLER:
    # Start sandbox
    ./test-sandbox.sh

    # Inside container, run the one-liner:
    curl -fsSL https://cdn.jsdelivr.net/gh/AeyeOps/ai-essentials@main/packages/stt-service/install.sh | bash

    # Test the service
    cd ~/stt-service
    ./scripts/stt-server.sh &
    ./scripts/stt-client.sh --ptt

    # In another terminal (optional)
    ./test-sandbox.sh --attach

NOTES:
    - GPU passed through via --gpus all
    - Audio passed through via PulseAudio
    - PTT uses spacebar in terminal mode (hold to record, release to transcribe)
EOF
}

build_image() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        info "Using existing test image: $IMAGE_NAME"
        return
    fi

    local uid=$(id -u)
    local gid=$(id -g)

    info "Building test image (CUDA 13 Ubuntu 24.04 with runtime)..."
    docker build -t "$IMAGE_NAME" --build-arg UID="$uid" --build-arg GID="$gid" - << 'DOCKERFILE'
FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ARG UID=1000
ARG GID=1000

# Minimal packages - CUDA runtime provided by base image
# Installer will add CUDA 12 compat libs for onnxruntime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    pulseaudio-utils \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# Create test user with matching UID/GID for PulseAudio socket access
# Remove any existing user/group with target IDs (CUDA images often have ubuntu:1000)
RUN (u=$(getent passwd $UID | cut -d: -f1) && userdel -r "$u" 2>/dev/null) || true && \
    (g=$(getent group $GID | cut -d: -f1) && groupdel "$g" 2>/dev/null) || true && \
    groupadd -g $GID testuser && \
    useradd -m -u $UID -g $GID -s /bin/bash -G audio testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# PulseAudio client config - connect to host's server, disable shared memory
RUN mkdir -p /home/testuser/.config/pulse && \
    echo "default-server = unix:/run/user/$UID/pulse/native" > /home/testuser/.config/pulse/client.conf && \
    echo "autospawn = no" >> /home/testuser/.config/pulse/client.conf && \
    echo "enable-shm = false" >> /home/testuser/.config/pulse/client.conf && \
    chown -R $UID:$GID /home/testuser/.config

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
    echo ""
    warn "Run inside container:"
    echo "  curl -fsSL https://cdn.jsdelivr.net/gh/AeyeOps/ai-essentials@main/packages/stt-service/install.sh | bash"
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
