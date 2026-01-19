#!/usr/bin/env bash
# Wrapper script to run stt-server with correct CUDA library path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find CUDA libraries (onnxruntime-gpu needs CUDA 12 compat libs)
find_cuda_lib() {
    local paths=(
        "/usr/local/cuda/targets/sbsa-linux/lib"
        "/usr/local/cuda-13.0/targets/sbsa-linux/lib"
        "/usr/local/cuda-12.6/targets/sbsa-linux/lib"
        "/usr/local/cuda/lib64"
        "/usr/lib/aarch64-linux-gnu"
    )
    for p in "${paths[@]}"; do
        if [[ -f "$p/libcublas.so.12" ]] || [[ -f "$p/libcublas.so" ]]; then
            echo "$p"
            return 0
        fi
    done
    # Fallback search
    local found
    found=$(find /usr -name "libcublas.so.12*" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        dirname "$found"
        return 0
    fi
}

CUDA_LIB=$(find_cuda_lib)
if [[ -n "$CUDA_LIB" ]]; then
    export LD_LIBRARY_PATH="$CUDA_LIB:${LD_LIBRARY_PATH:-}"
fi

cd "$PROJECT_DIR"
exec uv run stt-server "$@"

