# Speech-to-Text with Push-to-Talk Setup

## Session Summary (2026-01-11)

Setting up a Wispr Flow-like STT experience on Linux ARM64 (GB10) using whisper.cpp.

## Requirements

- **Platform**: NVIDIA GB10 ARM (Grace Blackwell)
- **Hotkey**: Ctrl+Super (push-to-talk)
- **Backend**: whisper.cpp (local, offline)
- **Integration**: Type directly into focused application
- **Display Server**: Check with `echo $XDG_SESSION_TYPE` (Wayland or X11)

## Why whisper.cpp?

- Native ARM64/aarch64 support with NEON SIMD acceleration
- Official Docker images for `linux/arm64`
- Pre-built Python wheels for aarch64
- Can leverage CUDA on Blackwell GPU for larger models
- 95-99% accuracy (vs VOSK's 85-95%)

## Alternatives Researched

| Tool | Notes |
|------|-------|
| Wispr Flow | No Linux support at all |
| Voxtype | x64 only, would need ARM build |
| Handy | x64 binaries only |
| Open-Whispr | Electron, x64 focused |
| BlahST | Shell scripts, whisper.cpp backend, should work on ARM |
| nerd-dictation | Uses VOSK (lower accuracy), not Whisper |
| Talon | Proprietary, no Wayland support |

## Installation Plan

### 1. Build whisper.cpp
```bash
cd /opt/dev/aeo/ai-essentials/scripts
git clone https://github.com/ggml-org/whisper.cpp
cd whisper.cpp
make -j$(nproc)

# Download model (base.en is good balance of speed/accuracy)
./models/download-ggml-model.sh base.en
```

### 2. Install dependencies
```bash
# For Wayland
sudo apt install wtype wl-clipboard

# For X11
sudo apt install xdotool xclip

# Audio capture
sudo apt install sox libsox-fmt-all
```

### 3. Create PTT script
See: `scripts/whisper-ptt.sh`

### 4. Configure hotkey (Ctrl+Super)
- GNOME: Settings > Keyboard > Custom Shortcuts
- KDE: System Settings > Shortcuts
- Hyprland/Sway: Add bind in config

## Models

| Model | Size | Speed (ARM) | Accuracy |
|-------|------|-------------|----------|
| tiny.en | 39MB | Fastest | Good |
| base.en | 142MB | Fast | Better |
| small.en | 466MB | Medium | Great |
| medium.en | 1.5GB | Slower | Excellent |
| large-v3 | 3GB | Slow (use GPU) | Best |

## Next Steps

- [ ] Clone and build whisper.cpp
- [ ] Test basic transcription
- [ ] Create PTT wrapper script
- [ ] Configure global hotkey
- [ ] Test end-to-end flow
