#!/usr/bin/env bash
# download-models.sh - Download ONNX models for STT service
#
# Downloads Parakeet TDT 0.6B v2 ONNX model from HuggingFace.
# Requires: huggingface-cli (pip install huggingface-hub)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/../packages/stt-service/models"

# Model configurations
declare -A MODELS=(
    ["parakeet-tdt-0.6b-v2"]="onnx-community/parakeet-tdt-0.6b-v2-ONNX"
)

usage() {
    echo "Usage: $0 [model-name]"
    echo ""
    echo "Available models:"
    for model in "${!MODELS[@]}"; do
        echo "  - $model"
    done
    echo ""
    echo "If no model specified, downloads parakeet-tdt-0.6b-v2 (default)"
}

download_model() {
    local model_name="$1"
    local repo="${MODELS[$model_name]}"
    local target_dir="${MODELS_DIR}/${model_name}"

    if [[ -z "$repo" ]]; then
        echo "Error: Unknown model '$model_name'"
        usage
        exit 1
    fi

    echo "Downloading ${model_name} from ${repo}..."
    echo "Target directory: ${target_dir}"

    # Check for huggingface-cli
    if ! command -v huggingface-cli &> /dev/null; then
        echo "Error: huggingface-cli not found."
        echo "Install with: pip install huggingface-hub"
        exit 1
    fi

    # Create models directory if needed
    mkdir -p "${MODELS_DIR}"

    # Download model
    huggingface-cli download "${repo}" \
        --local-dir "${target_dir}" \
        --local-dir-use-symlinks False

    echo ""
    echo "Model downloaded successfully to: ${target_dir}"
    echo ""
    echo "Model files:"
    ls -lh "${target_dir}"
}

main() {
    local model="${1:-parakeet-tdt-0.6b-v2}"

    if [[ "$model" == "-h" || "$model" == "--help" ]]; then
        usage
        exit 0
    fi

    download_model "$model"
}

main "$@"
