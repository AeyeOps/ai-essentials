#!/usr/bin/env bash
#
# AI Developer Essentials Stack Setup
# Idempotent installation script for a complete AI development environment
#
# Components:
#   - NVM + Node.js 22 LTS
#   - Mamba/Miniforge + 'dev' environment with AI packages
#   - Kitty terminal
#   - Yazi file manager
#   - CLI tools: fd, fzf, bat, eza, delta, ripgrep
#   - Zellij terminal multiplexer
#   - bun (JS runtime) + direnv
#   - Zsh + Oh-My-Zsh + Powerlevel10k
#
# Usage: ./setup-ai-dev-stack.sh
#
# Author: Generated for AEO AI Essentials
# License: MIT

set -euo pipefail

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

# ─── Ensure sudo available ──────────────────────────────────────────────────
if ! command_exists sudo; then
    error "sudo is required but not installed"
fi

# ─── Update apt cache ───────────────────────────────────────────────────────
info "Updating package cache..."
sudo apt-get update -qq

# ─── Install base dependencies ──────────────────────────────────────────────
info "Installing base dependencies..."
sudo apt-get install -qq -y git curl unzip fontconfig

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
    curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" -o "$FONT_DIR/MesloLGS NF Regular.ttf"
    curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" -o "$FONT_DIR/MesloLGS NF Bold.ttf"
    curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" -o "$FONT_DIR/MesloLGS NF Italic.ttf"
    curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" -o "$FONT_DIR/MesloLGS NF Bold Italic.ttf"
    fc-cache -f
    success "MesloLGS Nerd Font installed"
else
    warn "MesloLGS Nerd Font already installed"
fi

info "Checking Zsh..."
if ! command_exists zsh; then
    info "Installing Zsh..."
    sudo apt-get install -qq -y zsh
    success "Zsh installed"
else
    warn "Zsh already installed: $(zsh --version)"
fi

info "Checking Oh-My-Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Installing Oh-My-Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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
    chsh -s "$(which zsh)"
    success "Zsh set as default shell (log out and back in to apply)"
else
    warn "Zsh is already the default shell"
fi

# Configure .zshrc if it doesn't have our setup
if ! grep -q "ZSH_THEME=\"powerlevel10k/powerlevel10k\"" ~/.zshrc 2>/dev/null; then
    info "Configuring .zshrc with Powerlevel10k theme..."
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc 2>/dev/null || true
fi

# Enable plugins in .zshrc
if ! grep -q "zsh-autosuggestions" ~/.zshrc 2>/dev/null; then
    info "Enabling zsh plugins in .zshrc..."
    sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc 2>/dev/null || true
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

# Ensure NVM is in zshrc
if ! grep -q 'NVM_DIR' ~/.zshrc 2>/dev/null; then
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
    curl -fsSL -o /tmp/miniforge.sh "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH_ALT}.sh"
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
    sudo apt-get install -qq -y kitty
    success "Kitty installed"

    # Configure Kitty for auto-copy and right-click paste
    mkdir -p ~/.config/kitty
    if [[ ! -f ~/.config/kitty/kitty.conf ]]; then
        info "Configuring Kitty..."
        cat > ~/.config/kitty/kitty.conf << 'EOF'
# ─── Kitty Configuration ───────────────────────────────────────────────────

# Copy on select
copy_on_select clipboard

# Mouse bindings
mouse_map right press ungrabbed paste_from_clipboard

# Font - MesloLGS NF for Powerlevel10k compatibility
font_family MesloLGS NF
bold_font MesloLGS NF Bold
italic_font MesloLGS NF Italic
bold_italic_font MesloLGS NF Bold Italic
font_size 11.0

# Scrollback
scrollback_lines 10000

# Bell
enable_audio_bell no

# Tab bar
tab_bar_style powerline

# Window padding
window_padding_width 4

# Cursor
cursor_shape beam
cursor_blink_interval 0

# URLs
url_style curly
open_url_with default

# Performance
repaint_delay 10
input_delay 3
sync_to_monitor yes
EOF
        success "Kitty configured"
    fi
else
    warn "Kitty already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 5. YAZI FILE MANAGER
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Yazi..."
if ! command_exists yazi; then
    info "Installing Yazi..."
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -fsSL "https://github.com/sxyazi/yazi/releases/download/${YAZI_VERSION}/yazi-${ARCH_ALT}-unknown-linux-gnu.zip" -o /tmp/yazi.zip
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
    sudo apt-get install -qq -y ripgrep
    success "ripgrep installed"
else
    warn "ripgrep already installed"
fi

# fd
info "Checking fd..."
if ! command_exists fd && ! command_exists fdfind; then
    info "Installing fd..."
    sudo apt-get install -qq -y fd-find
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
    sudo apt-get install -qq -y fzf
    success "fzf installed"
else
    warn "fzf already installed"
fi

# bat
info "Checking bat..."
if ! command_exists bat && ! command_exists batcat; then
    info "Installing bat..."
    sudo apt-get install -qq -y bat
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
    sudo apt-get install -qq -y eza || {
        # Fallback: install from GitHub releases
        EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep -oP '"tag_name": "\K[^"]+')
        curl -fsSL "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${ARCH_ALT}-unknown-linux-gnu.tar.gz" -o /tmp/eza.tar.gz
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
    DELTA_VERSION=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH_DEB}.deb" -o /tmp/delta.deb
    sudo dpkg -i /tmp/delta.deb || sudo apt-get install -qq -f -y
    rm /tmp/delta.deb
    success "delta installed"
else
    warn "delta already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 7. ZELLIJ TERMINAL MULTIPLEXER
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Zellij..."
if ! command_exists zellij; then
    info "Installing Zellij..."
    ZELLIJ_VERSION=$(curl -s https://api.github.com/repos/zellij-org/zellij/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -fsSL "https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VERSION}/zellij-${ARCH_ALT}-unknown-linux-musl.tar.gz" -o /tmp/zellij.tar.gz
    sudo tar -xzf /tmp/zellij.tar.gz -C /usr/local/bin/
    rm /tmp/zellij.tar.gz
    success "Zellij installed"
else
    warn "Zellij already installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 8. BUN (FAST JS RUNTIME)
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Bun..."
if [[ ! -x "$HOME/.bun/bin/bun" ]]; then
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    success "Bun installed"
else
    warn "Bun already installed: $($HOME/.bun/bin/bun --version)"
fi

# Ensure bun is in zshrc
if ! grep -q 'BUN_INSTALL' ~/.zshrc 2>/dev/null; then
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
    sudo apt-get install -qq -y direnv
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
# 10. SHELL ALIASES FOR NEW TOOLS
# ═══════════════════════════════════════════════════════════════════════════
if ! grep -q '# ─── AI Dev Stack Aliases' ~/.zshrc 2>/dev/null; then
    info "Adding tool aliases to .zshrc..."
    cat >> ~/.zshrc << 'EOF'

# ─── AI Dev Stack Aliases ──────────────────────────────────────────────────────
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --icons --level=2'
alias cat='bat --paging=never'
alias y='yazi'
alias zj='zellij'
EOF
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
echo "  - Kitty terminal (with auto-copy, right-click paste, Nerd Font)"
echo "  - Yazi file manager"
echo "  - CLI tools: ripgrep, fd, fzf, bat, eza, delta"
echo "  - Zellij terminal multiplexer"
echo "  - Bun JS runtime"
echo "  - direnv"
echo ""
echo "Quick start commands:"
echo "  kitty          - Launch Kitty terminal"
echo "  yazi / y       - File manager"
echo "  zellij / zj    - Terminal multiplexer"
echo "  mamba activate dev  - Activate AI dev environment"
echo ""
echo -e "${YELLOW}NOTES:${NC}"
echo "  - Log out and back in (or run 'exec zsh') to apply all changes"
echo "  - On first Zsh launch, Powerlevel10k will run its configuration wizard"
echo "  - Set your terminal font to 'MesloLGS NF' for proper icons"
echo ""
