#!/usr/bin/env bash
#
# AEO Push-to-Talk Installer
#
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash
#
# Or with wget:
#   wget -O- https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash
#
# Options (via environment variables):
#   STT_NONINTERACTIVE=1  - No prompts, use defaults
#   STT_INSTALL_DIR=path  - Custom install location (default: ~/stt-service)
#   STT_SKIP_MODEL=1      - Don't download the speech model
#   STT_WITH_SERVICE=1    - Install systemd service
#
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════

INSTALL_DIR="${STT_INSTALL_DIR:-$HOME/stt-service}"
NONINTERACTIVE="${STT_NONINTERACTIVE:-0}"
SKIP_MODEL="${STT_SKIP_MODEL:-0}"
WITH_SERVICE="${STT_WITH_SERVICE:-0}"

# GitHub download URL (tarball, no git required)
REPO_TARBALL="https://github.com/AeyeOps/ai-essentials/archive/refs/heads/main.tar.gz"
PACKAGE_SUBDIR="ai-essentials-main/packages/stt-service"

# ARM64 onnxruntime wheel (not on PyPI)
ONNX_WHEEL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.24.0-cp312-cp312-linux_aarch64.whl"

# CUDA library paths to search (in order of preference)
# GB10 with full CUDA toolkit uses /usr/local/cuda-*/targets/sbsa-linux/lib
# apt-installed packages use /usr/lib/aarch64-linux-gnu
CUDA_LIB=""  # Will be detected dynamically

# Minimum disk space required (GB)
MIN_DISK_GB=3

# Track if CUDA upgrade is recommended
CUDA_NEEDS_UPGRADE=0

# Track if apt-get update has been run this session
APT_UPDATED=0

# ═══════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════

# Colors (disabled if not a terminal)
setup_colors() {
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' NC=''
    fi
}

info()    { echo -e "${BLUE}│${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}!${NC} $1"; }
error()   { echo -e "${RED}✗ ERROR:${NC} $1" >&2; }
die()     { error "$1"; exit 1; }
step()    { echo -e "\n${BOLD}$1${NC}"; }

# Read single character with tty fallback for piped execution (curl | bash)
# Sets REPLY variable, echoes newline after input
# All prompts go to /dev/tty to avoid capture in command substitution
read_char() {
    local prompt="$1"
    if [[ -t 0 ]]; then
        read -p "$prompt" -n 1 -r
        echo >&2
    elif [[ -e /dev/tty ]]; then
        printf '%s' "$prompt" > /dev/tty
        read -n 1 -r < /dev/tty
        echo > /dev/tty
    else
        REPLY=""
    fi
}

# Prompt with default (respects NONINTERACTIVE)
ask() {
    local prompt="$1"
    local default="$2"

    if [[ "$NONINTERACTIVE" == "1" ]]; then
        echo "$default"
        return
    fi

    local yn_hint=""
    if [[ "$default" == "y" ]]; then
        yn_hint="[Y/n]"
    elif [[ "$default" == "n" ]]; then
        yn_hint="[y/N]"
    fi

    read_char "$prompt $yn_hint "

    if [[ -z "$REPLY" ]]; then
        echo "$default"
    elif [[ "$REPLY" =~ ^[Yy]$ ]]; then
        echo "y"
    else
        echo "n"
    fi
}

# Check if command exists
has_cmd() {
    command -v "$1" &> /dev/null
}

# Find CUDA 12 library directory (required by onnxruntime-gpu)
# GB10 has CUDA 13 as primary, but onnxruntime needs CUDA 12 compat libs
find_cuda_lib() {
    # Prioritize CUDA 12 paths - onnxruntime-gpu needs libcublas.so.12
    local search_paths=(
        "/usr/local/cuda-12.6/targets/sbsa-linux/lib"  # GB10 CUDA 12 compat
        "/usr/local/cuda-12/targets/sbsa-linux/lib"
        "/usr/lib/aarch64-linux-gnu"                    # apt-installed libs
        "/usr/local/cuda/targets/sbsa-linux/lib"        # Only if has .so.12
        "/usr/local/cuda-13.0/targets/sbsa-linux/lib"   # Only if has .so.12
        "/usr/local/cuda/lib64"
    )
    for p in "${search_paths[@]}"; do
        # MUST have libcublas.so.12 specifically (not just .so which could be CUDA 13)
        if [[ -f "$p/libcublas.so.12" ]]; then
            echo "$p"
            return 0
        fi
    done
    # Fallback: search for libcublas.so.12
    local found
    found=$(find /usr -name "libcublas.so.12" -type f -o -name "libcublas.so.12" -type l 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        dirname "$found"
        return 0
    fi
    # Return empty string (not an error - just not found yet)
    echo ""
    return 0
}

# Download helper (uses curl or wget)
download() {
    local url="$1"
    local dest="$2"

    if has_cmd curl; then
        curl -fsSL "$url" -o "$dest"
    elif has_cmd wget; then
        wget "$url" -O "$dest"
    else
        die "Neither curl nor wget found. Install one with: sudo apt install curl"
    fi
}

# Download and extract tarball
download_extract() {
    local url="$1"
    local dest="$2"

    if has_cmd curl; then
        curl -fsSL "$url" | tar -xz -C "$dest"
    elif has_cmd wget; then
        wget -O- "$url" | tar -xz -C "$dest"
    else
        die "Neither curl nor wget found. Install one with: sudo apt install curl"
    fi
}

# Ensure apt-get update has been run
ensure_apt_updated() {
    if [[ "$APT_UPDATED" != "1" ]]; then
        sudo apt-get update
        APT_UPDATED=1
    fi
}

# Install autostart entry for AEO Push-to-Talk daemon
install_autostart() {
    info "Installing desktop dependencies..."
    cd "$INSTALL_DIR"
    uv sync --extra desktop

    # Reinstall GPU wheel (uv sync removes packages not in lockfile)
    info "Ensuring GPU runtime..."
    uv pip install "$ONNX_WHEEL"

    # Create desktop entry from template (both autostart and applications)
    info "Creating desktop entries..."
    mkdir -p "$HOME/.config/autostart" "$HOME/.local/share/applications"
    if [[ ! -f "$INSTALL_DIR/scripts/aeo-ptt.desktop.template" ]]; then
        warn "Template not found: $INSTALL_DIR/scripts/aeo-ptt.desktop.template"
        return 1
    fi
    sed "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        "$INSTALL_DIR/scripts/aeo-ptt.desktop.template" \
        > "$HOME/.config/autostart/aeo-ptt.desktop"
    cp "$HOME/.config/autostart/aeo-ptt.desktop" "$HOME/.local/share/applications/"

    # Verify files were created
    if [[ ! -f "$HOME/.config/autostart/aeo-ptt.desktop" ]]; then
        warn "Failed to create autostart entry"
        return 1
    fi
    success "Desktop entries created"

    # Ensure xdotool is installed (for typing text at cursor)
    if ! has_cmd xdotool; then
        info "Installing xdotool..."
        ensure_apt_updated
        sudo apt-get install -y xdotool
    fi

    # Install PyGObject for tray support on GNOME
    # The venv uses system-site-packages to access these
    if ! dpkg -s python3-gi &> /dev/null; then
        info "Installing tray dependencies (PyGObject)..."
        ensure_apt_updated
        sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-ayatanaappindicator3-0.1
    fi

    success "Auto-start enabled"
    info "AEO Push-to-Talk will start automatically at login"
}

# Get available disk space in GB
disk_space_gb() {
    df -BG "$HOME" | awk 'NR==2 {print int($4)}'
}

# Check if model is already cached (huggingface_hub cache)
model_cached() {
    local hf_cache="${HF_HOME:-$HOME/.cache/huggingface}/hub"
    # Model is from istupakov (ONNX conversion of NVIDIA Parakeet)
    ls -d "$hf_cache"/models--istupakov--parakeet* &>/dev/null
}

# Check if systemd service exists
service_exists() {
    [[ -f /etc/systemd/system/stt-service.service ]]
}

# ═══════════════════════════════════════════════════════════════════
# Pre-flight checks
# ═══════════════════════════════════════════════════════════════════

preflight_checks() {
    local issues=0

    step "Checking system requirements..."

    # Architecture
    if [[ "$(uname -m)" == "aarch64" ]]; then
        success "Architecture: ARM64"
    else
        error "This installer requires ARM64 (GB10/DGX Spark)"
        info "Detected: $(uname -m)"
        ((issues++))
    fi

    # Running as root (warn only)
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        warn "Running as root is not recommended"
        info "Consider running as a regular user"
    fi

    # NVIDIA driver and CUDA version
    if has_cmd nvidia-smi; then
        if nvidia-smi -L 2>/dev/null | grep -q GPU; then
            local gpu_name
            gpu_name=$(nvidia-smi -L | head -1 | sed 's/GPU 0: //' | cut -d'(' -f1)
            success "GPU: $gpu_name"

            # Check CUDA version (using sed for portability - grep -oP requires PCRE)
            local cuda_version
            cuda_version=$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p' | head -1)
            [[ -z "$cuda_version" ]] && cuda_version="unknown"
            if [[ "$cuda_version" != "unknown" ]]; then
                local cuda_major="${cuda_version%%.*}"
                success "CUDA Version: $cuda_version"

                # Warn if CUDA is older than 12
                if [[ "$cuda_major" -lt 12 ]]; then
                    warn "CUDA $cuda_version is older than recommended (12.0+)"
                    info "Consider upgrading CUDA for best performance"
                    CUDA_NEEDS_UPGRADE=1
                elif [[ "$cuda_major" -lt 13 ]]; then
                    info "CUDA 13 is available for GB10 - upgrade optional"
                fi
            else
                warn "Could not detect CUDA version"
            fi
        else
            error "nvidia-smi found but no GPU detected"
            info "Check that your GPU is properly connected"
            ((issues++))
        fi
    else
        error "NVIDIA driver not found"
        info "Install with: sudo apt install nvidia-driver-570"
        info "Then reboot and run this installer again"
        ((issues++))
    fi

    # Disk space
    local space
    space=$(disk_space_gb)
    if [[ "$space" -ge "$MIN_DISK_GB" ]]; then
        success "Disk space: ${space}GB available"
    else
        error "Insufficient disk space: ${space}GB available, need ${MIN_DISK_GB}GB"
        ((issues++))
    fi

    # Internet connectivity
    if has_cmd curl; then
        if curl -fsS --connect-timeout 5 "https://github.com" > /dev/null 2>&1; then
            success "Internet: Connected"
        else
            error "Cannot reach github.com"
            info "Check your internet connection"
            ((issues++))
        fi
    elif has_cmd wget; then
        if wget -q --spider --timeout=5 "https://github.com" 2>/dev/null; then
            success "Internet: Connected"
        else
            error "Cannot reach github.com"
            ((issues++))
        fi
    fi

    # CUDA libraries (informational)
    CUDA_LIB=$(find_cuda_lib)
    if [[ -n "$CUDA_LIB" ]]; then
        success "CUDA libraries: Found at $CUDA_LIB"
    else
        warn "CUDA libraries not found"
        info "Will attempt to install via apt"
    fi

    if [[ "$issues" -gt 0 ]]; then
        echo ""
        die "Please fix the above issues and run the installer again"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Detect existing installation
# ═══════════════════════════════════════════════════════════════════

detect_existing() {
    step "Checking for existing installation..."

    local found_install=0
    local found_model=0
    local found_service=0

    # Check install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/pyproject.toml" ]]; then
            success "Existing installation found: $INSTALL_DIR"
            found_install=1
        else
            warn "Directory exists but appears incomplete: $INSTALL_DIR"
        fi
    else
        info "Fresh installation to: $INSTALL_DIR"
    fi

    # Check for cached model
    if model_cached; then
        success "Speech model already downloaded"
        found_model=1
        SKIP_MODEL=1
    fi

    # Check for systemd service
    if service_exists; then
        success "Systemd service already installed"
        found_service=1
    fi

    # If existing install found, ask what to do
    if [[ "$found_install" -eq 1 ]]; then
        echo ""
        info "What would you like to do?"
        info "  1) Update - Pull latest changes"
        info "  2) Reinstall - Clean install"
        info "  3) Cancel"

        if [[ "$NONINTERACTIVE" == "1" ]]; then
            info "Non-interactive mode: Updating..."
            INSTALL_MODE="update"
        else
            read_char "Choice [1]: "
            case "${REPLY:-1}" in
                2) INSTALL_MODE="reinstall" ;;
                3) echo "Cancelled."; exit 0 ;;
                *) INSTALL_MODE="update" ;;
            esac
        fi
    else
        INSTALL_MODE="fresh"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Install system dependencies
# ═══════════════════════════════════════════════════════════════════

# Check if NVIDIA CUDA repo is configured
cuda_repo_configured() {
    [[ -f /etc/apt/sources.list.d/cuda-ubuntu2404-sbsa.list ]] || \
    [[ -f /etc/apt/sources.list.d/cuda*.list ]] || \
    grep -rq "developer.download.nvidia.com/compute/cuda" /etc/apt/sources.list.d/ 2>/dev/null
}

# Check if CUDA toolkit is installed
cuda_installed() {
    # Check multiple indicators of CUDA installation
    # 1. nvcc compiler available
    # 2. /usr/local/cuda symlink exists (created by CUDA installer)
    # 3. Any /usr/local/cuda-* directory exists
    # 4. CUDA toolkit package installed via apt
    has_cmd nvcc || \
    [[ -d /usr/local/cuda ]] || \
    ls -d /usr/local/cuda-* &>/dev/null || \
    dpkg -l 2>/dev/null | grep -qE "cuda-toolkit-1[23]|cuda-runtime-1[23]"
}

# Set up NVIDIA CUDA repository
setup_cuda_repo() {
    info "Setting up NVIDIA CUDA repository..."
    info "This requires sudo access..."

    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/cuda-keyring_1.1-1_all.deb"
    local keyring_file="/tmp/cuda-keyring.deb"

    # Download keyring package
    if has_cmd curl; then
        curl -fsSL "$keyring_url" -o "$keyring_file" || die "Failed to download CUDA keyring"
    elif has_cmd wget; then
        wget -q "$keyring_url" -O "$keyring_file" || die "Failed to download CUDA keyring"
    else
        die "Neither curl nor wget available"
    fi

    # Install keyring and update
    sudo dpkg -i "$keyring_file" || die "Failed to install CUDA keyring"
    rm -f "$keyring_file"
    sudo apt-get update
    APT_UPDATED=1

    success "NVIDIA CUDA repository configured"
}

# Install CUDA toolkit
install_cuda_toolkit() {
    info "Installing CUDA toolkit..."
    info "This may take several minutes..."

    # Install CUDA 13.0 toolkit (pinned to match GB10)
    sudo apt-get install -y cuda-toolkit-13-0
    success "CUDA toolkit installed"

    # Add CUDA to PATH for this session
    export PATH="/usr/local/cuda/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
}

install_system_deps() {
    step "Installing system dependencies..."

    local need_cuda_repo=0

    # First, check if CUDA toolkit is installed or needs upgrade
    if ! cuda_installed; then
        warn "CUDA toolkit not detected"
        need_cuda_repo=1

        # Setup repo first if needed
        if ! cuda_repo_configured; then
            if [[ $(ask "Set up NVIDIA CUDA repository?" "y") == "y" ]]; then
                setup_cuda_repo
            else
                die "CUDA repository required for installation"
            fi
        fi

        if [[ $(ask "Install CUDA 13 toolkit?" "y") == "y" ]]; then
            install_cuda_toolkit
        else
            warn "Skipping CUDA toolkit - GPU acceleration may not work"
        fi
    elif [[ "$CUDA_NEEDS_UPGRADE" == "1" ]]; then
        warn "CUDA upgrade recommended for optimal performance"

        # Setup repo first if needed
        if ! cuda_repo_configured; then
            if [[ $(ask "Set up NVIDIA CUDA repository?" "y") == "y" ]]; then
                setup_cuda_repo
            fi
        fi

        if [[ $(ask "Upgrade to CUDA 13?" "n") == "y" ]]; then
            install_cuda_toolkit
            info "Note: A reboot may be required after CUDA upgrade"
        else
            info "Skipping CUDA upgrade - using existing version"
        fi
    else
        success "CUDA toolkit: Already installed"
    fi

    # Packages we need
    local packages=()

    # Check each one
    if ! dpkg -s libportaudio2 &> /dev/null; then
        packages+=(libportaudio2)
    else
        success "libportaudio2: Already installed"
    fi

    # CUDA 12 compatibility libs (onnxruntime-gpu built for CUDA 12)
    if ! dpkg -s libcudnn9-cuda-12 &> /dev/null; then
        packages+=(libcudnn9-cuda-12)
        need_cuda_repo=1
    else
        success "libcudnn9-cuda-12: Already installed"
    fi

    # onnxruntime-gpu needs CUDA 12 cublas specifically (not CUDA 13)
    if ! ldconfig -p | grep -q 'libcublas.so.12'; then
        packages+=(libcublas-12-6)
        need_cuda_repo=1
    else
        success "libcublas (CUDA 12): Already installed"
    fi

    # Check if we need CUDA repo setup for compat libs
    if [[ "$need_cuda_repo" == "1" ]] && ! cuda_repo_configured; then
        warn "NVIDIA CUDA repository not configured"
        info "Required for: libcudnn9-cuda-12, libcublas-12-6"

        if [[ $(ask "Set up NVIDIA CUDA repository?" "y") == "y" ]]; then
            setup_cuda_repo
        else
            warn "Skipping CUDA repo setup - CUDA packages may fail to install"
            # Remove CUDA packages from list
            packages=("${packages[@]/libcudnn9-cuda-12}")
            packages=("${packages[@]/libcublas-12-6}")
            # Clean empty elements
            local cleaned=()
            for pkg in "${packages[@]}"; do
                [[ -n "$pkg" ]] && cleaned+=("$pkg")
            done
            packages=("${cleaned[@]}")
        fi
    fi

    # Install missing packages
    if [[ ${#packages[@]} -gt 0 ]]; then
        info "Installing: ${packages[*]}"
        info "This requires sudo access..."

        # Only run apt-get update if not already done this session
        if [[ "$APT_UPDATED" != "1" ]]; then
            sudo apt-get update
            APT_UPDATED=1
        fi
        sudo apt-get install -y "${packages[@]}"
        success "System dependencies installed"
    else
        success "All system dependencies already installed"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Install uv
# ═══════════════════════════════════════════════════════════════════

install_uv() {
    step "Setting up Python package manager..."

    if has_cmd uv; then
        local uv_version
        uv_version=$(uv --version 2>/dev/null | head -1)
        success "uv already installed: $uv_version"
    else
        info "Installing uv..."

        if has_cmd curl; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
        else
            wget -O- https://astral.sh/uv/install.sh | sh
        fi

        # Add to PATH for this session
        export PATH="$HOME/.local/bin:$PATH"

        if has_cmd uv; then
            success "uv installed: $(uv --version | head -1)"
        else
            die "Failed to install uv"
        fi

        # Ensure PATH persists across sessions
        local shell_rc=""
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -f "$HOME/.profile" ]]; then
            shell_rc="$HOME/.profile"
        else
            shell_rc="$HOME/.bashrc"
            touch "$shell_rc"
        fi
        if ! grep -q '\.local/bin' "$shell_rc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
            info "Added ~/.local/bin to PATH in $(basename "$shell_rc")"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Download/update package
# ═══════════════════════════════════════════════════════════════════

download_package() {
    step "Downloading AEO Push-to-Talk..."

    # Always download from GitHub (curl installer path)
    # Local development should use git clone directly

    case "$INSTALL_MODE" in
        fresh|reinstall)
            # Clean install
            if [[ "$INSTALL_MODE" == "reinstall" ]] && [[ -d "$INSTALL_DIR" ]]; then
                info "Removing old installation..."
                rm -rf "$INSTALL_DIR"
            fi

            mkdir -p "$(dirname "$INSTALL_DIR")"

            # Download from GitHub
            info "Downloading from GitHub..."
            local tmp_dir
            tmp_dir=$(mktemp -d)

            download_extract "$REPO_TARBALL" "$tmp_dir"

            # Move just the stt-service package
            mv "$tmp_dir/$PACKAGE_SUBDIR" "$INSTALL_DIR"
            rm -rf "$tmp_dir"

            success "Downloaded to $INSTALL_DIR"
            ;;

        update)
            # Update existing installation
            # Preserve venv if it exists
            local venv_backup=""
            if [[ -d "$INSTALL_DIR/.venv" ]]; then
                venv_backup=$(mktemp -d)
                mv "$INSTALL_DIR/.venv" "$venv_backup/.venv"
            fi

            if has_cmd git && [[ -d "$INSTALL_DIR/.git" ]]; then
                info "Updating via git..."
                cd "$INSTALL_DIR"
                git pull
                success "Updated from git"
            else
                info "Re-downloading latest version..."
                local tmp_dir
                tmp_dir=$(mktemp -d)

                download_extract "$REPO_TARBALL" "$tmp_dir"

                rm -rf "$INSTALL_DIR"
                mv "$tmp_dir/$PACKAGE_SUBDIR" "$INSTALL_DIR"
                rm -rf "$tmp_dir"
                success "Updated from GitHub"
            fi

            # Restore venv
            if [[ -n "$venv_backup" ]] && [[ -d "$venv_backup/.venv" ]]; then
                mv "$venv_backup/.venv" "$INSTALL_DIR/.venv"
                rm -rf "$venv_backup"
            fi
            ;;
    esac

    cd "$INSTALL_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# Setup Python environment
# ═══════════════════════════════════════════════════════════════════

setup_python() {
    step "Setting up Python environment..."

    cd "$INSTALL_DIR"

    # Check if venv exists and is healthy
    if [[ -d ".venv" ]] && [[ -f ".venv/bin/python" ]]; then
        if .venv/bin/python --version &> /dev/null; then
            success "Python environment exists"
            info "Updating dependencies..."
            uv sync
        else
            warn "Python environment corrupted, recreating..."
            rm -rf .venv
            uv sync --python 3.12
        fi
    else
        info "Creating Python 3.12 environment..."
        uv sync --python 3.12
    fi

    success "Python dependencies installed"

    # Enable system-site-packages for PyGObject access (needed for tray on GNOME)
    # This allows the venv to access system-installed gi (gobject-introspection)
    if [[ -f ".venv/pyvenv.cfg" ]]; then
        if grep -q "include-system-site-packages = false" ".venv/pyvenv.cfg"; then
            sed -i 's/include-system-site-packages = false/include-system-site-packages = true/' ".venv/pyvenv.cfg"
            success "Enabled system-site-packages for tray support"
        fi
    fi

    # Install GPU runtime
    info "Installing GPU runtime..."
    uv pip install "$ONNX_WHEEL"
    success "GPU runtime installed"

    # Install evdev for global hotkey support (Ctrl+Super)
    # Requires build tools and kernel headers to compile evdev
    local evdev_deps=()
    if ! has_cmd cc; then
        evdev_deps+=(build-essential)
    fi
    if ! dpkg -s linux-libc-dev &> /dev/null; then
        evdev_deps+=(linux-libc-dev)
    fi
    if [[ ${#evdev_deps[@]} -gt 0 ]]; then
        info "Installing build dependencies for evdev: ${evdev_deps[*]}"
        ensure_apt_updated
        sudo apt-get install -y "${evdev_deps[@]}"
    fi
    info "Installing global hotkey support..."
    uv pip install "evdev>=1.7.0"
    success "Global hotkey support installed"
}

# ═══════════════════════════════════════════════════════════════════
# Verify GPU
# ═══════════════════════════════════════════════════════════════════

verify_gpu() {
    step "Verifying GPU acceleration..."

    cd "$INSTALL_DIR"

    # Find and set CUDA library path
    CUDA_LIB=$(find_cuda_lib)
    if [[ -n "$CUDA_LIB" ]]; then
        export LD_LIBRARY_PATH="$CUDA_LIB:${LD_LIBRARY_PATH:-}"
    fi

    local result
    if result=$(uv run python -c "
import onnxruntime as ort
providers = ort.get_available_providers()
if 'CUDAExecutionProvider' in providers:
    print('CUDA')
elif 'TensorrtExecutionProvider' in providers:
    print('TensorRT')
else:
    print('NONE')
    exit(1)
" 2>&1); then
        success "GPU acceleration: $result"
    else
        error "GPU verification failed"
        echo ""
        info "Diagnostics:"
        info "  CUDA lib path: $CUDA_LIB (exists: $(test -d "$CUDA_LIB" && echo yes || echo no))"
        info "  LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-not set}"
        echo ""
        info "Try:"
        info "  1. Ensure CUDA 12.6 is installed"
        info "  2. Reboot if you recently installed drivers"
        info "  3. Check: nvidia-smi"
        die "GPU setup failed"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Download model
# ═══════════════════════════════════════════════════════════════════

download_model() {
    step "Speech model setup..."

    if [[ "$SKIP_MODEL" == "1" ]]; then
        if model_cached; then
            success "Model already cached, skipping download"
        else
            warn "Skipping model download (will download on first use)"
        fi
        return
    fi

    # Check if model already exists
    if model_cached; then
        success "Model already downloaded"
        return
    fi

    # Check disk space again before large download
    local space
    space=$(disk_space_gb)
    if [[ "$space" -lt 2 ]]; then
        warn "Low disk space (${space}GB). Model is ~1GB."
        if [[ $(ask "Continue anyway?" "n") != "y" ]]; then
            warn "Skipping model download"
            return
        fi
    fi

    if [[ $(ask "Download speech model now? (~1GB)" "y") == "y" ]]; then
        info "Downloading model (this may take a few minutes)..."

        cd "$INSTALL_DIR"
        CUDA_LIB=$(find_cuda_lib)
        if [[ -n "$CUDA_LIB" ]]; then
            export LD_LIBRARY_PATH="$CUDA_LIB:${LD_LIBRARY_PATH:-}"
        fi

        if uv run python -c "
from stt_service.transcriber import Transcriber
t = Transcriber()
t.load()
print('Model loaded successfully')
" 2>&1; then
            success "Model downloaded and verified"
        else
            warn "Model download failed - will retry on first use"
        fi
    else
        info "Skipped. Model will download on first use."
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Setup systemd service
# ═══════════════════════════════════════════════════════════════════

setup_service() {
    step "System service setup..."

    # Detect container environment
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        info "Docker detected - systemd not available"
        return
    fi

    if ! has_cmd systemctl; then
        info "Systemd not available, skipping service setup"
        info "Run server: $INSTALL_DIR/scripts/stt-server.sh"
        info "Run client: $INSTALL_DIR/scripts/stt-client.sh"
        return
    fi

    if service_exists; then
        info "Service already installed"
        if [[ $(ask "Update service configuration?" "n") == "y" ]]; then
            : # Continue to install
        else
            success "Keeping existing service"
            return
        fi
    else
        # Default to no for service (more advanced feature)
        local default="n"
        [[ "$WITH_SERVICE" == "1" ]] && default="y"

        if [[ $(ask "Install as system service (auto-start on boot)?" "$default") != "y" ]]; then
            info "Skipped. Install later with: $INSTALL_DIR/scripts/install-systemd.sh"
            return
        fi
    fi

    info "Installing systemd service..."

    # Find CUDA libs for service environment
    CUDA_LIB=$(find_cuda_lib)

    # Generate service file
    cat > /tmp/stt-service.service << EOF
[Unit]
Description=AEO Push-to-Talk - GPU-accelerated speech-to-text
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$INSTALL_DIR
Environment="LD_LIBRARY_PATH=${CUDA_LIB:-/usr/lib/aarch64-linux-gnu}"
Environment="PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$HOME/.local/bin/uv run stt-server
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=stt-service

[Install]
WantedBy=multi-user.target
EOF

    sudo cp /tmp/stt-service.service /etc/systemd/system/
    sudo systemctl daemon-reload
    rm -f /tmp/stt-service.service

    success "Service installed"

    if [[ $(ask "Enable and start service now?" "n") == "y" ]]; then
        sudo systemctl enable --now stt-service
        sleep 2
        if systemctl is-active --quiet stt-service; then
            success "Service running"
        else
            warn "Service may have failed to start"
            info "Check: sudo systemctl status stt-service"
        fi
    else
        info "Start later with: sudo systemctl enable --now stt-service"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Completion
# ═══════════════════════════════════════════════════════════════════

show_completion() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✓ Installation complete!${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check if in Docker/container
    local in_container=0
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        in_container=1
    fi

    local needs_logout=0
    local has_global_hotkey=0

    # ─────────────────────────────────────────────────────────────────
    # Offer: Global hotkey setup (input group)
    # ─────────────────────────────────────────────────────────────────
    # Use id -nG to check /etc/group directly (not session groups)
    if [[ "$in_container" == "0" ]] && ! id -nG "$USER" | grep -q '\binput\b'; then
        echo -e "${BOLD}Global Hotkey Setup${NC}"
        echo -e "${DIM}Enable Ctrl+Super hotkey for push-to-talk (works in any app)${NC}"
        echo ""
        if [[ $(ask "Add yourself to input group for global hotkey?" "y") == "y" ]]; then
            if sudo usermod -a -G input "$USER"; then
                success "Added $USER to input group"
                needs_logout=1
                has_global_hotkey=1
            else
                warn "Failed to add to input group (sudo required)"
                echo -e "  ${DIM}Run manually: sudo usermod -a -G input \$USER${NC}"
            fi
        else
            info "Skipped. PTT will use terminal mode (spacebar)"
        fi
        echo ""
    else
        # Already in input group or container
        if [[ "$in_container" == "0" ]]; then
            has_global_hotkey=1
        fi
    fi

    # ─────────────────────────────────────────────────────────────────
    # Offer: Systemd service (auto-start server on boot)
    # ─────────────────────────────────────────────────────────────────
    if [[ "$in_container" == "0" ]] && has_cmd systemctl && ! service_exists; then
        echo -e "${BOLD}Auto-Start Server${NC}"
        echo -e "${DIM}Start STT server automatically on boot${NC}"
        echo ""
        if [[ $(ask "Install systemd service for auto-start?" "y") == "y" ]]; then
            if "$INSTALL_DIR/scripts/install-systemd.sh" --yes 2>/dev/null || \
               "$INSTALL_DIR/scripts/install-systemd.sh" 2>/dev/null; then
                success "Systemd service installed"
                # Start it now
                if sudo systemctl start stt-service 2>/dev/null; then
                    success "Server started"
                fi
            else
                warn "Failed to install service"
                echo -e "  ${DIM}Run manually: $INSTALL_DIR/scripts/install-systemd.sh${NC}"
            fi
        else
            info "Skipped. Start server manually when needed"
        fi
        echo ""
    fi

    # ─────────────────────────────────────────────────────────────────
    # Offer: Auto-start PTT client at login (requires global hotkey + systemd)
    # ─────────────────────────────────────────────────────────────────
    local has_autostart=0
    # Check actual file existence (not cached state)
    if [[ -f "$HOME/.config/autostart/aeo-ptt.desktop" ]]; then
        has_autostart=1
    elif [[ "$in_container" == "0" ]] && [[ "$has_global_hotkey" == "1" ]] && service_exists; then
        echo -e "${BOLD}Auto-Start Client${NC}"
        echo -e "${DIM}Start AEO Push-to-Talk automatically at login (Ctrl+Super in any app)${NC}"
        echo ""
        if [[ $(ask "Enable AEO Push-to-Talk auto-start?" "y") == "y" ]]; then
            if install_autostart; then
                has_autostart=1
            fi
        else
            info "Skipped. Start client manually when needed"
        fi
        echo ""
    fi

    # ─────────────────────────────────────────────────────────────────
    # Final summary and instructions
    # ─────────────────────────────────────────────────────────────────

    # Show configuration summary (non-container only)
    if [[ "$in_container" == "0" ]]; then
        echo -e "${BOLD}Configuration:${NC}"
        if [[ "$has_global_hotkey" == "1" ]]; then
            echo -e "  ${GREEN}✓${NC} Global hotkey: ${GREEN}Ctrl+Super${NC}"
        else
            echo -e "  ${DIM}○${NC} Global hotkey: ${DIM}not configured (using spacebar)${NC}"
        fi
        if service_exists; then
            echo -e "  ${GREEN}✓${NC} Server auto-start: ${GREEN}enabled${NC} (systemd)"
        else
            echo -e "  ${DIM}○${NC} Server auto-start: ${DIM}manual${NC}"
        fi
        if [[ "$has_autostart" == "1" ]]; then
            echo -e "  ${GREEN}✓${NC} Client auto-start: ${GREEN}enabled${NC} (tray icon at login)"
        else
            echo -e "  ${DIM}○${NC} Client auto-start: ${DIM}manual${NC}"
        fi
        echo ""
    fi

    # Logout reminder if needed (but not if autostart - that section has its own)
    if [[ "$needs_logout" == "1" ]] && [[ "$has_autostart" != "1" ]]; then
        echo -e "${YELLOW}${BOLD}► Log out and back in${NC} for group change to take effect"
        echo ""
    fi

    # Show appropriate next steps based on configuration
    if [[ "$has_autostart" == "1" ]]; then
        # Fully automated setup
        echo -e "${BOLD}You're all set!${NC}"
        echo ""

        if [[ "$needs_logout" == "1" ]]; then
            # Just added to input group - must logout first
            echo -e "${YELLOW}${BOLD}► Log out and back in${NC} to activate global hotkey."
            echo ""
            echo -e "  After logging back in, press ${GREEN}Ctrl+Super${NC} in any app to dictate."
            echo -e "  Look for the ${GREEN}green tray icon${NC} (turns red when recording)."
        else
            # Already in input group - start client now via desktop entry
            echo -e "Starting AEO Push-to-Talk..."
            if gtk-launch aeo-ptt 2>/dev/null; then
                sleep 1
                echo -e "${GREEN}✓${NC} Client started (check for tray icon)"
                echo ""
                echo -e "  Press ${GREEN}Ctrl+Super${NC} in any app to dictate."
                echo -e "  Look for the ${GREEN}green tray icon${NC} (turns red when recording)."
            else
                echo -e "${YELLOW}Could not start client automatically${NC}"
                echo -e "  Run: ${DIM}gtk-launch aeo-ptt${NC}"
            fi
        fi
        echo ""
    elif [[ "$in_container" == "1" ]]; then
        # Docker: show one-liner test option
        echo -e "${BOLD}Quick start:${NC}"
        echo ""
        echo "  # Test in single terminal (Docker) - hold SPACE to record"
        echo -e "  ${DIM}cd $INSTALL_DIR && (./scripts/stt-server.sh &) && sleep 3 && ./scripts/stt-client.sh --ptt${NC}"
        echo ""
        echo -e "  ${DIM}Hold SPACE to record, release to transcribe${NC}"
        echo ""
    elif service_exists; then
        # Server running but no autostart - show client command only
        echo -e "${BOLD}Quick start:${NC}"
        echo ""
        echo "  # Server is running. Start the client:"
        echo -e "  ${DIM}$INSTALL_DIR/scripts/stt-client.sh --ptt${NC}"
        echo ""
        if [[ "$has_global_hotkey" == "1" ]]; then
            echo -e "  ${DIM}Hold Ctrl+Super to record, release to transcribe${NC}"
        else
            echo -e "  ${DIM}Hold SPACE to record, release to transcribe${NC}"
        fi
        echo ""
    else
        # Fully manual setup
        echo -e "${BOLD}Quick start:${NC}"
        echo ""
        echo "  # Start server, then client"
        echo -e "  ${DIM}$INSTALL_DIR/scripts/stt-server.sh &${NC}"
        echo -e "  ${DIM}$INSTALL_DIR/scripts/stt-client.sh --ptt${NC}"
        echo ""
        if [[ "$has_global_hotkey" == "1" ]]; then
            echo -e "  ${DIM}Hold Ctrl+Super to record, release to transcribe${NC}"
        else
            echo -e "  ${DIM}Hold SPACE to record, release to transcribe${NC}"
        fi
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Usage / Help
# ═══════════════════════════════════════════════════════════════════

usage() {
    cat << 'EOF'
AEO Push-to-Talk Installer

USAGE:
    install.sh [OPTIONS]
    curl -fsSL https://...install.sh | bash

OPTIONS:
    -h, --help      Show this help message
    -y, --yes       Non-interactive mode (accept all defaults)
    --uninstall     Remove AEO Push-to-Talk and optionally the systemd service

ENVIRONMENT VARIABLES:
    STT_NONINTERACTIVE=1    No prompts, use defaults (same as -y)
    STT_INSTALL_DIR=path    Custom install location (default: ~/stt-service)
    STT_SKIP_MODEL=1        Don't download the speech model
    STT_WITH_SERVICE=1      Install systemd service by default

EXAMPLES:
    # Interactive install (recommended)
    curl -fsSL https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash

    # Non-interactive install with all defaults
    curl -fsSL ... | STT_NONINTERACTIVE=1 bash

    # Install to custom directory
    STT_INSTALL_DIR=/opt/stt ./install.sh

    # Uninstall
    ./install.sh --uninstall
EOF
}

uninstall() {
    setup_colors

    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AEO Push-to-Talk Uninstaller${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""

    local removed=0

    # Remove systemd service
    if service_exists; then
        info "Found systemd service"
        if [[ $(ask "Remove systemd service?" "y") == "y" ]]; then
            sudo systemctl stop stt-service 2>/dev/null || true
            sudo systemctl disable stt-service 2>/dev/null || true
            sudo rm -f /etc/systemd/system/stt-service.service
            sudo systemctl daemon-reload
            success "Systemd service removed"
            ((removed++))
        fi
    fi

    # Remove autostart entry
    if [[ -f "$HOME/.config/autostart/aeo-ptt.desktop" ]]; then
        info "Found autostart entry"
        if [[ $(ask "Remove autostart entry?" "y") == "y" ]]; then
            rm -f "$HOME/.config/autostart/aeo-ptt.desktop"
            success "Autostart entry removed"
            ((removed++))
        fi
    fi

    # Remove installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        info "Found installation: $INSTALL_DIR"
        if [[ $(ask "Remove installation directory?" "y") == "y" ]]; then
            rm -rf "$INSTALL_DIR"
            success "Installation directory removed"
            ((removed++))
        fi
    fi

    # Note about cached model (huggingface cache)
    local hf_cache="${HF_HOME:-$HOME/.cache/huggingface}/hub"
    if ls -d "$hf_cache"/models--istupakov--parakeet* &>/dev/null 2>&1; then
        info "Speech model cache exists in: $hf_cache"
        if [[ $(ask "Remove cached model (~2.5GB)?" "n") == "y" ]]; then
            rm -rf "$hf_cache"/models--istupakov--parakeet*
            success "Model cache removed"
            ((removed++))
        else
            info "Kept model cache (can be reused by future installs)"
        fi
    fi

    if [[ "$removed" -eq 0 ]]; then
        info "Nothing to remove"
    else
        echo ""
        success "Uninstall complete"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

main() {
    setup_colors

    # Header
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AEO Push-to-Talk Installer${NC}"
    echo -e "${BOLD}  GPU-accelerated speech-to-text for NVIDIA GB10${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Show what we'll do
    echo "This installer will:"
    echo "  • Check system requirements"
    echo "  • Install dependencies (uv, CUDA libs, PortAudio)"
    echo "  • Download and configure AEO Push-to-Talk"
    echo "  • Optionally download the speech model (~1GB)"
    echo ""
    echo -e "Install location: ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    # Confirm
    if [[ "$NONINTERACTIVE" != "1" ]]; then
        if [[ $(ask "Proceed with installation?" "y") != "y" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Run installation steps
    preflight_checks
    detect_existing
    install_system_deps
    install_uv
    download_package
    setup_python
    verify_gpu
    download_model
    setup_service
    show_completion
}

# ═══════════════════════════════════════════════════════════════════
# Argument parsing
# ═══════════════════════════════════════════════════════════════════

# Save original directory to return to after install (avoids direnv errors)
_ORIGINAL_DIR="$(pwd)"
trap 'cd "$_ORIGINAL_DIR" 2>/dev/null || true' EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes)
            NONINTERACTIVE=1
            shift
            ;;
        --uninstall)
            uninstall
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage"
            exit 1
            ;;
    esac
done

main
