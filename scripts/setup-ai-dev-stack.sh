#!/usr/bin/env bash
#
# AI Developer Essentials Stack Setup
# Idempotent installation script for a complete AI development environment
#
# Components:
#   - NVM + Node.js 22 LTS
#   - Mamba/Miniforge + 'dev' environment with AI packages
#   - Kitty terminal (GPU-optimized for high-DPI/OLED)
#   - Yazi file manager
#   - CLI tools: fd, fzf, bat, eza, delta, ripgrep, glow, btop, ncdu, duf, httpie, yq, shellcheck, p7zip
#   - tmux (with optional AEO config: C-Space prefix, true color, keyboard reference bar)
#   - Zellij terminal multiplexer
#   - bun (JS runtime) + direnv
#   - Zsh + Oh-My-Zsh + Powerlevel10k
#   - Pop Shell (GNOME tiling extension)
#   - Terminal media: ffmpeg, mpv (Kitty video playback), chafa
#   - Post-install: Kitty default terminal, git delta pager, fzf integration
#   - WSL2 environment setup (Wayland workaround, Mesa, D-Bus, display server)
#
# Usage: ./setup-ai-dev-stack.sh
#
# Author: Generated for AEO AI Essentials
# License: MIT

set -euo pipefail

# ─── Logging Setup ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
LOG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME}.log"
exec > >(stdbuf -oL tee "$LOG_FILE") 2>&1
echo "══════════════════════════════════════════════════════════════════════════"
echo "Log: $LOG_FILE | Started: $(date -Iseconds)"
echo "══════════════════════════════════════════════════════════════════════════"

# ─── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Helpers ────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

# ─── Architecture Detection ─────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_DEB="amd64"; ARCH_ALT="x86_64" ;;
    aarch64) ARCH_DEB="arm64"; ARCH_ALT="aarch64" ;;
    armv7l)  ARCH_DEB="armhf"; ARCH_ALT="armv7l" ;;
    *)       error "Unsupported architecture: $ARCH" ;;
esac
info "Detected architecture: $ARCH ($ARCH_DEB)"

# ─── WSL Detection ─────────────────────────────────────────────────────────
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    info "WSL2 detected - will apply WSL-specific configuration"
fi

# ─── Ensure sudo available ──────────────────────────────────────────────────
if ! command_exists sudo; then
    error "sudo is required but not installed"
fi

# ─── Update apt cache ───────────────────────────────────────────────────────
info "Updating package cache..."
sudo apt-get update

# ─── Install base dependencies ──────────────────────────────────────────────
info "Installing base dependencies..."
sudo apt-get install -y git curl unzip fontconfig

# ═══════════════════════════════════════════════════════════════════════════
# WSL2 ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════
if $IS_WSL; then
    info "Configuring WSL2 environment for GUI/Kitty support..."

    # --- Kitty Wayland workaround (current session) ---
    export KITTY_DISABLE_WAYLAND=1

    # --- DISPLAY fallback (current session only) ---
    # WSLg (Win11) sets DISPLAY automatically via /mnt/wslg
    # Only set fallback if WSLg is not present and DISPLAY is unset
    if [[ ! -d /mnt/wslg ]] && [[ -z "${DISPLAY:-}" ]]; then
        export DISPLAY=:0
        info "Set DISPLAY=:0 (no WSLg detected)"
    fi

    # --- mesa-utils for OpenGL diagnostics ---
    if ! command_exists glxinfo; then
        info "Installing mesa-utils (OpenGL diagnostics)..."
        sudo apt-get install -y mesa-utils
        success "mesa-utils installed"
    else
        warn "mesa-utils already installed"
    fi

    # --- dbus-x11 for D-Bus session support ---
    if ! dpkg -s dbus-x11 &>/dev/null; then
        info "Installing dbus-x11 (D-Bus session support)..."
        sudo apt-get install -y dbus-x11
        success "dbus-x11 installed"
    else
        warn "dbus-x11 already installed"
    fi

    success "WSL2 environment configured"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 1. ZSH + OH-MY-ZSH + POWERLEVEL10K + FONTS
# ═══════════════════════════════════════════════════════════════════════════

# Install Nerd Fonts (MesloLGS NF - recommended for Powerlevel10k)
info "Checking Nerd Fonts (MesloLGS NF)..."
FONT_DIR="$HOME/.local/share/fonts"
# Check for any MesloLGS font file (handles both space and %20 in filenames)
if ! ls "$FONT_DIR"/MesloLGS* &>/dev/null; then
    info "Installing MesloLGS Nerd Font..."
    mkdir -p "$FONT_DIR"
    curl -fSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" -o "$FONT_DIR/MesloLGS NF Regular.ttf"
    curl -fSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" -o "$FONT_DIR/MesloLGS NF Bold.ttf"
    curl -fSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" -o "$FONT_DIR/MesloLGS NF Italic.ttf"
    curl -fSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" -o "$FONT_DIR/MesloLGS NF Bold Italic.ttf"
    fc-cache -f
    success "MesloLGS Nerd Font installed"
else
    warn "MesloLGS Nerd Font already installed"
fi

info "Checking Zsh..."
if ! command_exists zsh; then
    info "Installing Zsh..."
    sudo apt-get install -y zsh
    success "Zsh installed"
else
    warn "Zsh already installed: $(zsh --version)"
fi

info "Checking Oh-My-Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Installing Oh-My-Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"  # silent: output piped to sh
    success "Oh-My-Zsh installed"
else
    warn "Oh-My-Zsh already installed"
fi

info "Checking Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    success "Powerlevel10k installed"
else
    warn "Powerlevel10k already installed"
fi

# Install essential zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

info "Checking zsh-autosuggestions..."
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    info "Installing zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    success "zsh-autosuggestions installed"
else
    warn "zsh-autosuggestions already installed"
fi

info "Checking zsh-syntax-highlighting..."
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    info "Installing zsh-syntax-highlighting..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    success "zsh-syntax-highlighting installed"
else
    warn "zsh-syntax-highlighting already installed"
fi

# Set Zsh as default shell if not already
if [[ "$SHELL" != *"zsh"* ]]; then
    info "Setting Zsh as default shell..."
    if sudo chsh -s "$(which zsh)" "$USER" 2>/dev/null; then
        success "Zsh set as default shell (log out and back in to apply)"
    else
        warn "Could not change default shell (run 'chsh -s $(which zsh)' manually)"
    fi
else
    warn "Zsh is already the default shell"
fi

# Configure .zshrc with oh-my-zsh wiring (theme + plugins).
# Single guard: if oh-my-zsh.sh is not sourced anywhere, append the full block.
# Otherwise (standard omz .zshrc), use sed to update the existing ZSH_THEME and plugins lines.
if ! grep -q 'oh-my-zsh\.sh' ~/.zshrc 2>/dev/null; then
    info "Wiring oh-my-zsh into .zshrc (theme + plugins + source)..."
    cat >> ~/.zshrc << 'EOF'

# ─── Oh-My-Zsh ─────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh
EOF
    success "Appended oh-my-zsh block to ~/.zshrc"
else
    # oh-my-zsh is already sourced — adjust theme + plugin list in place.
    if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' ~/.zshrc 2>/dev/null; then
        info "Setting Powerlevel10k theme in .zshrc..."
        if grep -q '^ZSH_THEME=' ~/.zshrc 2>/dev/null; then
            sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
        else
            echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
        fi
    fi
    if ! grep -q 'zsh-autosuggestions' ~/.zshrc 2>/dev/null; then
        info "Adding zsh-autosuggestions to .zshrc plugins..."
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' ~/.zshrc 2>/dev/null || true
    fi
    if ! grep -q 'zsh-syntax-highlighting' ~/.zshrc 2>/dev/null; then
        info "Adding zsh-syntax-highlighting to .zshrc plugins..."
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting)/' ~/.zshrc 2>/dev/null || true
    fi
fi

# --- Apply AEO Powerlevel10k preset (skip wizard on first launch) ---
P10K_PRESET_APPLIED=false
P10K_PRESET_SRC="$SCRIPT_DIR/../configs/zsh/p10k-aeo.zsh"
if [[ -f "$P10K_PRESET_SRC" ]]; then
    echo ""
    echo -e "${BLUE}Powerlevel10k Configuration${NC}"
    echo "  The AEO preset provides a ready-to-use terminal prompt theme."
    echo "  If you skip this, the p10k configuration wizard will run on first Zsh launch."
    echo ""
    read -r -p "Apply AEO Powerlevel10k theme preset? [Y/n] " p10k_answer || p10k_answer="n"
    if [[ "${p10k_answer,,}" != "n" ]]; then
        # Deploy p10k config (skip if user already has one)
        if [[ ! -f "$HOME/.p10k.zsh" ]]; then
            cp "$P10K_PRESET_SRC" "$HOME/.p10k.zsh"
            success "Copied AEO p10k preset → ~/.p10k.zsh"
        else
            warn "~/.p10k.zsh already exists (keeping existing config)"
        fi

        # Prepend instant prompt cache block to top of .zshrc (p10k requirement)
        if ! grep -q 'Enable Powerlevel10k instant prompt' ~/.zshrc 2>/dev/null; then
            info "Adding Powerlevel10k instant prompt to top of .zshrc..."
            INSTANT_PROMPT_BLOCK='# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
'
            # Prepend to .zshrc (preserve permissions)
            _tmpfile=$(mktemp)
            printf '%s' "$INSTANT_PROMPT_BLOCK" | cat - ~/.zshrc > "$_tmpfile"
            chmod --reference="$HOME/.zshrc" "$_tmpfile"
            mv "$_tmpfile" ~/.zshrc
            success "Instant prompt block added to top of .zshrc"
        fi

        P10K_PRESET_APPLIED=true
        success "AEO Powerlevel10k theme preset applied"
    else
        info "Skipped AEO preset — p10k wizard will run on first Zsh launch"
    fi
fi

# --- .zshenv (NVM + Bun env exports for non-interactive shells) ---
ZSHENV_SRC="$SCRIPT_DIR/../configs/zsh/zshenv"
ZSHENV_DEST="$HOME/.zshenv"

if [[ -f "$ZSHENV_SRC" ]]; then
    echo ""
    echo -e "${BLUE}Zsh Environment File (~/.zshenv)${NC}"
    echo "  Adds NVM and Bun env exports so Node/npm/bun are available in"
    echo "  non-interactive shells (CI, VS Code tasks, ssh host cmd)."
    echo ""
    if [[ -f "$ZSHENV_DEST" ]]; then
        echo -e "${YELLOW}  An existing ~/.zshenv was found. It will be backed up before any changes.${NC}"
        echo "  Missing NVM_DIR / BUN_INSTALL blocks will be appended; existing content is preserved."
    else
        echo "  No existing ~/.zshenv found. The AEO template will be installed fresh."
    fi
    echo ""
    read -r -p "Deploy AEO ~/.zshenv env exports? [Y/n] " zshenv_answer || zshenv_answer="n"
    if [[ "${zshenv_answer,,}" != "n" ]]; then
        if [[ ! -f "$ZSHENV_DEST" ]]; then
            cp "$ZSHENV_SRC" "$ZSHENV_DEST"
            success "Deployed AEO ~/.zshenv (NVM + Bun env exports)"
        else
            # Only back up if something actually needs appending.
            _needs_nvm=false
            _needs_bun=false
            grep -q 'NVM_DIR' "$ZSHENV_DEST" 2>/dev/null || _needs_nvm=true
            grep -q 'BUN_INSTALL' "$ZSHENV_DEST" 2>/dev/null || _needs_bun=true
            if [[ "$_needs_nvm" == true || "$_needs_bun" == true ]]; then
                cp "$ZSHENV_DEST" "$ZSHENV_DEST.bak.$(date +%Y%m%d%H%M%S)"
                info "Backed up existing ~/.zshenv"
                if [[ "$_needs_nvm" == true ]]; then
                    info "Appending NVM block to ~/.zshenv..."
                    cat >> "$ZSHENV_DEST" << 'EOF'

# ─── NVM ───────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
                fi
                if [[ "$_needs_bun" == true ]]; then
                    info "Appending Bun block to ~/.zshenv..."
                    cat >> "$ZSHENV_DEST" << 'EOF'

# ─── Bun ───────────────────────────────────────────────────────────────────────
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
EOF
                fi
                success "AEO ~/.zshenv env exports applied"
            else
                warn "AEO blocks already present in ~/.zshenv — no changes needed"
            fi
        fi
    else
        info "Skipped ~/.zshenv deployment"
    fi
else
    warn "configs/zsh/zshenv not found — skipping .zshenv deployment"
fi

# --- Tmux (install + optional AEO config) ---
TMUX_CONFIG_APPLIED=false
TMUX_FRESH_INSTALL=false
TMUX_CONFIG_SRC="$SCRIPT_DIR/../configs/tmux"
TMUX_DEST="$HOME/.config/tmux"

info "Checking tmux..."
if ! command_exists tmux; then
    info "Installing tmux..."
    sudo apt-get install -y tmux
    TMUX_FRESH_INSTALL=true
    success "tmux installed"
else
    TMUX_CURRENT="$(tmux -V)"
    warn "tmux already installed: $TMUX_CURRENT"
    read -r -p "Upgrade tmux to latest apt version? [y/N] " tmux_upgrade || tmux_upgrade="n"
    if [[ "${tmux_upgrade,,}" == "y" ]]; then
        sudo apt-get install -y --only-upgrade tmux
        success "tmux upgraded: $(tmux -V)"
    fi
fi

if command_exists tmux && [[ -f "$TMUX_CONFIG_SRC/tmux.conf" ]]; then
    if $TMUX_FRESH_INSTALL; then
        # Fresh install — no existing config to clobber, just deploy
        mkdir -p "$TMUX_DEST/scripts"
        cp "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf"
        if [[ -d "$TMUX_CONFIG_SRC/scripts" ]]; then
            cp "$TMUX_CONFIG_SRC/scripts/"* "$TMUX_DEST/scripts/"
            chmod +x "$TMUX_DEST/scripts/"*.sh 2>/dev/null || true
        fi
        TMUX_CONFIG_APPLIED=true
        success "AEO tmux config deployed -> ~/.config/tmux/"
    else
        # Existing install — ask before replacing
        echo ""
        echo -e "${BLUE}Tmux Configuration${NC}"
        echo "  The AEO tmux config sets C-Space prefix (avoids Claude Code Ctrl+b conflict),"
        echo "  true color, vi copy mode, OSC 52 clipboard, and a 3-line keyboard reference bar."
        echo ""
        echo -e "${YELLOW}  WARNING: This will REPLACE your existing tmux config if you have one.${NC}"
        if [[ -f "$TMUX_DEST/tmux.conf" ]]; then
            echo -e "  Existing config found: ${TMUX_DEST}/tmux.conf (will be backed up)"
        elif [[ -f "$HOME/.tmux.conf" ]]; then
            echo -e "  Existing config found: ~/.tmux.conf (will be backed up)"
        fi
        echo ""
        read -r -p "Apply AEO tmux config? [y/N] " tmux_answer || tmux_answer="n"
        if [[ "${tmux_answer,,}" == "y" ]]; then
            # Back up existing configs
            if [[ -f "$TMUX_DEST/tmux.conf" ]]; then
                cp "$TMUX_DEST/tmux.conf" "$TMUX_DEST/tmux.conf.bak.$(date +%Y%m%d%H%M%S)"
                info "Backed up existing ~/.config/tmux/tmux.conf"
            fi
            if [[ -f "$HOME/.tmux.conf" ]]; then
                cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$(date +%Y%m%d%H%M%S)"
                info "Backed up existing ~/.tmux.conf"
            fi

            mkdir -p "$TMUX_DEST/scripts"
            cp "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf"
            if [[ -d "$TMUX_CONFIG_SRC/scripts" ]]; then
                cp "$TMUX_CONFIG_SRC/scripts/"* "$TMUX_DEST/scripts/"
                chmod +x "$TMUX_DEST/scripts/"*.sh 2>/dev/null || true
            fi

            TMUX_CONFIG_APPLIED=true
            success "AEO tmux config deployed -> ~/.config/tmux/"
        else
            info "Skipped AEO tmux config"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 2. NVM + NODE.JS 22 LTS
# ═══════════════════════════════════════════════════════════════════════════
info "Checking NVM..."
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
    info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    success "NVM installed"
else
    warn "NVM already installed"
fi

# Source NVM for current session
[[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"

info "Checking Node.js 22 LTS..."
if ! nvm ls 22 &>/dev/null; then
    info "Installing Node.js 22 LTS..."
    nvm install 22 --lts
    nvm alias default 22 &>/dev/null
    success "Node.js 22 LTS installed and set as default"
else
    warn "Node.js 22 already installed"
    nvm alias default 22 &>/dev/null || true
fi

# Ensure NVM is in zshrc (skip if already covered by .zshenv)
if ! grep -q 'NVM_DIR' ~/.zshrc 2>/dev/null && ! grep -q 'NVM_DIR' ~/.zshenv 2>/dev/null; then
    info "Adding NVM to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── NVM ───────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
fi

# ═══════════════════════════════════════════════════════════════════════════
# 3. MAMBA/MINIFORGE + DEV ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Mamba/Miniforge..."
MINIFORGE_DIR="$HOME/miniforge3"
if [[ ! -d "$MINIFORGE_DIR" ]]; then
    info "Installing Miniforge (includes Mamba)..."
    curl -fSL -o /tmp/miniforge.sh "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH_ALT}.sh"
    bash /tmp/miniforge.sh -b -p "$MINIFORGE_DIR"
    rm /tmp/miniforge.sh
    success "Miniforge installed"
else
    warn "Miniforge already installed"
fi

# Initialize conda/mamba for current session
eval "$("$MINIFORGE_DIR/bin/conda" shell.bash hook)"

# Create 'dev' environment if it doesn't exist
info "Checking 'dev' mamba environment..."
if [[ ! -d "$MINIFORGE_DIR/envs/dev" ]]; then
    info "Creating 'dev' environment with AI essentials..."
    mamba create -n dev -y python=3.12 anthropic openai httpx rich typer pydantic
    success "'dev' environment created with AI packages"
else
    warn "'dev' environment already exists"
fi

# Ensure conda init is in zshrc
if ! grep -q 'conda initialize' ~/.zshrc 2>/dev/null; then
    info "Adding conda init to .zshrc..."
    "$MINIFORGE_DIR/bin/conda" init zsh
fi

# ═══════════════════════════════════════════════════════════════════════════
# 4. KITTY TERMINAL
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Kitty..."
if ! command_exists kitty; then
    info "Installing Kitty terminal..."
    sudo apt-get install -y kitty
    success "Kitty installed"

    # Configure Kitty (GPU-optimized for high-DPI/OLED displays)
    mkdir -p ~/.config/kitty
    if [[ ! -f ~/.config/kitty/kitty.conf ]]; then
        info "Configuring Kitty (GPU-optimized)..."
        cat > ~/.config/kitty/kitty.conf << 'EOF'
# ─── Kitty Configuration ───────────────────────────────────────────────────
# Optimized for high-performance GPU systems (RTX 3090 / GB10)

# ─── Window Size (4K 2x3 grid: 1280x1080 per cell) ─────────────────────────
remember_window_size no
initial_window_width 1260
initial_window_height 1040

# ─── Font - MesloLGS NF (Nerdfont for Powerlevel10k) ───────────────────────
font_family MesloLGS NF
bold_font MesloLGS NF Bold
italic_font MesloLGS NF Italic
bold_italic_font MesloLGS NF Bold Italic
font_size 9.0
disable_ligatures never

# ─── Theme (OLED optimized - true black) ───────────────────────────────────
background #000000
foreground #d0d0d0
cursor #d7af00
cursor_text_color #000000
selection_background #32291B
selection_foreground #d7af00

# 16-color palette
color0  #000000
color1  #d75f5f
color2  #5fd700
color3  #d7af00
color4  #0087af
color5  #af87d7
color6  #00afff
color7  #d0d0d0
color8  #5a5a5a
color9  #ff8787
color10 #87ff5f
color11 #ffd75f
color12 #5fafff
color13 #d7afff
color14 #5fd7ff
color15 #ffffff

# ─── High Performance GPU Settings ─────────────────────────────────────────
repaint_delay 5
input_delay 1
sync_to_monitor no

# Large scrollback (RAM is cheap)
scrollback_lines 50000
scrollback_pager_history_size 100

# No animations/distractions
cursor_blink_interval 0
visual_bell_duration 0
window_alert_on_bell no
enable_audio_bell no

# ─── Input ─────────────────────────────────────────────────────────────────
copy_on_select clipboard
mouse_map right press ungrabbed paste_from_clipboard

# ─── Shell Integration ─────────────────────────────────────────────────────
shell_integration enabled

# ─── UI ────────────────────────────────────────────────────────────────────
tab_bar_style powerline
window_padding_width 4
confirm_os_window_close 0

# ─── Cursor ────────────────────────────────────────────────────────────────
cursor_shape beam

# ─── URLs ──────────────────────────────────────────────────────────────────
url_style curly
open_url_with default

# ─── Keyboard Shortcuts ────────────────────────────────────────────────────
map ctrl+equal change_font_size all +1.0
map ctrl+minus change_font_size all -1.0
map ctrl+0 change_font_size all 0
EOF
        success "Kitty configured (GPU-optimized)"
    fi
else
    warn "Kitty already installed"
fi

# WSL2: force X11 display server in Kitty config
if $IS_WSL && [[ -f ~/.config/kitty/kitty.conf ]]; then
    if ! grep -q 'linux_display_server' ~/.config/kitty/kitty.conf; then
        echo -e '\n# WSL2: force X11 display server\nlinux_display_server x11' >> ~/.config/kitty/kitty.conf
        success "Kitty configured for WSL2 (linux_display_server x11)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 5. YAZI FILE MANAGER
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Yazi..."
if ! command_exists yazi; then
    info "Installing Yazi..."
    info "  Fetching latest version from GitHub API..."
    YAZI_VERSION=$(curl --max-time 30 https://api.github.com/repos/sxyazi/yazi/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    info "  Version: $YAZI_VERSION"
    YAZI_URL="https://github.com/sxyazi/yazi/releases/download/${YAZI_VERSION}/yazi-${ARCH_ALT}-unknown-linux-gnu.zip"
    info "  Downloading: $YAZI_URL"
    curl -fSL "$YAZI_URL" -o /tmp/yazi.zip
    unzip -o /tmp/yazi.zip -d /tmp/yazi
    sudo mv /tmp/yazi/yazi-${ARCH_ALT}-unknown-linux-gnu/yazi /usr/local/bin/
    sudo mv /tmp/yazi/yazi-${ARCH_ALT}-unknown-linux-gnu/ya /usr/local/bin/ 2>/dev/null || true
    rm -rf /tmp/yazi /tmp/yazi.zip
    success "Yazi installed"
else
    warn "Yazi already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 6. CLI POWER TOOLS
# ═══════════════════════════════════════════════════════════════════════════

# ripgrep
info "Checking ripgrep..."
if ! command_exists rg || [[ "$(which rg)" == *"claude"* ]]; then
    info "Installing ripgrep..."
    sudo apt-get install -y ripgrep
    success "ripgrep installed"
else
    warn "ripgrep already installed"
fi

# fd
info "Checking fd..."
if ! command_exists fd && ! command_exists fdfind; then
    info "Installing fd..."
    sudo apt-get install -y fd-find
    # Create fd symlink if fdfind is installed
    if command_exists fdfind && ! command_exists fd; then
        sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
    success "fd installed"
else
    warn "fd already installed"
fi

# fzf
info "Checking fzf..."
if ! command_exists fzf; then
    info "Installing fzf..."
    sudo apt-get install -y fzf
    success "fzf installed"
else
    warn "fzf already installed"
fi

# bat
info "Checking bat..."
if ! command_exists bat && ! command_exists batcat; then
    info "Installing bat..."
    sudo apt-get install -y bat
    # Create bat symlink if batcat is installed
    if command_exists batcat && ! command_exists bat; then
        sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
    success "bat installed"
else
    warn "bat already installed"
fi

# eza (modern ls replacement)
info "Checking eza..."
if ! command_exists eza; then
    info "Installing eza..."
    sudo apt-get install -y eza || {
        # Fallback: install from GitHub releases
        EZA_VERSION=$(curl --max-time 30 https://api.github.com/repos/eza-community/eza/releases/latest | grep -oP '"tag_name": "\K[^"]+')
        curl -fSL "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${ARCH_ALT}-unknown-linux-gnu.tar.gz" -o /tmp/eza.tar.gz
        sudo tar -xzf /tmp/eza.tar.gz -C /usr/local/bin/
        rm /tmp/eza.tar.gz
    }
    success "eza installed"
else
    warn "eza already installed"
fi

# delta (git diff viewer)
info "Checking delta..."
if ! command_exists delta; then
    info "Installing delta..."
    info "  Fetching latest version from GitHub API..."
    DELTA_VERSION=$(curl --max-time 30 https://api.github.com/repos/dandavison/delta/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    info "  Version: $DELTA_VERSION"
    DELTA_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH_DEB}.deb"
    info "  Downloading: $DELTA_URL"
    curl -fSL "$DELTA_URL" -o /tmp/delta.deb
    sudo dpkg -i /tmp/delta.deb || sudo apt-get install -f -y
    rm /tmp/delta.deb
    success "delta installed"
else
    warn "delta already installed"
fi

# glow (markdown renderer)
info "Checking glow..."
if ! command_exists glow; then
    info "Installing glow..."
    info "  Fetching latest version from GitHub API..."
    GLOW_VERSION=$(curl --max-time 30 https://api.github.com/repos/charmbracelet/glow/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
    info "  Version: $GLOW_VERSION"
    # glow uses 'arm64' not 'aarch64' in release names
    GLOW_ARCH="${ARCH_ALT}"
    [[ "$ARCH" == "aarch64" ]] && GLOW_ARCH="arm64"
    GLOW_URL="https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_${GLOW_ARCH}.tar.gz"
    info "  Downloading: $GLOW_URL"
    curl -fSL "$GLOW_URL" -o /tmp/glow.tar.gz
    sudo tar -xzf /tmp/glow.tar.gz -C /usr/local/bin/ --strip-components=1 --wildcards "*/glow"
    rm /tmp/glow.tar.gz
    success "glow installed"
else
    warn "glow already installed"
fi

# btop (beautiful system monitor)
info "Checking btop..."
if ! command_exists btop; then
    info "Installing btop..."
    sudo apt-get install -y btop
    success "btop installed"
else
    warn "btop already installed"
fi

# ncdu (interactive disk usage analyzer)
info "Checking ncdu..."
if ! command_exists ncdu; then
    info "Installing ncdu..."
    sudo apt-get install -y ncdu
    success "ncdu installed"
else
    warn "ncdu already installed"
fi

# duf (modern df replacement)
info "Checking duf..."
if ! command_exists duf; then
    info "Installing duf..."
    info "  Fetching latest version from GitHub API..."
    DUF_VERSION=$(curl --max-time 30 -sS https://api.github.com/repos/muesli/duf/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
    if [[ -z "$DUF_VERSION" ]]; then
        error "Failed to fetch duf version from GitHub API"
    fi
    info "  Version: $DUF_VERSION"
    # duf uses 'arm64' not 'aarch64' in release names
    DUF_ARCH="${ARCH_ALT}"
    [[ "$ARCH" == "aarch64" ]] && DUF_ARCH="arm64"
    DUF_URL="https://github.com/muesli/duf/releases/download/v${DUF_VERSION}/duf_${DUF_VERSION}_linux_${DUF_ARCH}.tar.gz"
    info "  Downloading: $DUF_URL"
    curl --max-time 60 -fSL "$DUF_URL" -o /tmp/duf.tar.gz
    sudo tar -xzf /tmp/duf.tar.gz -C /usr/local/bin/ duf
    rm /tmp/duf.tar.gz
    success "duf installed"
else
    warn "duf already installed"
fi

# httpie (human-friendly curl alternative)
info "Checking httpie..."
if ! command_exists http; then
    info "Installing httpie..."
    sudo apt-get install -y httpie
    success "httpie installed"
else
    warn "httpie already installed"
fi

# yq (YAML processor - mikefarah/yq via snap, NOT the apt jq-wrapper)
info "Checking yq..."
if ! command_exists yq; then
    info "Installing yq via snap..."
    sudo snap install yq
    success "yq installed"
else
    warn "yq already installed"
fi

# Shellcheck (shell script linter)
info "Checking shellcheck..."
if ! command_exists shellcheck; then
    info "Installing shellcheck..."
    sudo apt-get install -y shellcheck
    success "shellcheck installed"
else
    warn "shellcheck already installed"
fi

# p7zip-full (7z archive support)
info "Checking p7zip..."
if ! command_exists 7z; then
    info "Installing p7zip-full..."
    sudo apt-get install -y p7zip-full
    success "p7zip-full installed"
else
    warn "p7zip already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 7. ZELLIJ TERMINAL MULTIPLEXER
# ═══════════════════════════════════════════════════════════════════════════
ZELLIJ_CONFIG_APPLIED=false
ZELLIJ_FRESH_INSTALL=false
ZELLIJ_CONFIG_SRC="$SCRIPT_DIR/../configs/zellij"
ZELLIJ_DEST="$HOME/.config/zellij"

info "Checking Zellij..."
if ! command_exists zellij; then
    info "Installing Zellij..."
    info "  Fetching latest version from GitHub API..."
    ZELLIJ_VERSION=$(curl --max-time 30 https://api.github.com/repos/zellij-org/zellij/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    info "  Version: $ZELLIJ_VERSION"
    ZELLIJ_URL="https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VERSION}/zellij-${ARCH_ALT}-unknown-linux-musl.tar.gz"
    info "  Downloading: $ZELLIJ_URL"
    curl -fSL "$ZELLIJ_URL" -o /tmp/zellij.tar.gz
    sudo tar -xzf /tmp/zellij.tar.gz -C /usr/local/bin/
    rm /tmp/zellij.tar.gz
    ZELLIJ_FRESH_INSTALL=true
    success "Zellij installed"
else
    warn "Zellij already installed"
fi

# zjstatus plugin (required by AEO layout for the Alt-key powerline status row)
# `-s` test (exists AND non-empty) so a 0-byte download from a prior run gets repaired.
if command_exists zellij; then
    mkdir -p "$ZELLIJ_DEST/plugins"
    if [[ ! -s "$ZELLIJ_DEST/plugins/zjstatus.wasm" ]]; then
        if [[ -f "$ZELLIJ_DEST/plugins/zjstatus.wasm" ]]; then
            info "zjstatus.wasm exists but is empty — re-downloading..."
        else
            info "Downloading zjstatus plugin..."
        fi
        ZJSTATUS_URL="https://github.com/dj95/zjstatus/releases/latest/download/zjstatus.wasm"
        if curl -fSL --max-time 60 "$ZJSTATUS_URL" -o "$ZELLIJ_DEST/plugins/zjstatus.wasm" \
            && [[ -s "$ZELLIJ_DEST/plugins/zjstatus.wasm" ]]; then
            success "zjstatus.wasm installed -> ~/.config/zellij/plugins/"
        else
            warn "Failed to download zjstatus.wasm (or got empty file) — Alt-key status row will not render"
        fi
    else
        warn "zjstatus.wasm already present"
    fi
fi

# zjwidth sidecar plugin (required by AEO layout: width-aware Alt-bar via {pipe_altbar})
# `-s` test guards against deploying a 0-byte wasm if the repo build was mid-flight.
if command_exists zellij; then
    if [[ -s "$ZELLIJ_CONFIG_SRC/plugins/zjwidth.wasm" ]]; then
        cp "$ZELLIJ_CONFIG_SRC/plugins/zjwidth.wasm" "$ZELLIJ_DEST/plugins/zjwidth.wasm"
        if [[ -s "$ZELLIJ_DEST/plugins/zjwidth.wasm" ]]; then
            success "zjwidth.wasm installed -> ~/.config/zellij/plugins/"
        else
            warn "zjwidth.wasm copied but deployed file is empty — Alt-key bar will be empty"
        fi
    elif [[ -f "$ZELLIJ_CONFIG_SRC/plugins/zjwidth.wasm" ]]; then
        warn "zjwidth.wasm in repo at $ZELLIJ_CONFIG_SRC/plugins/ is empty (0 bytes) — skipping deploy"
    else
        warn "zjwidth.wasm not found in repo at $ZELLIJ_CONFIG_SRC/plugins/ — Alt-key bar will be empty"
    fi
fi

# Pre-seed zellij plugin permissions so users don't get prompted on first
# session for AEO-deployed plugins. Idempotently merges into permissions.kdl;
# preserves any existing grants for other plugins.
if command_exists zellij && command_exists python3; then
    python3 - <<'PYEOF'
import os
import re
from pathlib import Path

HOME = Path(os.environ["HOME"])
PATH = HOME / ".cache/zellij/permissions.kdl"
PATH.parent.mkdir(parents=True, exist_ok=True)
PLUGINS_DIR = str(HOME / ".config/zellij/plugins")

GRANTS = {
    f"{PLUGINS_DIR}/zjstatus.wasm": [
        "ReadApplicationState",
        "ChangeApplicationState",
        "RunCommands",
    ],
    f"{PLUGINS_DIR}/zjwidth.wasm": [
        "ReadApplicationState",
        "ChangeApplicationState",
        "MessageAndLaunchOtherPlugins",
    ],
}

existing = PATH.read_text() if PATH.exists() else ""

def remove_block(text, path):
    pattern = re.compile(
        r'^\s*"' + re.escape(path) + r'"\s*\{[^}]*\}\s*\n?',
        re.MULTILINE | re.DOTALL,
    )
    return pattern.sub("", text)

def block_for(path, perms):
    inner = "\n".join(f"    {p}" for p in perms)
    return f'"{path}" {{\n{inner}\n}}\n'

result = existing
for path, perms in GRANTS.items():
    result = remove_block(result, path)
    if result and not result.endswith("\n"):
        result += "\n"
    result += block_for(path, perms)

PATH.write_text(result)
PYEOF
    success "Pre-seeded zellij plugin permissions for zjstatus and zjwidth"
fi

if command_exists zellij && [[ -f "$ZELLIJ_CONFIG_SRC/config.kdl" ]]; then
    if $ZELLIJ_FRESH_INSTALL; then
        # Fresh install — no existing config to clobber, just deploy
        mkdir -p "$ZELLIJ_DEST/layouts"
        cp "$ZELLIJ_CONFIG_SRC/config.kdl" "$ZELLIJ_DEST/config.kdl"
        cp "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl"
        ZELLIJ_CONFIG_APPLIED=true
        success "AEO zellij config deployed -> ~/.config/zellij/"
    else
        # Existing install — ask before replacing
        echo ""
        echo -e "${BLUE}Zellij Configuration${NC}"
        echo "  The AEO zellij config provides the p10k-aeo theme, custom keybinds"
        echo "  (Alt+w SIGWINCH redraw, Alt+arrows navigation, Alt+p pane group),"
        echo "  and a powerline Alt-key reference status row via the zjstatus plugin."
        echo ""
        echo -e "${YELLOW}  WARNING: This will REPLACE your existing zellij config if you have one.${NC}"
        if [[ -f "$ZELLIJ_DEST/config.kdl" ]]; then
            echo -e "  Existing config found: ${ZELLIJ_DEST}/config.kdl (will be backed up)"
        fi
        echo ""
        read -r -p "Apply AEO zellij config? [y/N] " zellij_answer || zellij_answer="n"
        if [[ "${zellij_answer,,}" == "y" ]]; then
            STAMP="$(date +%Y%m%d%H%M%S)"
            if [[ -f "$ZELLIJ_DEST/config.kdl" ]]; then
                cp "$ZELLIJ_DEST/config.kdl" "$ZELLIJ_DEST/config.kdl.bak.$STAMP"
                info "Backed up existing ~/.config/zellij/config.kdl"
            fi
            if [[ -f "$ZELLIJ_DEST/layouts/default.kdl" ]]; then
                cp "$ZELLIJ_DEST/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl.bak.$STAMP"
                info "Backed up existing ~/.config/zellij/layouts/default.kdl"
            fi
            mkdir -p "$ZELLIJ_DEST/layouts"
            cp "$ZELLIJ_CONFIG_SRC/config.kdl" "$ZELLIJ_DEST/config.kdl"
            cp "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl"
            ZELLIJ_CONFIG_APPLIED=true
            success "AEO zellij config deployed -> ~/.config/zellij/"
        else
            info "Skipped AEO zellij config"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 8. BUN (FAST JS RUNTIME)
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Bun..."
if [[ ! -x "$HOME/.bun/bin/bun" ]]; then
    info "Installing Bun..."
    curl -fSL https://bun.sh/install | bash
    success "Bun installed"
else
    warn "Bun already installed: $("$HOME"/.bun/bin/bun --version)"
fi

# Ensure bun is in zshrc (skip if already covered by .zshenv)
if ! grep -q 'BUN_INSTALL' ~/.zshrc 2>/dev/null && ! grep -q 'BUN_INSTALL' ~/.zshenv 2>/dev/null; then
    info "Adding Bun to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── Bun ───────────────────────────────────────────────────────────────────────
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
EOF
fi

# ═══════════════════════════════════════════════════════════════════════════
# 9. DIRENV
# ═══════════════════════════════════════════════════════════════════════════
info "Checking direnv..."
if ! command_exists direnv; then
    info "Installing direnv..."
    sudo apt-get install -y direnv
    success "direnv installed"
else
    warn "direnv already installed"
fi

# Add direnv hook to zshrc
if ! grep -q 'direnv hook' ~/.zshrc 2>/dev/null; then
    info "Adding direnv hook to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── Direnv ────────────────────────────────────────────────────────────────────
eval "$(direnv hook zsh)"
EOF
fi

# ═══════════════════════════════════════════════════════════════════════════
# 10. TERMINAL MEDIA TOOLS
# ═══════════════════════════════════════════════════════════════════════════

# ffmpeg (video processing foundation)
info "Checking ffmpeg..."
if ! command_exists ffmpeg; then
    info "Installing ffmpeg..."
    sudo apt-get install -y ffmpeg
    success "ffmpeg installed"
else
    warn "ffmpeg already installed"
fi

# mpv (video player with Kitty graphics protocol)
info "Checking mpv..."
if ! command_exists mpv; then
    info "Installing mpv..."
    sudo apt-get install -y mpv
    success "mpv installed"
else
    warn "mpv already installed"
fi

# chafa (terminal image/GIF renderer)
info "Checking chafa..."
if ! command_exists chafa; then
    info "Installing chafa..."
    sudo apt-get install -y chafa
    success "chafa installed"
else
    warn "chafa already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 11. POP SHELL (GNOME TILING EXTENSION)
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Pop Shell..."
POP_SHELL_DIR="$HOME/.local/share/gnome-shell/extensions/pop-shell@system76.com"
if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]] && [[ ! -d "$POP_SHELL_DIR" ]]; then
    info "Installing Pop Shell (GNOME tiling extension)..."

    # Install TypeScript dependency
    sudo apt-get install -y node-typescript

    # Clone and build Pop Shell
    TEMP_DIR=$(mktemp -d)
    git clone --depth=1 https://github.com/pop-os/shell.git "$TEMP_DIR/pop-shell"
    cd "$TEMP_DIR/pop-shell"

    # Build without interactive prompts
    make local-install <<< "n" 2>/dev/null || make local-install

    cd - > /dev/null
    rm -rf "$TEMP_DIR"

    # Enable the extension
    gnome-extensions enable "pop-shell@system76.com" 2>/dev/null || true

    # Apply optimized settings
    dconf write /org/gnome/shell/extensions/pop-shell/tile-by-default true
    dconf write /org/gnome/shell/extensions/pop-shell/gap-inner 4
    dconf write /org/gnome/shell/extensions/pop-shell/gap-outer 4
    dconf write /org/gnome/shell/extensions/pop-shell/active-hint true
    dconf write /org/gnome/shell/extensions/pop-shell/smart-gaps true
    dconf write /org/gnome/shell/extensions/pop-shell/show-title false

    success "Pop Shell installed and configured"
elif [[ "${XDG_CURRENT_DESKTOP:-}" != *"GNOME"* ]]; then
    warn "Pop Shell skipped (requires GNOME desktop)"
else
    warn "Pop Shell already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 12. POST-INSTALL CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

# --- Kitty as default terminal (GNOME) ---
if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]] && command_exists kitty; then
    KITTY_PATH=$(which kitty)
    CURRENT_TERMINAL=$(update-alternatives --query x-terminal-emulator 2>/dev/null | grep "^Value:" | cut -d' ' -f2)
    if [[ "$CURRENT_TERMINAL" != "$KITTY_PATH" ]]; then
        info "Setting Kitty as default terminal (GNOME)..."
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$KITTY_PATH" 50
        sudo update-alternatives --set x-terminal-emulator "$KITTY_PATH"
        gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty' 2>/dev/null || true
        success "Kitty set as default terminal"
    else
        warn "Kitty already set as default terminal"
    fi
elif [[ "${XDG_CURRENT_DESKTOP:-}" != *"GNOME"* ]]; then
    warn "Kitty default terminal skipped (requires GNOME desktop)"
elif ! command_exists kitty; then
    warn "Kitty default terminal skipped (kitty not installed)"
fi

# --- Git delta as default pager ---
if command_exists delta; then
    if [[ "$(git config --global --get core.pager 2>/dev/null)" != "delta" ]]; then
        info "Configuring git delta as default pager..."
        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.navigate true
        git config --global delta.dark true
        git config --global merge.conflictStyle zdiff3
        success "Git delta configured as default pager"
    else
        warn "Git delta already configured as pager"
    fi
else
    warn "Git delta pager skipped (delta not installed)"
fi

# --- fzf Zsh integration ---
FZF_KEYBINDINGS="/usr/share/doc/fzf/examples/key-bindings.zsh"
if [[ -f "$FZF_KEYBINDINGS" ]]; then
    if ! grep -q 'fzf Integration' ~/.zshrc 2>/dev/null; then
        info "Adding fzf Zsh integration (Ctrl+T, Ctrl+R, Alt+C)..."
        cat >> ~/.zshrc << 'EOF'

# ─── fzf Integration ─────────────────────────────────────────────────────────
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
EOF
        success "fzf Zsh keybindings and completion enabled"
    else
        warn "fzf Zsh integration already configured"
    fi
else
    warn "fzf Zsh integration skipped (keybindings file not found)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 13. SHELL ALIASES FOR NEW TOOLS
# ═══════════════════════════════════════════════════════════════════════════
if ! grep -q '# ─── AI Dev Stack Aliases' ~/.zshrc 2>/dev/null; then
    info "Adding tool aliases to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── AI Dev Stack Aliases ──────────────────────────────────────────────────────
# Note: Some aliases shadow built-ins (ls, cat, df, top). Use \cmd for originals.
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --icons --level=2'
alias cat='bat --paging=never'
alias y='yazi'
alias zj='zellij'
alias mdv='glow'
alias mpvk='mpv --profile=sw-fast --vo=kitty --vo-kitty-use-shm=yes --really-quiet'
alias disk='ncdu'
alias df='duf'
alias top='btop'
alias yaml='yq'
EOF
fi

# ─── WSL2 Environment (persisted to modular env files) ───────────────────────
if $IS_WSL; then
    for _env_file in ~/.bashrc_env ~/.zshrc_env; do
        if [[ -f "$_env_file" ]] && ! grep -q 'KITTY_DISABLE_WAYLAND' "$_env_file"; then
            info "Adding KITTY_DISABLE_WAYLAND=1 to $_env_file..."
            cat >> "$_env_file" << 'WSLEOF'

# Kitty WSL2 Wayland workaround
export KITTY_DISABLE_WAYLAND=1
WSLEOF
            success "Updated $_env_file"
        fi
    done
    unset _env_file
fi

# --- p10k source line (must be last in .zshrc, after all other appends) ---
if $P10K_PRESET_APPLIED; then
    if ! grep -q 'source ~/.p10k.zsh' ~/.zshrc 2>/dev/null; then
        info "Adding p10k source line to end of .zshrc..."
        cat >> ~/.zshrc << 'EOF'

# ─── Powerlevel10k Config ─────────────────────────────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
        success "p10k source line added to .zshrc"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 14. GITHUB CLI (gh)
# ═══════════════════════════════════════════════════════════════════════════
info "Checking GitHub CLI (gh)..."
if ! command_exists gh; then
    info "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
    success "GitHub CLI installed: $(gh --version | head -1)"
else
    warn "GitHub CLI already installed: $(gh --version | head -1)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 15. HOMEBREW
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Homebrew..."
_brew_bin=""
[[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]] && _brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
[[ -z "$_brew_bin" && -x "$HOME/.linuxbrew/bin/brew" ]] && _brew_bin="$HOME/.linuxbrew/bin/brew"

if [[ -z "$_brew_bin" ]]; then
    info "Installing Homebrew (this may take a few minutes)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]] && _brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
    [[ -z "$_brew_bin" && -x "$HOME/.linuxbrew/bin/brew" ]] && _brew_bin="$HOME/.linuxbrew/bin/brew"
    if [[ -n "$_brew_bin" ]]; then
        success "Homebrew installed: $($_brew_bin --version)"
    else
        warn "Homebrew install may have failed — brew binary not found at expected paths"
    fi
else
    warn "Homebrew already installed: $($_brew_bin --version)"
fi

if [[ -n "$_brew_bin" ]] && ! grep -q 'brew shellenv' ~/.zshrc 2>/dev/null; then
    info "Adding Homebrew shellenv to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── Homebrew ──────────────────────────────────────────────────────────────────
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
EOF
    success "Homebrew shellenv added to .zshrc"
elif [[ -n "$_brew_bin" ]]; then
    warn "Homebrew already in .zshrc"
fi

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  AI Developer Essentials Stack - Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Installed components:"
echo "  - Zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font"
echo "  - Zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting"
echo "  - NVM + Node.js 22 LTS"
echo "  - Mamba + 'dev' environment (anthropic, openai, httpx, rich, typer, pydantic)"
echo "  - Kitty terminal (GPU-optimized, OLED theme, 4K ready)"
echo "  - Yazi file manager"
echo "  - CLI tools: ripgrep, fd, fzf, bat, eza, delta, glow, btop, ncdu, duf, httpie, yq, shellcheck, p7zip"
echo "  - Terminal media: ffmpeg, mpv, chafa"
echo "  - tmux (with optional AEO config)"
echo "  - Zellij terminal multiplexer"
echo "  - Bun JS runtime"
echo "  - direnv"
echo "  - GitHub CLI (gh)"
echo "  - Homebrew"
echo "  - Pop Shell (GNOME tiling - if GNOME detected)"
echo "  - Post-install config: Kitty default terminal, git delta, fzf integration"
echo ""
echo "Quick start commands:"
echo "  kitty          - Launch Kitty terminal"
echo "  yazi / y       - File manager"
echo "  zellij / zj    - Terminal multiplexer"
echo "  glow / mdv     - Render markdown in terminal"
echo "  mpvk video.mp4  - Play video in Kitty terminal"
echo "  mamba activate dev  - Activate AI dev environment"
echo "  btop / top     - Beautiful system monitor"
echo "  ncdu / disk    - Interactive disk usage"
echo "  duf / df       - Modern disk free"
echo "  yq / yaml      - YAML processor"
echo ""
echo -e "${YELLOW}NOTES:${NC}"
echo "  - Log out and back in (or run 'exec zsh') to apply all changes"
if $P10K_PRESET_APPLIED; then
    echo "  - AEO Powerlevel10k theme pre-configured (no wizard needed)"
else
    echo "  - On first Zsh launch, Powerlevel10k will run its configuration wizard"
fi
if $TMUX_CONFIG_APPLIED; then
    echo "  - AEO tmux config applied (C-Space prefix, 3-line status bar)"
fi
echo "  - Set your terminal font to 'MesloLGS NF' for proper icons"
echo ""
if $IS_WSL; then
    echo -e "${YELLOW}WSL2-SPECIFIC:${NC}"
    echo "  - KITTY_DISABLE_WAYLAND=1 set (prevents Wayland errors)"
    echo "  - Kitty configured with linux_display_server x11"
    echo "  - mesa-utils and dbus-x11 installed for GUI support"
    echo "  - D-Bus startup warnings from Kitty are harmless (no systemd in WSL)"
    echo "  - snap commands may require systemd (enable in /etc/wsl.conf if needed)"
    echo ""
fi
