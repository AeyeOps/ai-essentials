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
#   - herdr agent multiplexer (with AEO config, agent integrations, plugins)
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
# 1. AEO SHELL STACK (zsh + oh-my-zsh + Powerlevel10k + fonts + .zshenv)
# ═══════════════════════════════════════════════════════════════════════════
SHELL_STACK_APPLIED=false
P10K_PRESET_APPLIED=false
FONT_DIR="$HOME/.local/share/fonts"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
P10K_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
P10K_PRESET_SRC="$SCRIPT_DIR/../configs/zsh/p10k-aeo.zsh"
ZSHENV_SRC="$SCRIPT_DIR/../configs/zsh/zshenv"
ZSHENV_DEST="$HOME/.zshenv"

# Pre-check: silently skip the bundle when everything is already in place.
_shell_stack_ready=true
command_exists zsh || _shell_stack_ready=false
[[ -d "$HOME/.oh-my-zsh" ]] || _shell_stack_ready=false
[[ -d "$P10K_DIR" ]] || _shell_stack_ready=false
[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || _shell_stack_ready=false
[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || _shell_stack_ready=false
ls "$FONT_DIR"/MesloLGS* &>/dev/null || _shell_stack_ready=false
[[ -f "$HOME/.p10k.zsh" ]] || _shell_stack_ready=false
grep -q 'Enable Powerlevel10k instant prompt' ~/.zshrc 2>/dev/null || _shell_stack_ready=false
grep -q 'oh-my-zsh\.sh' ~/.zshrc 2>/dev/null || _shell_stack_ready=false
[[ -f "$ZSHENV_DEST" ]] || _shell_stack_ready=false
grep -q 'NVM_DIR' "$ZSHENV_DEST" 2>/dev/null || _shell_stack_ready=false
grep -q 'BUN_INSTALL' "$ZSHENV_DEST" 2>/dev/null || _shell_stack_ready=false

if $_shell_stack_ready; then
    warn "AEO Shell stack already installed and configured"
    SHELL_STACK_APPLIED=true
    P10K_PRESET_APPLIED=true
else
    echo ""
    echo -e "${BLUE}AEO Shell Stack${NC}"
    echo "  Installs: zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font"
    echo "  Plugins: zsh-autosuggestions, zsh-syntax-highlighting"
    echo "  Config:  AEO p10k preset, ~/.zshenv (NVM + Bun env exports)"
    echo ""
    read -r -p "Install AEO Shell stack? [Y/n] " shell_stack_answer || shell_stack_answer="n"
    if [[ "${shell_stack_answer,,}" != "n" ]]; then
        # ── MesloLGS Nerd Font ──
        info "Checking Nerd Fonts (MesloLGS NF)..."
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

        # ── zsh ──
        info "Checking Zsh..."
        if ! command_exists zsh; then
            info "Installing Zsh..."
            sudo apt-get install -y zsh
            success "Zsh installed"
        else
            warn "Zsh already installed: $(zsh --version)"
        fi

        # ── Oh-My-Zsh ──
        info "Checking Oh-My-Zsh..."
        if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
            info "Installing Oh-My-Zsh..."
            RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"  # silent: output piped to sh
            success "Oh-My-Zsh installed"
        else
            warn "Oh-My-Zsh already installed"
        fi

        # ── Powerlevel10k ──
        info "Checking Powerlevel10k..."
        if [[ ! -d "$P10K_DIR" ]]; then
            info "Installing Powerlevel10k..."
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
            success "Powerlevel10k installed"
        else
            warn "Powerlevel10k already installed"
        fi

        # ── zsh plugins ──
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

        # ── chsh to zsh ──
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

        # ── .zshrc oh-my-zsh wiring (theme + plugins + source) ──
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

        # ── AEO Powerlevel10k preset ──
        _p10k_mutated=false
        if [[ -f "$P10K_PRESET_SRC" ]]; then
            if [[ ! -f "$HOME/.p10k.zsh" ]]; then
                cp "$P10K_PRESET_SRC" "$HOME/.p10k.zsh"
                success "Copied AEO p10k preset → ~/.p10k.zsh"
                _p10k_mutated=true
            else
                warn "$HOME/.p10k.zsh already exists (keeping existing config)"
            fi

            if ! grep -q 'Enable Powerlevel10k instant prompt' ~/.zshrc 2>/dev/null; then
                info "Adding Powerlevel10k instant prompt to top of .zshrc..."
                # shellcheck disable=SC2016
                INSTANT_PROMPT_BLOCK='# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
'
                _tmpfile=$(mktemp)
                printf '%s' "$INSTANT_PROMPT_BLOCK" | cat - ~/.zshrc > "$_tmpfile"
                chmod --reference="$HOME/.zshrc" "$_tmpfile"
                mv "$_tmpfile" ~/.zshrc
                success "Instant prompt block added to top of .zshrc"
                _p10k_mutated=true
            fi

            P10K_PRESET_APPLIED=true
            if $_p10k_mutated; then
                success "AEO Powerlevel10k theme preset applied"
            fi
        fi

        # ── ~/.zshenv (NVM + Bun env exports) ──
        if [[ -f "$ZSHENV_SRC" ]]; then
            if [[ ! -f "$ZSHENV_DEST" ]]; then
                cp "$ZSHENV_SRC" "$ZSHENV_DEST"
                success "Deployed AEO ~/.zshenv (NVM + Bun env exports)"
            else
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
                fi
            fi
        else
            warn "configs/zsh/zshenv not found — skipping .zshenv deployment"
        fi

        SHELL_STACK_APPLIED=true
        success "AEO Shell stack installed"
    else
        info "Skipped AEO Shell stack"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 2. AEO TMUX + CONFIG (install/upgrade tmux + deploy AEO config)
# ═══════════════════════════════════════════════════════════════════════════
TMUX_INSTALLED=false
TMUX_CONFIG_APPLIED=false
TMUX_CONFIG_SRC="$SCRIPT_DIR/../configs/tmux"
TMUX_DEST="$HOME/.config/tmux"

_tmux_md5_match() {
    local src="$1" dst="$2"
    [[ -f "$src" && -f "$dst" ]] || return 1
    [[ "$(md5sum "$src" | awk '{print $1}')" == "$(md5sum "$dst" | awk '{print $1}')" ]]
}

# Pre-check: silently skip when tmux is installed, no apt upgrade pending,
# tmux.conf md5 matches the repo, and every repo script has a matching deployed md5.
_tmux_bundle_ready=true
command_exists tmux || _tmux_bundle_ready=false
if $_tmux_bundle_ready && apt list --upgradable 2>/dev/null | grep -q '^tmux/'; then
    _tmux_bundle_ready=false
fi
if $_tmux_bundle_ready && [[ -f "$TMUX_CONFIG_SRC/tmux.conf" ]]; then
    _tmux_md5_match "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf" \
        || _tmux_bundle_ready=false
fi
if $_tmux_bundle_ready && [[ -d "$TMUX_CONFIG_SRC/scripts" ]]; then
    while IFS= read -r -d '' _src; do
        _dst="$TMUX_DEST/scripts/$(basename "$_src")"
        if ! _tmux_md5_match "$_src" "$_dst"; then
            _tmux_bundle_ready=false
            break
        fi
    done < <(find "$TMUX_CONFIG_SRC/scripts" -type f -print0)
fi

if $_tmux_bundle_ready; then
    warn "AEO tmux + config already installed and up to date"
    TMUX_INSTALLED=true
    TMUX_CONFIG_APPLIED=true
else
    echo ""
    echo -e "${BLUE}AEO Tmux + Config${NC}"
    echo "  Installs/upgrades tmux and deploys the AEO config:"
    echo "  C-Space prefix (avoids Claude Code Ctrl+b conflict), true color,"
    echo "  vi copy mode, OSC 52 clipboard, 3-line keyboard reference bar,"
    echo "  plus tmux/scripts/."
    if [[ -f "$TMUX_DEST/tmux.conf" ]] || [[ -f "$HOME/.tmux.conf" ]]; then
        echo ""
        echo -e "${YELLOW}  WARNING: This will REPLACE your existing tmux config (backup will be made).${NC}"
    fi
    echo ""
    read -r -p "Install AEO tmux + config? [y/N] " tmux_answer || tmux_answer="n"
    if [[ "${tmux_answer,,}" == "y" ]]; then
        # Install or upgrade tmux
        if ! command_exists tmux; then
            info "Installing tmux..."
            sudo apt-get install -y tmux
            success "tmux installed"
        else
            TMUX_CURRENT="$(tmux -V)"
            warn "tmux already installed: $TMUX_CURRENT"
            if apt list --upgradable 2>/dev/null | grep -q '^tmux/'; then
                info "Upgrading tmux..."
                sudo apt-get install -y --only-upgrade tmux
                success "tmux upgraded: $(tmux -V)"
            fi
        fi
        TMUX_INSTALLED=true

        # Deploy AEO config
        if [[ -f "$TMUX_CONFIG_SRC/tmux.conf" ]]; then
            STAMP="$(date +%Y%m%d%H%M%S)"
            mkdir -p "$TMUX_DEST/scripts"
            if [[ -f "$TMUX_DEST/tmux.conf" ]] \
                && ! _tmux_md5_match "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf"; then
                cp "$TMUX_DEST/tmux.conf" "$TMUX_DEST/tmux.conf.bak.$STAMP"
                info "Backed up existing ~/.config/tmux/tmux.conf"
            fi
            if [[ -f "$HOME/.tmux.conf" ]]; then
                cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak.$STAMP"
                info "Backed up existing ~/.tmux.conf"
            fi
            cp "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf"
            if [[ -d "$TMUX_CONFIG_SRC/scripts" ]]; then
                cp "$TMUX_CONFIG_SRC/scripts/"* "$TMUX_DEST/scripts/"
                chmod +x "$TMUX_DEST/scripts/"*.sh 2>/dev/null || true
            fi
            TMUX_CONFIG_APPLIED=true
            success "AEO tmux config deployed -> ~/.config/tmux/"
        fi
    else
        info "Skipped AEO tmux + config"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 2b. AEO GHOSTTY SESSION LAUNCHER (transparent tmux + decoration fix)
# ═══════════════════════════════════════════════════════════════════════════
GHOSTTY_LAUNCHER_DEPLOYED=false
GHOSTTY_SRC="$SCRIPT_DIR/../configs/ghostty"
GHOSTTY_DEST="$HOME/.config/ghostty"
GHOSTTY_MODE_MARKER="$GHOSTTY_DEST/.aeo-launcher-mode"

# The launcher runs under its own shebang, so we deploy ONE binary named
# ghostty-tmux-launch (the zsh variant if zsh is present, else the bash port);
# both rc guards exec that path. The per-shell choice only affects the rc snippet.
if command_exists zsh; then
    GHOSTTY_LAUNCHER_SRC="$GHOSTTY_SRC/ghostty-tmux-launch"
else
    GHOSTTY_LAUNCHER_SRC="$GHOSTTY_SRC/ghostty-tmux-launch.bash"
fi

_gt_md5() { [[ -f "$1" ]] && md5sum "$1" | awk '{print $1}'; }
_gt_md5_match() {
    local a b
    a="$(_gt_md5 "$1")"; b="$(_gt_md5 "$2")"
    [[ -n "$a" && "$a" == "$b" ]]
}

# Desktop decoration detection. Plasma/KWin can avoid Ghostty's GTK CSD frame
# offset with server-side decorations, preserving resize handles instead of
# removing every border. Tiling WMs without usable server-side decoration support
# keep the old borderless fallback.
_gt_is_plasma_kwin() {
    local hay
    hay="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}"
    case "${hay,,}" in
        *kde*|*plasma*) return 0 ;;
    esac
    pgrep -x kwin_wayland >/dev/null 2>&1 && return 0
    pgrep -x kwin_x11 >/dev/null 2>&1 && return 0
    return 1
}

_gt_is_tiling_wm() {
    local hay p
    hay="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}"
    case "${hay,,}" in
        *sway*|*hyprland*|*i3*|*wayfire*|*river*|*bspwm*|*qtile*|*dwm*|*xmonad*)
            return 0 ;;
    esac
    [[ -n "${SWAYSOCK:-}" || -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" || -n "${I3SOCK:-}" ]] && return 0
    for p in sway Hyprland i3 bspwm river wayfire qtile dwm xmonad; do
        pgrep -x "$p" >/dev/null 2>&1 && return 0
    done
    return 1
}

# Resolve an fzf >= 0.45 (the launcher's conditional Tab needs fzf's `transform`
# action, added in 0.45; apt ships 0.44.1). Sets GT_FZF_PATH. Installs the latest
# release to /usr/local/bin only when no new-enough fzf is found.
GT_FZF_PATH=""
_gt_resolve_fzf() {
    local cand ver maj min url
    for cand in "$(command -v fzf 2>/dev/null || true)" /usr/local/bin/fzf; do
        [[ -x "$cand" ]] || continue
        ver="$("$cand" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+')"
        maj="${ver%%.*}"; min="${ver#*.}"
        if (( ${maj:-0} > 0 || ${min:-0} >= 45 )); then
            GT_FZF_PATH="$cand"; return 0
        fi
    done
    info "Installing fzf >= 0.45 from GitHub (apt's fzf is too old for the launcher's conditional Tab)..."
    url="$(curl --max-time 30 https://api.github.com/repos/junegunn/fzf/releases/latest \
        | grep -oP '"browser_download_url":\s*"\K[^"]+linux_'"$ARCH_DEB"'\.tar\.gz' | head -n1)"
    if [[ -n "$url" ]]; then
        curl -fSL "$url" -o /tmp/fzf.tar.gz
        sudo tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin/ fzf
        rm -f /tmp/fzf.tar.gz
        GT_FZF_PATH="/usr/local/bin/fzf"
        success "fzf $("$GT_FZF_PATH" --version | awk '{print $1}') installed -> /usr/local/bin/fzf"
        return 0
    fi
    warn "Could not fetch a newer fzf; conditional Tab degrades to plain Tab"
    GT_FZF_PATH="fzf"
}

# Echo one marker-fenced block (guard|integration) from an rc snippet, with
# @FZF_PATH@ substituted for the resolved fzf path.
_gt_extract_block() {
    local snip="$1" kind="$2" fzf="$3" s e
    if [[ "$kind" == "guard" ]]; then
        s='# >>> aeo ghostty session launcher (guard) >>>'
        e='# <<< aeo ghostty session launcher (guard) <<<'
    else
        s='# >>> aeo ghostty shell integration >>>'
        e='# <<< aeo ghostty shell integration <<<'
    fi
    awk -v s="$s" -v e="$e" 'index($0,s){f=1} f{print} index($0,e){f=0}' "$snip" \
        | sed "s|@FZF_PATH@|$fzf|g"
}

# Prepend the guard block to the top of an rc file (it execs, so it must run
# above the p10k instant-prompt block) and append the integration block to the
# end. Both are idempotent on their marker comments.
_gt_apply_rc() {
    local rc="$1" snip="$2" fzf="$3" tmp
    if ! grep -qF 'aeo ghostty session launcher (guard)' "$rc" 2>/dev/null; then
        tmp="$(mktemp)"
        { _gt_extract_block "$snip" guard "$fzf"; echo ""; cat "$rc" 2>/dev/null || true; } > "$tmp"
        cat "$tmp" > "$rc"
        rm -f "$tmp"
        info "Added Ghostty launcher guard to $(basename "$rc")"
    fi
    if ! grep -qF 'aeo ghostty shell integration' "$rc" 2>/dev/null; then
        { echo ""; _gt_extract_block "$snip" integration "$fzf"; } >> "$rc"
        info "Added Ghostty shell integration to $(basename "$rc")"
    fi
}

# Apply rc blocks to every detected rc file (.zshrc uses the zsh snippet, .bashrc
# the bash snippet). If neither exists, create the one matching the user's shell.
_gt_deploy_rc_all() {
    local fzf="$1" did=false
    if [[ -f "$HOME/.zshrc" ]]; then
        _gt_apply_rc "$HOME/.zshrc" "$GHOSTTY_SRC/rc-snippet.zsh" "$fzf"; did=true
    fi
    if [[ -f "$HOME/.bashrc" ]]; then
        _gt_apply_rc "$HOME/.bashrc" "$GHOSTTY_SRC/rc-snippet.bash" "$fzf"; did=true
    fi
    if ! $did; then
        if command_exists zsh; then
            touch "$HOME/.zshrc"
            _gt_apply_rc "$HOME/.zshrc" "$GHOSTTY_SRC/rc-snippet.zsh" "$fzf"
        else
            touch "$HOME/.bashrc"
            _gt_apply_rc "$HOME/.bashrc" "$GHOSTTY_SRC/rc-snippet.bash" "$fzf"
        fi
    fi
}

# Deploy the launcher binary + aeo-launcher.conf, enabling the least-invasive
# decoration fix for the detected desktop.
_gt_deploy_assets() {
    mkdir -p "$GHOSTTY_DEST"
    cp "$GHOSTTY_LAUNCHER_SRC" "$GHOSTTY_DEST/ghostty-tmux-launch"
    chmod +x "$GHOSTTY_DEST/ghostty-tmux-launch"
    cp "$GHOSTTY_SRC/aeo-launcher.conf" "$GHOSTTY_DEST/aeo-launcher.conf"
    if _gt_is_plasma_kwin; then
        sed -i '0,/^# *window-decoration = server/s|^# *window-decoration = server.*|window-decoration = server|' "$GHOSTTY_DEST/aeo-launcher.conf"
        sed -i '0,/^# *gtk-titlebar = false/s|^# *gtk-titlebar = false.*|gtk-titlebar = false|' "$GHOSTTY_DEST/aeo-launcher.conf"
        info "Plasma/KWin detected -> enabled window-decoration = server and gtk-titlebar = false"
    elif _gt_is_tiling_wm; then
        sed -i '0,/^# *window-decoration = none/s|^# *window-decoration = none.*|window-decoration = none|' "$GHOSTTY_DEST/aeo-launcher.conf"
        info "Tiling WM detected -> enabled borderless window-decoration = none fallback"
    else
        info "No decoration workaround needed -> Ghostty decoration settings left commented"
    fi
}

# The config file is version-checked, but desktop decoration needs are host-local:
# reusing a home directory on a different Plasma/KWin instance must re-enable the
# server-side decoration fix even when the launcher files are otherwise current.
_gt_decoration_state_matches() {
    local conf="$GHOSTTY_DEST/aeo-launcher.conf"
    [[ -f "$conf" ]] || return 1
    if _gt_is_plasma_kwin; then
        grep -Eq '^[[:space:]]*window-decoration[[:space:]]*=[[:space:]]*server[[:space:]]*$' "$conf" \
            && grep -Eq '^[[:space:]]*gtk-titlebar[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$conf"
    elif _gt_is_tiling_wm; then
        grep -Eq '^[[:space:]]*window-decoration[[:space:]]*=[[:space:]]*none[[:space:]]*$' "$conf"
    else
        ! grep -Eq '^[[:space:]]*window-decoration[[:space:]]*=' "$conf" \
            && ! grep -Eq '^[[:space:]]*gtk-titlebar[[:space:]]*=' "$conf"
    fi
}

# Append the 3 Ghostty terminfo/title lines to the active user tmux config when
# missing (Full deploys the AEO tmux.conf, which already carries them).
_gt_append_tmux_lines() {
    local tcfg=""
    if [[ -f "$HOME/.config/tmux/tmux.conf" ]]; then tcfg="$HOME/.config/tmux/tmux.conf"
    elif [[ -f "$HOME/.tmux.conf" ]]; then tcfg="$HOME/.tmux.conf"
    else
        mkdir -p "$HOME/.config/tmux"; tcfg="$HOME/.config/tmux/tmux.conf"; : > "$tcfg"
    fi
    if ! grep -qF 'terminal-features ",xterm-ghostty:RGB"' "$tcfg"; then
        cat >> "$tcfg" << 'EOF'

# Ghostty terminfo + title forwarding (for the Ghostty session launcher)
set -as terminal-features ",xterm-ghostty:RGB"
set -as terminal-features ",xterm-ghostty:hyperlinks"
set -g  set-titles on
EOF
        info "Added Ghostty terminfo/title lines to $(basename "$tcfg")"
    fi
}

# Guard against a silently-broken include (Ghostty fails config soft).
_gt_validate() {
    command_exists ghostty || return 0
    if ghostty +validate-config >/tmp/gt-validate.out 2>&1; then
        success "ghostty +validate-config: config is valid"
    else
        warn "ghostty +validate-config reported issues:"
        sed 's/^/    /' /tmp/gt-validate.out || true
    fi
    rm -f /tmp/gt-validate.out
}

# Option A — additive: keep the user's config, add a `config-file` include.
_gt_install_integrate() {
    _gt_resolve_fzf
    _gt_deploy_assets
    local cfg="$GHOSTTY_DEST/config"
    [[ -f "$cfg" ]] || { : > "$cfg"; info "Created minimal ~/.config/ghostty/config"; }
    if ! grep -qF 'config-file = aeo-launcher.conf' "$cfg"; then
        printf '\n# AEO Ghostty session launcher (native-split keybinds + decoration fix)\nconfig-file = aeo-launcher.conf\n' >> "$cfg"
        info "Added 'config-file = aeo-launcher.conf' to your Ghostty config"
    fi
    _gt_append_tmux_lines
    _gt_deploy_rc_all "$GT_FZF_PATH"
    echo "integrate" > "$GHOSTTY_MODE_MARKER"
    _gt_validate
    GHOSTTY_LAUNCHER_DEPLOYED=true
    success "AEO Ghostty launcher installed (Integrate) -> ~/.config/ghostty/"
}

# Option B — opinionated: REPLACE the Ghostty + tmux configs. Pre-confirm screen
# names every replaced file, its backup, and the one-command rollback BEFORE any
# write; timestamped backups; a generated restore-<stamp>.sh undoes it all.
_gt_install_full() {
    STAMP="$(date +%Y%m%d%H%M%S)"
    local cfg="$GHOSTTY_DEST/config"
    local restore="$GHOSTTY_DEST/restore-$STAMP.sh"
    mkdir -p "$GHOSTTY_DEST"

    echo ""
    echo -e "${YELLOW}  Full AEO will REPLACE these files (timestamped backup of each first):${NC}"
    [[ -f "$cfg" ]]                         && echo "    ~/.config/ghostty/config     -> ~/.config/ghostty/config.bak.$STAMP"
    [[ -f "$HOME/.config/tmux/tmux.conf" ]] && echo "    ~/.config/tmux/tmux.conf     -> ~/.config/tmux/tmux.conf.bak.$STAMP"
    [[ -f "$HOME/.tmux.conf" ]]             && echo "    ~/.tmux.conf                 -> ~/.tmux.conf.bak.$STAMP"
    echo "  Also deploys: ghostty-tmux-launch, aeo-launcher.conf, the AEO tmux"
    echo "  scripts, and rc guard/integration blocks in ~/.zshrc and ~/.bashrc."
    echo ""
    echo -e "${YELLOW}  One-command rollback (generated at install time):${NC}"
    echo "    bash ${restore/#$HOME/~}"
    echo ""
    read -r -p "  Proceed with Full AEO? [y/N] " gt_full || gt_full="n"
    if [[ "${gt_full,,}" != "y" ]]; then
        info "Skipped AEO Ghostty launcher (Full)"
        return 0
    fi

    _gt_resolve_fzf

    local _gt_restore_lines=""
    _gt_backup() {
        [[ -f "$1" ]] || return 0
        cp "$1" "$1.bak.$STAMP"
        _gt_restore_lines+="cp -f \"$1.bak.$STAMP\" \"$1\""$'\n'
        info "Backed up $(basename "$1")"
    }
    _gt_backup "$cfg"
    _gt_backup "$HOME/.config/tmux/tmux.conf"
    _gt_backup "$HOME/.tmux.conf"

    cp "$GHOSTTY_SRC/config.full" "$cfg"
    _gt_deploy_assets

    if [[ -f "$TMUX_CONFIG_SRC/tmux.conf" ]]; then
        mkdir -p "$TMUX_DEST/scripts"
        cp "$TMUX_CONFIG_SRC/tmux.conf" "$TMUX_DEST/tmux.conf"
        if [[ -d "$TMUX_CONFIG_SRC/scripts" ]]; then
            cp "$TMUX_CONFIG_SRC/scripts/"* "$TMUX_DEST/scripts/"
            chmod +x "$TMUX_DEST/scripts/"*.sh 2>/dev/null || true
        fi
        info "Deployed AEO tmux config -> ~/.config/tmux/"
    fi

    _gt_deploy_rc_all "$GT_FZF_PATH"
    echo "full" > "$GHOSTTY_MODE_MARKER"

    cat > "$restore" <<EOF
#!/usr/bin/env bash
# AEO Ghostty 'Full' install rollback ($STAMP). Restores the replaced files and
# strips the rc launcher blocks. Generated by setup-ai-dev-stack.sh.
set -uo pipefail
echo "Rolling back AEO Ghostty 'Full' install ($STAMP)..."
$_gt_restore_lines
for rc in "\$HOME/.zshrc" "\$HOME/.bashrc"; do
  [[ -f "\$rc" ]] || continue
  sed -i '/# >>> aeo ghostty session launcher (guard) >>>/,/# <<< aeo ghostty session launcher (guard) <<</d' "\$rc"
  sed -i '/# >>> aeo ghostty shell integration >>>/,/# <<< aeo ghostty shell integration <<</d' "\$rc"
done
rm -f "$GHOSTTY_MODE_MARKER"
echo "Rollback complete. Open a new shell (or 'exec \$SHELL') to apply."
EOF
    chmod +x "$restore"

    _gt_validate
    GHOSTTY_LAUNCHER_DEPLOYED=true
    success "AEO Ghostty launcher installed (Full AEO) -> ~/.config/ghostty/"
    info "Rollback any time: bash ${restore/#$HOME/~}"
}

# Pre-check: silently skip when the recorded mode is already fully deployed
# (launcher md5 matches, conf present, Full's config matches, rc guards present).
# aeo-launcher.conf is version-checked instead of md5-checked — desktop-specific
# decoration toggles legitimately change its hash after deployment.
_gt_ready=false
if [[ -f "$GHOSTTY_MODE_MARKER" ]]; then
    _gt_mode="$(cat "$GHOSTTY_MODE_MARKER" 2>/dev/null || true)"
    _gt_ready=true
    _gt_md5_match "$GHOSTTY_LAUNCHER_SRC" "$GHOSTTY_DEST/ghostty-tmux-launch" || _gt_ready=false
    [[ -f "$GHOSTTY_DEST/aeo-launcher.conf" ]] || _gt_ready=false
    _gt_conf_version="$(grep -m1 '^# AEO_GHOSTTY_LAUNCHER_CONF_VERSION=' "$GHOSTTY_SRC/aeo-launcher.conf" 2>/dev/null || true)"
    [[ -n "$_gt_conf_version" ]] || _gt_ready=false
    grep -qF "$_gt_conf_version" "$GHOSTTY_DEST/aeo-launcher.conf" 2>/dev/null || _gt_ready=false
    _gt_decoration_state_matches || _gt_ready=false
    if [[ "$_gt_mode" == "full" ]]; then
        _gt_md5_match "$GHOSTTY_SRC/config.full" "$GHOSTTY_DEST/config" || _gt_ready=false
    fi
    if $_gt_ready; then
        for _rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
            [[ -f "$_rc" ]] || continue
            grep -qF 'aeo ghostty session launcher (guard)' "$_rc" || { _gt_ready=false; break; }
        done
    fi
fi

if $_gt_ready; then
    warn "AEO Ghostty launcher already installed ($_gt_mode mode) and up to date"
    GHOSTTY_LAUNCHER_DEPLOYED=true
else
    echo ""
    echo -e "${BLUE}AEO Ghostty Session Launcher${NC}"
    echo "  Transparent tmux under Ghostty: every window/tab/native split lands in"
    echo "  its own recoverable tmux session via one fzf screen (name it, Tab-pull"
    echo "  detached sessions in as panes). Includes a desktop-specific decoration fix."
    if ! command_exists ghostty; then
        echo ""
        echo -e "${YELLOW}  NOTE: Ghostty is not installed — the launcher stays dormant until it is.${NC}"
    fi
    echo ""
    echo "  Install options:"
    echo "    1) Integrate  - additive; keeps your config, adds a config-file include"
    echo "                    (overrides only alt+d, alt+shift+d, and, when needed,"
    echo "                    Ghostty decoration keys). Reversible by hand."
    echo "    2) Full AEO   - opinionated bundle; REPLACES your Ghostty + tmux configs"
    echo "                    (timestamped backups + one-command restore script)."
    echo "    s) Skip"
    echo ""
    read -r -p "  Choose [1/2/s]: " gt_choice || gt_choice="s"
    case "${gt_choice,,}" in
        1|integrate) _gt_install_integrate ;;
        2|full)      _gt_install_full ;;
        *)           info "Skipped AEO Ghostty launcher" ;;
    esac
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
# shellcheck source=/dev/null
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
# 7. AEO ZELLIJ + CONFIG (install zellij + plugins + AEO config)
# ═══════════════════════════════════════════════════════════════════════════
ZELLIJ_INSTALLED=false
ZELLIJ_CONFIG_APPLIED=false
ZELLIJ_CONFIG_SRC="$SCRIPT_DIR/../configs/zellij"
ZELLIJ_DEST="$HOME/.config/zellij"

_zellij_md5_match() {
    local src="$1" dst="$2"
    [[ -f "$src" && -f "$dst" ]] || return 1
    [[ "$(md5sum "$src" | awk '{print $1}')" == "$(md5sum "$dst" | awk '{print $1}')" ]]
}

# Pre-check: silently skip when zellij is installed, both wasms are deployed,
# zjwidth (when repo-side non-empty) md5-matches, and config + default layout md5-match.
_zellij_bundle_ready=true
command_exists zellij || _zellij_bundle_ready=false
[[ -s "$ZELLIJ_DEST/plugins/zjstatus.wasm" ]] || _zellij_bundle_ready=false
if $_zellij_bundle_ready && [[ -s "$ZELLIJ_CONFIG_SRC/plugins/zjwidth.wasm" ]]; then
    _zellij_md5_match "$ZELLIJ_CONFIG_SRC/plugins/zjwidth.wasm" "$ZELLIJ_DEST/plugins/zjwidth.wasm" \
        || _zellij_bundle_ready=false
fi
if $_zellij_bundle_ready && [[ -f "$ZELLIJ_CONFIG_SRC/config.kdl" ]]; then
    _zellij_md5_match "$ZELLIJ_CONFIG_SRC/config.kdl" "$ZELLIJ_DEST/config.kdl" \
        || _zellij_bundle_ready=false
fi
if $_zellij_bundle_ready && [[ -f "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" ]]; then
    _zellij_md5_match "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl" \
        || _zellij_bundle_ready=false
fi

if $_zellij_bundle_ready; then
    warn "AEO zellij + config already installed and up to date"
    ZELLIJ_INSTALLED=true
    ZELLIJ_CONFIG_APPLIED=true
else
    echo ""
    echo -e "${BLUE}AEO Zellij + Config${NC}"
    echo "  Installs zellij plus the AEO config:"
    echo "  p10k-aeo theme, custom keybinds (Alt+w SIGWINCH redraw, Alt+arrows nav,"
    echo "  Alt+p pane group), powerline Alt-key status row via zjstatus + zjwidth wasm plugins."
    if [[ -f "$ZELLIJ_DEST/config.kdl" ]] || [[ -f "$ZELLIJ_DEST/layouts/default.kdl" ]]; then
        echo ""
        echo -e "${YELLOW}  WARNING: This will REPLACE your existing zellij config (backup will be made).${NC}"
    fi
    echo ""
    read -r -p "Install AEO zellij + config? [y/N] " zellij_answer || zellij_answer="n"
    if [[ "${zellij_answer,,}" == "y" ]]; then
        # Install zellij if missing
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
            success "Zellij installed"
        else
            warn "Zellij already installed"
        fi
        ZELLIJ_INSTALLED=true

        if command_exists zellij; then
            mkdir -p "$ZELLIJ_DEST/plugins" "$ZELLIJ_DEST/layouts"

            # zjstatus (download from upstream; only re-download if missing/empty)
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

            # zjwidth (from repo; only deploy when repo-side wasm is non-empty)
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

            # Pre-seed zellij plugin permissions so users don't get prompted on first
            # session for AEO-deployed plugins. Idempotently merges into permissions.kdl;
            # preserves any existing grants for other plugins.
            if command_exists python3; then
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

            # Deploy AEO config + default layout
            if [[ -f "$ZELLIJ_CONFIG_SRC/config.kdl" ]]; then
                STAMP="$(date +%Y%m%d%H%M%S)"
                if [[ -f "$ZELLIJ_DEST/config.kdl" ]] \
                    && ! _zellij_md5_match "$ZELLIJ_CONFIG_SRC/config.kdl" "$ZELLIJ_DEST/config.kdl"; then
                    cp "$ZELLIJ_DEST/config.kdl" "$ZELLIJ_DEST/config.kdl.bak.$STAMP"
                    info "Backed up existing ~/.config/zellij/config.kdl"
                fi
                if [[ -f "$ZELLIJ_DEST/layouts/default.kdl" ]] \
                    && ! _zellij_md5_match "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl"; then
                    cp "$ZELLIJ_DEST/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl.bak.$STAMP"
                    info "Backed up existing ~/.config/zellij/layouts/default.kdl"
                fi
                cp "$ZELLIJ_CONFIG_SRC/config.kdl" "$ZELLIJ_DEST/config.kdl"
                cp "$ZELLIJ_CONFIG_SRC/layouts/default.kdl" "$ZELLIJ_DEST/layouts/default.kdl"
                ZELLIJ_CONFIG_APPLIED=true
                success "AEO zellij config deployed -> ~/.config/zellij/"
            fi
        fi
    else
        info "Skipped AEO zellij + config"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 7b. AEO HERDR + CONFIG (agent multiplexer + integrations + plugins)
# ═══════════════════════════════════════════════════════════════════════════
HERDR_INSTALLED=false
HERDR_CONFIG_APPLIED=false
HERDR_CONFIG_SRC="$SCRIPT_DIR/../configs/herdr"
HERDR_DEST="$HOME/.config/herdr"
HERDR_ZSH_COMPDIR="$HOME/.zsh/completions"

_herdr_md5_match() {
    local src="$1" dst="$2"
    [[ -f "$src" && -f "$dst" ]] || return 1
    [[ "$(md5sum "$src" | awk '{print $1}')" == "$(md5sum "$dst" | awk '{print $1}')" ]]
}

# Pre-check: silently skip when herdr is installed, config.toml md5-matches,
# completions + zshenv DISPLAY block are deployed, the agent skill is present,
# and the expected plugins are installed (Rust-built ones only when cargo exists).
_herdr_bundle_ready=true
command_exists herdr || _herdr_bundle_ready=false
if $_herdr_bundle_ready && [[ -f "$HERDR_CONFIG_SRC/config.toml" ]]; then
    _herdr_md5_match "$HERDR_CONFIG_SRC/config.toml" "$HERDR_DEST/config.toml" \
        || _herdr_bundle_ready=false
fi
if $_herdr_bundle_ready && command_exists zsh; then
    [[ -s "$HERDR_ZSH_COMPDIR/_herdr" ]] || _herdr_bundle_ready=false
    if [[ -f "$HERDR_CONFIG_SRC/zshenv-display-snippet.zsh" ]]; then
        grep -qF 'aeo herdr display' "$HOME/.zshenv" 2>/dev/null || _herdr_bundle_ready=false
    fi
fi
if $_herdr_bundle_ready && command_exists npx; then
    [[ -d "$HOME/.agents/skills/herdr" ]] || _herdr_bundle_ready=false
fi
if $_herdr_bundle_ready; then
    [[ -d "$HERDR_DEST/plugins/config/cloudmanic.herdr-plus" ]] || _herdr_bundle_ready=false
fi
if $_herdr_bundle_ready && command_exists cargo; then
    [[ -d "$HERDR_DEST/plugins/config/herdr-file-viewer" ]] || _herdr_bundle_ready=false
    [[ -d "$HERDR_DEST/plugins/config/herdr-spreader" ]] || _herdr_bundle_ready=false
fi

if $_herdr_bundle_ready; then
    warn "AEO herdr + config already installed and up to date"
    HERDR_INSTALLED=true
    HERDR_CONFIG_APPLIED=true
else
    echo ""
    echo -e "${BLUE}AEO Herdr + Config${NC}"
    echo "  Installs herdr (agent multiplexer, herdr.dev) plus the AEO config:"
    echo "  ctrl+a prefix (clears tmux ctrl+b and AEO tmux C-Space), tokyo-night on"
    echo "  pure-black panels, system toasts, session/pane persistence across"
    echo "  restarts. Also: agent integrations (for agent CLIs present on this"
    echo "  machine), the herdr agent skill, plugins (herdr-plus, file-viewer,"
    echo "  spreader), zsh/bash completions, and a DISPLAY fallback for GUI tools"
    echo "  inside panes. Never run tmux/zellij INSIDE a herdr pane (breaks agent"
    echo "  state detection); herdr inside tmux is fine."
    if [[ -f "$HERDR_DEST/config.toml" ]]; then
        echo ""
        echo -e "${YELLOW}  WARNING: This will REPLACE your existing herdr config (backup will be made).${NC}"
    fi
    echo ""
    read -r -p "Install AEO herdr + config? [y/N] " herdr_answer || herdr_answer="n"
    if [[ "${herdr_answer,,}" == "y" ]]; then
        # Install herdr if missing (official installer detects OS/arch itself)
        if ! command_exists herdr; then
            info "Installing herdr..."
            curl -fsSL https://herdr.dev/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
            command_exists herdr || error "herdr installer finished but 'herdr' is not on PATH"
            success "herdr installed: $(herdr --version)"
        else
            warn "herdr already installed: $(herdr --version)"
        fi
        HERDR_INSTALLED=true

        # Deploy AEO config (timestamped backup on change)
        if [[ -f "$HERDR_CONFIG_SRC/config.toml" ]]; then
            mkdir -p "$HERDR_DEST"
            if [[ -f "$HERDR_DEST/config.toml" ]] \
                && ! _herdr_md5_match "$HERDR_CONFIG_SRC/config.toml" "$HERDR_DEST/config.toml"; then
                cp "$HERDR_DEST/config.toml" "$HERDR_DEST/config.toml.bak.$(date +%Y%m%d%H%M%S)"
                info "Backed up existing ~/.config/herdr/config.toml"
            fi
            cp "$HERDR_CONFIG_SRC/config.toml" "$HERDR_DEST/config.toml"
            HERDR_CONFIG_APPLIED=true
            success "AEO herdr config deployed -> ~/.config/herdr/"
            if herdr status server 2>/dev/null | grep -q 'status: running'; then
                herdr server reload-config >/dev/null 2>&1 || true
                info "Reloaded config into the running herdr server"
            fi
        fi

        # Agent integrations. Hooks embed absolute machine-local paths (e.g. in
        # ~/.claude/settings.json), so integrations install per machine and only
        # for agent CLIs actually present — never sync those files across hosts.
        for _agent in claude pi codex opencode; do
            if command_exists "$_agent"; then
                if herdr integration install "$_agent" >/dev/null 2>&1; then
                    success "herdr $_agent integration installed"
                else
                    warn "herdr $_agent integration failed (herdr integration install $_agent)"
                fi
            else
                warn "herdr $_agent integration skipped ($_agent not installed)"
            fi
        done
        unset _agent

        # Herdr agent skill: lets agents drive herdr panes via its socket API.
        # Self-gates on HERDR_ENV=1 (set by herdr in its panes) — inert elsewhere.
        if command_exists npx; then
            if [[ -d "$HOME/.agents/skills/herdr" ]]; then
                warn "herdr agent skill already installed"
            elif npx -y skills add ogulcancelik/herdr --skill herdr -g >/dev/null 2>&1; then
                success "herdr agent skill installed -> ~/.agents/skills/herdr"
            else
                warn "herdr agent skill install failed (npx -y skills add ogulcancelik/herdr --skill herdr -g)"
            fi
        else
            warn "herdr agent skill skipped (npx not available)"
        fi

        # Plugins: herdr-plus ships a prebuilt binary; file-viewer and spreader
        # build from source and need a Rust toolchain (file-viewer: rustc >= 1.96).
        _herdr_plugin_install() {
            local repo="$1" id="$2"
            if [[ -d "$HERDR_DEST/plugins/config/$id" ]]; then
                warn "herdr plugin $id already installed"
            elif herdr plugin install "$repo" --yes >/dev/null 2>&1; then
                success "herdr plugin installed: $id"
            else
                warn "herdr plugin $id failed (herdr plugin install $repo --yes)"
            fi
        }
        _herdr_plugin_install cloudmanic/herdr-plus cloudmanic.herdr-plus
        if command_exists cargo; then
            _herdr_plugin_install smarzban/herdr-file-viewer herdr-file-viewer
            _herdr_plugin_install yuk1ty/herdr-spreader herdr-spreader
        else
            warn "herdr plugins file-viewer/spreader skipped (need a Rust toolchain: https://rustup.rs)"
        fi

        # Zsh completions. fpath must be extended BEFORE the shell's single
        # compinit runs — a second compinit later in the rc re-reads a stale
        # dump and silently clobbers every registration from the first.
        if command_exists zsh; then
            mkdir -p "$HERDR_ZSH_COMPDIR"
            herdr completion zsh > "$HERDR_ZSH_COMPDIR/_herdr"
            if [[ -f "$HOME/.zshrc" ]] && ! grep -q '\.zsh/completions' "$HOME/.zshrc"; then
                if grep -q 'oh-my-zsh\.sh' "$HOME/.zshrc"; then
                    # shellcheck disable=SC2016
                    sed -i '0,/^[[:space:]]*source .*oh-my-zsh\.sh/s||fpath=(~/.zsh/completions $fpath)\n&|' "$HOME/.zshrc"
                    info "Added ~/.zsh/completions to fpath (before oh-my-zsh's compinit)"
                else
                    cat >> "$HOME/.zshrc" << 'EOF'

# ─── Completions (herdr) ───────────────────────────────────────────────────────
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
EOF
                    info "Added fpath + compinit to .zshrc"
                fi
                find "$HOME" -maxdepth 1 -name '.zcompdump*' -type f -delete 2>/dev/null || true
            fi
            success "herdr zsh completions -> ~/.zsh/completions/_herdr"
        fi

        # Bash completions (auto-loaded by the bash-completion package)
        mkdir -p "$HOME/.local/share/bash-completion/completions"
        if herdr completion bash > "$HOME/.local/share/bash-completion/completions/herdr" 2>/dev/null; then
            success "herdr bash completions -> ~/.local/share/bash-completion/completions/herdr"
        else
            rm -f "$HOME/.local/share/bash-completion/completions/herdr"
            warn "herdr bash completions not available in this herdr version"
        fi

        # DISPLAY fallback for GUI tools inside herdr panes (zsh; the block
        # self-guards at runtime: only fires when DISPLAY is unset and a local
        # X socket exists, so SSH X-forwarding and desktops are unaffected)
        if [[ -f "$HERDR_CONFIG_SRC/zshenv-display-snippet.zsh" ]] && command_exists zsh; then
            if ! grep -qF 'aeo herdr display' "$HOME/.zshenv" 2>/dev/null; then
                {
                    echo ""
                    echo "# >>> aeo herdr display >>>"
                    cat "$HERDR_CONFIG_SRC/zshenv-display-snippet.zsh"
                    echo "# <<< aeo herdr display <<<"
                } >> "$HOME/.zshenv"
                success "DISPLAY fallback appended to ~/.zshenv"
            else
                warn "DISPLAY fallback already in ~/.zshenv"
            fi
        fi
    else
        info "Skipped AEO herdr + config"
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
    success "Tool aliases added to ~/.zshrc"
else
    warn "Tool aliases already present in ~/.zshrc"
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

if [[ -n "$_brew_bin" ]] && ! grep -q 'brew shellenv' ~/.bashrc 2>/dev/null; then
    info "Adding Homebrew shellenv to .bashrc..."
    cat >> ~/.bashrc << 'EOF'

# ─── Homebrew ──────────────────────────────────────────────────────────────────
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
EOF
    success "Homebrew shellenv added to .bashrc"
elif [[ -n "$_brew_bin" ]]; then
    warn "Homebrew already in .bashrc"
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
if $SHELL_STACK_APPLIED; then
    echo "  - Zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font"
    echo "  - Zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting"
fi
echo "  - NVM + Node.js 22 LTS"
echo "  - Mamba + 'dev' environment (anthropic, openai, httpx, rich, typer, pydantic)"
echo "  - Kitty terminal (GPU-optimized, OLED theme, 4K ready)"
echo "  - Yazi file manager"
echo "  - CLI tools: ripgrep, fd, fzf, bat, eza, delta, glow, btop, ncdu, duf, httpie, yq, shellcheck, p7zip"
echo "  - Terminal media: ffmpeg, mpv, chafa"
if $TMUX_INSTALLED; then
    echo "  - tmux (with AEO config)"
fi
if $ZELLIJ_INSTALLED; then
    echo "  - Zellij terminal multiplexer (with AEO config)"
fi
if $HERDR_INSTALLED; then
    echo "  - herdr agent multiplexer (with AEO config, integrations, plugins)"
fi
if $GHOSTTY_LAUNCHER_DEPLOYED; then
    echo "  - Ghostty session launcher (transparent tmux + decoration fix)"
fi
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
echo "  herdr          - Agent multiplexer (ctrl+a prefix)"
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
if $ZELLIJ_CONFIG_APPLIED; then
    echo "  - AEO zellij config applied (p10k-aeo theme, Alt-key status row)"
fi
if $HERDR_CONFIG_APPLIED; then
    echo "  - AEO herdr config applied (ctrl+a prefix, persistence on; pane_history"
    echo "    writes scrollback to disk — set it false on shared/sensitive hosts)"
fi
if $GHOSTTY_LAUNCHER_DEPLOYED; then
    echo "  - Ghostty launcher fires via the rc guard under Ghostty; restart Ghostty to use it"
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
