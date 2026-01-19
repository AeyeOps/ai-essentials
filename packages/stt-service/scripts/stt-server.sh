#!/usr/bin/env bash
# Wrapper script to run stt-server with correct CUDA 12 library path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# CUDA 12 compatibility for onnxruntime-gpu wheel on CUDA 13
export LD_LIBRARY_PATH="/usr/local/cuda-12.6/targets/sbsa-linux/lib:${LD_LIBRARY_PATH:-}"

cd "$PROJECT_DIR"
exec uv run stt-server "$@"

