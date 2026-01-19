# STT Model Options for GB10 (Grace Blackwell)

## Session Summary (2026-01-11)

Research findings for high-quality real-time speech-to-text on NVIDIA GB10.

## GB10 Hardware Profile

- **CPU**: ARM64 Grace (20 cores: 10 Cortex-X925 + 10 Cortex-A725)
- **GPU**: Blackwell (compute capability 12.1 / sm_121)
- **Memory**: 128GB unified LPDDR5X (273 GB/s bandwidth)
- **CUDA**: Requires Toolkit 13.0 for native support, or 12.8+ with PTX JIT

## Top Model Recommendations

| Model | WER | RTFx | VRAM | Best For |
|-------|-----|------|------|----------|
| **Parakeet TDT 0.6B v3** | ~6% | >2000x | ~3GB | Speed + accuracy balance |
| **Canary Qwen 2.5B** | 5.63% | 418x | ~8GB | Best accuracy, 25 languages |
| **Nemotron Speech ASR 0.6B** | <8% | - | ~3GB | Ultra-low latency (182ms) |
| **Distil-Whisper** | ~15% | ~300x | ~5GB | English-only, efficient |
| **Whisper Large V3 Turbo** | ~7.75% | ~180x | ~6GB | 100+ languages |
| **Moonshine Base** | ~15% | ~500x | <1GB | Edge/embedded |

## Implementation Paths

### Path A: NeMo + Parakeet (Recommended) - SELECTED

Native NVIDIA optimization, streaming-capable, top accuracy.

```bash
pip install nemo_toolkit['asr']
python -c "from nemo.collections.asr.models import ASRModel; \
  ASRModel.from_pretrained('nvidia/parakeet-tdt-0.6b-v2')"
```

### Path B: sherpa-onnx

Best ARM64 + CUDA support, WebSocket server included.

```bash
pip install sherpa-onnx
sherpa-onnx-online-websocket-server \
  --tokens=./tokens.txt \
  --encoder=./encoder.onnx \
  --decoder=./decoder.onnx
```

### Path C: whisper.cpp with CUDA

Simplest upgrade path from existing script.

```bash
cmake -B build -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="121" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/whisper-stream -m models/ggml-large-v3.bin --gpu 0
```

## Streaming Architecture Comparison

```
File-based (current):
  [rec] -> temp.wav -> [whisper-cli] -> text -> [wtype]
  Latency: ~1-2s after speaking

Server-based (recommended):
  [PTT script] -> WebSocket -> [NeMo/sherpa server] -> text
  Latency: ~180ms (Nemotron), <100ms (Parakeet chunks)
```

## Alternative Models Researched

### NVIDIA Models (NeMo Framework)
- **Parakeet TDT 0.6B v3**: #1 on HuggingFace ASR leaderboard, 25 EU languages
- **Canary 1B v2**: Encoder-decoder, translation support
- **Canary Qwen 2.5B**: Best WER (5.63%), uses Qwen decoder
- **Nemotron Speech ASR**: Purpose-built for voice agents, 182ms latency

### Whisper Variants
- **Whisper Large V3**: Original, 100+ languages, ~10GB VRAM
- **Whisper Large V3 Turbo**: 6x faster, 809M params, multilingual
- **Distil-Whisper**: 6x faster, English-only, ~5GB VRAM
- **Faster-Whisper**: CTranslate2 backend, 4x speed, INT8 support

### Other Open Source
- **Moonshine**: Ultra-efficient (27-62M params), edge-focused
- **IBM Granite Speech 3.3 8B**: Excellent noise resilience
- **wav2vec2/HuBERT**: Good for clean speech, poor noise handling
- **Vosk**: Lightweight, zero-latency streaming, lower accuracy

## Blackwell Build Notes

```bash
# GB10 uses sm_121 (compute capability 12.1)
# Requires CUDA Toolkit 13.0 for native, or 12.8+ with PTX JIT

cmake -DCMAKE_CUDA_ARCHITECTURES="121"

# For broad Blackwell compatibility:
cmake -DCMAKE_CUDA_ARCHITECTURES="100;101;120;121"
```

## Sources

- [NVIDIA Parakeet Blog](https://developer.nvidia.com/blog/pushing-the-boundaries-of-speech-recognition-with-nemo-parakeet-asr-models/)
- [NVIDIA Canary Blog](https://developer.nvidia.com/blog/new-standard-for-speech-recognition-and-translation-from-the-nvidia-nemo-canary-model/)
- [HuggingFace Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard)
- [whisper.cpp GitHub](https://github.com/ggml-org/whisper.cpp)
- [sherpa-onnx GitHub](https://github.com/k2-fsa/sherpa-onnx)
- [Faster-Whisper GitHub](https://github.com/SYSTRAN/faster-whisper)
- [NVIDIA DGX Spark Performance Blog](https://developer.nvidia.com/blog/how-nvidia-dgx-sparks-performance-enables-intensive-ai-tasks/)
