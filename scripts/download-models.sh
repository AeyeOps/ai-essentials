#!/usr/bin/env bash
# download-models.sh - Pre-download ONNX models for STT service
#
# This script is OPTIONAL. onnx-asr will automatically download models on first use.
# Use this script to pre-cache models or for offline deployment.
#
# Models are downloaded to packages/stt-service/models/<model-name>/
# The transcriber will detect and use local models automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/../packages/stt-service/models"

# Model configurations: local-name -> huggingface-repo
# Local name should match onnx-asr model name (without 'nemo-' prefix)
declare -A MODELS=(
    ["parakeet-tdt-0.6b-v2"]="onnx-community/parakeet-tdt-0.6b-v2-ONNX"
    ["parakeet-tdt-0.6b-v3"]="onnx-community/parakeet-tdt-0.6b-v3-ONNX"
)

usage() {
    echo "Usage: $0 [model-name]"
    echo ""
    echo "Pre-download ONNX models for offline use or faster startup."
    echo "NOTE: This is optional - onnx-asr downloads models automatically."
    echo ""
    echo "Available models:"
    for model in "${!MODELS[@]}"; do
        echo "  - $model"
    done
    echo ""
    echo "Default: parakeet-tdt-0.6b-v2 (English)"
    echo ""
    echo "Example:"
    echo "  $0                      # Download default model"
    echo "  $0 parakeet-tdt-0.6b-v3 # Download multilingual model"
}

download_model() {
    local model_name="$1"
    local repo="${MODELS[$model_name]:-}"
    local target_dir="${MODELS_DIR}/${model_name}"

    if [[ -z "$repo" ]]; then
        echo "Error: Unknown model '$model_name'"
        echo ""
        usage
        exit 1
    fi

    # Check if already downloaded
    if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
        echo "Model already exists at: ${target_dir}"
        echo "Delete the directory to re-download."
        exit 0
    fi

    echo "Downloading ${model_name} from ${repo}..."
    echo "Target directory: ${target_dir}"
    echo ""

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
    echo "The STT server will automatically use this local model."
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
