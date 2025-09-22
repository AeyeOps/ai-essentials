#!/usr/bin/env bash
set -euo pipefail

# update_cli_ubuntu.sh
# Purpose: Update or install common AI-related CLIs on Ubuntu.
# Usage: run without args to attempt updates; use -h/--help for help.

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'EOF'
update_cli_ubuntu.sh

Updates or installs a small set of AI-related CLI tools on Ubuntu-based systems.

Tools managed
- Claude Code (Anthropic)
- Crush (Charmbracelet, Go)
- Gemini CLI (Google)
- AWS Q CLI (Amazon)
- Codex CLI (OpenAI)

Notes
- Script requires curl, bash, and package managers for the respective tools.
- It may perform network operations and install system packages.
- Q CLI updates reinstall the latest .deb package instead of using the built-in updater.

Usage
  bash scripts/update_cli_ubuntu.sh
  bash scripts/update_cli_ubuntu.sh --help
EOF
  exit 0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

declare -a SUMMARY

##########
# HELPER #
##########
record_summary() {
  local tool="$1" result="$2"
  SUMMARY+=("$tool: $result")
}

# Download and install the Amazon Q .deb package. Retries dependency fixes if needed.
install_q_from_deb() {
  local debfile
  debfile=$(mktemp --suffix=.deb)

  echo -e "${BLUE}Downloading latest Amazon Q package...${NC}"
  if ! curl -fLo "$debfile" https://desktop-release.q.us-east-1.amazonaws.com/latest/amazon-q.deb; then
    echo -e "${YELLOW}Failed to download Amazon Q package.${NC}"
    rm -f "$debfile"
    return 1
  fi

  echo -e "${BLUE}Installing Amazon Q package via dpkg...${NC}"
  if ! sudo dpkg -i "$debfile"; then
    echo -e "${YELLOW}dpkg reported issues; attempting to fix dependencies via apt-get -f.${NC}"
    if sudo apt-get install -f -y; then
      if ! sudo dpkg -i "$debfile"; then
        echo -e "${YELLOW}Amazon Q package install still failing after dependency fix.${NC}"
        rm -f "$debfile"
        return 1
      fi
    else
      echo -e "${YELLOW}Unable to fix dependencies for Amazon Q package.${NC}"
      rm -f "$debfile"
      return 1
    fi
  fi

  rm -f "$debfile"
  return 0
}

### ========== CLAUDE CODE ==========
handle_claude_code() {
  echo -e "\n${CYAN}=== Claude Code (Anthropic, native nightly) ===${NC}"
  local local_version remote_version new_version
  local tmpfile
  tmpfile=$(mktemp)
  set +e

  if command -v claude &>/dev/null; then
    local_version=$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo -e "${GREEN}Detected Claude Code version: $local_version${NC}"
  else
    echo -e "${YELLOW}Claude Code is not installed.${NC}"
    local_version="none"
  fi

  if remote_version=$(curl -fsSL https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest 2>/dev/null); then
    echo -e "${BLUE}Latest Claude Code nightly version: $remote_version${NC}"
  else
    echo -e "${YELLOW}Unable to determine latest Claude Code version.${NC}"
    record_summary "Claude Code" "Skipped: unable to query remote version"
    rm -f "$tmpfile"
    set -e
    return
  fi

  if [[ "$local_version" == "$remote_version" ]]; then
    echo -e "${GREEN}Claude Code is already up to date ($local_version). Skipping install.${NC}"
    record_summary "Claude Code" "Already up to date ($local_version)"
  else
    echo -e "${BLUE}Updating Claude Code from $local_version to $remote_version ...${NC}"
    if curl -fsSL https://claude.ai/install.sh -o /tmp/claude_install.sh; then
      if bash -x /tmp/claude_install.sh latest 2>&1 | tee "$tmpfile"; then
        new_version=$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        record_summary "Claude Code" "Updated from $local_version to $new_version"
      else
        record_summary "Claude Code" "Update failed: $(tail -20 "$tmpfile")"
      fi
    else
      record_summary "Claude Code" "Install script download failed"
    fi
  fi
  rm -f "$tmpfile"
  set -e
}

### ========== CRUSH ==========
handle_crush() {
  echo -e "\n${CYAN}=== Crush CLI (Charmbracelet, Go) ===${NC}"
  local local_version remote_version old_version

  if ! command -v go &>/dev/null; then
    echo -e "${YELLOW}Go toolchain not found; skipping Crush update.${NC}"
    record_summary "Crush" "Skipped: Go toolchain not installed"
    return
  fi

  if command -v crush &>/dev/null; then
    local_version=$(crush --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    old_version="$local_version"
    echo -e "${GREEN}Detected Crush version: $local_version${NC}"
  else
    echo -e "${YELLOW}Crush is not installed.${NC}"
    local_version="none"
    old_version="none"
  fi
  local remote_output
  if remote_output=$(go list -m -f '{{.Version}}' github.com/charmbracelet/crush@latest 2>/dev/null); then
    remote_version=$(echo "$remote_output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    echo -e "${BLUE}Latest Crush version: $remote_version${NC}"
  else
    echo -e "${YELLOW}Unable to determine latest Crush version.${NC}"
    record_summary "Crush" "Skipped: unable to query remote version"
    return
  fi

  if [[ "$local_version" == "$remote_version" ]]; then
    record_summary "Crush" "Already up to date ($local_version)"
  else
    if out=$(go install -v github.com/charmbracelet/crush@latest 2>&1); then
      new_version=$(crush --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
      record_summary "Crush" "Updated from $old_version to $new_version"
    else
      record_summary "Crush" "Update failed: $(echo "$out" | tail -20)"
    fi
  fi
}

### ========== GEMINI CLI ==========
handle_gemini() {
  echo -e "\n${CYAN}=== Gemini CLI (Google, npm nightly) ===${NC}"
  local local_version remote_version old_version
  if ! command -v npm &>/dev/null; then
    echo -e "${YELLOW}npm not found; skipping Gemini CLI update.${NC}"
    record_summary "Gemini CLI" "Skipped: npm not available"
    return
  fi
  if command -v gemini &>/dev/null; then
    local_version=$(gemini --version 2>/dev/null | awk '{print $NF}')
    old_version="$local_version"
    echo -e "${GREEN}Detected Gemini version: $local_version${NC}"
  else
    echo -e "${YELLOW}Gemini CLI is not installed.${NC}"
    local_version="none"
    old_version="none"
  fi
  if remote_version=$(npm view @google/gemini-cli dist-tags.nightly 2>/dev/null); then
    echo -e "${BLUE}Latest Gemini nightly version: $remote_version${NC}"
  else
    echo -e "${YELLOW}Unable to determine Gemini nightly version.${NC}"
    record_summary "Gemini CLI" "Skipped: unable to query remote version"
    return
  fi

  if [[ "$local_version" == "$remote_version" ]]; then
    record_summary "Gemini CLI" "Already up to date ($local_version)"
  else
    if out=$(npm install -g @google/gemini-cli@nightly --verbose 2>&1); then
      new_version=$(gemini --version 2>/dev/null | awk '{print $NF}')
      record_summary "Gemini CLI" "Updated from $old_version to $new_version"
    else
      record_summary "Gemini CLI" "Update failed: $(echo "$out" | tail -20)"
    fi
  fi
}

### ========== Q CLI ==========
handle_q() {
  echo -e "\n${CYAN}=== AWS Q CLI (Amazon) ===${NC}"
  local local_version new_version install_status
  set +e
  if command -v q &>/dev/null; then
    local_version=$(q version 2>/dev/null | grep -m1 -i version | grep -Eo '[0-9\.]+')
    echo -e "${GREEN}Detected Q CLI version: ${local_version:-unknown}${NC}"
    echo -e "${BLUE}Reinstalling Amazon Q from package to pick up latest release...${NC}"
    install_q_from_deb
    install_status=$?
    new_version=$(q version 2>/dev/null | grep -m1 -i version | grep -Eo '[0-9\.]+')
    if [[ $install_status -ne 0 ]]; then
      record_summary "Q CLI" "Package reinstall failed"
    elif [[ -z "$new_version" ]]; then
      record_summary "Q CLI" "Package reinstall completed but version unknown"
    elif [[ "$local_version" == "$new_version" ]]; then
      record_summary "Q CLI" "Reinstalled current version $local_version"
    else
      record_summary "Q CLI" "Updated from $local_version to $new_version"
    fi
  else
    echo -e "${YELLOW}Q CLI is not installed.${NC}"
    install_q_from_deb
    install_status=$?
    new_version=$(q version 2>/dev/null | grep -m1 -i version | grep -Eo '[0-9\.]+')
    if [[ $install_status -ne 0 ]]; then
      record_summary "Q CLI" "Installation failed"
    else
      record_summary "Q CLI" "Installed new version ${new_version:-unknown}"
    fi
  fi
  set -e
}

### ========== CODEX ==========

handle_codex() {
  echo -e "\n${CYAN}=== Codex CLI (OpenAI, npm global) ===${NC}"
  local local_version remote_version old_version
  if ! command -v npm &>/dev/null; then
    echo -e "${YELLOW}npm not found; skipping Codex CLI update.${NC}"
    record_summary "Codex CLI" "Skipped: npm not available"
    return
  fi
  if command -v codex &>/dev/null; then
    local_version=$(codex --version 2>/dev/null | awk '{print $NF}')
    old_version="$local_version"
    echo -e "${GREEN}Detected Codex version: $local_version${NC}"
  else
    echo -e "${YELLOW}Codex CLI is not installed.${NC}"
    local_version="none"
    old_version="none"
  fi
  if remote_version=$(npm view @openai/codex version 2>/dev/null); then
    echo -e "${BLUE}Latest Codex version: $remote_version${NC}"
  else
    echo -e "${YELLOW}Unable to determine latest Codex version.${NC}"
    record_summary "Codex CLI" "Skipped: unable to query remote version"
    return
  fi

  if [[ "$local_version" == "$remote_version" ]]; then
    record_summary "Codex CLI" "Already up to date ($local_version)"
  else
    if out=$(npm install -g @openai/codex --verbose 2>&1); then
      new_version=$(codex --version 2>/dev/null | awk '{print $NF}')
      record_summary "Codex CLI" "Updated from $old_version to $new_version"
    else
      record_summary "Codex CLI" "Update failed: $(echo "$out" | tail -20)"
    fi
  fi
}

#####################
### MAIN SECTION  ###
#####################

main() {
  handle_claude_code
  handle_crush
  handle_gemini
  handle_q
  handle_codex

  echo -e "\n${MAGENTA}======= SUMMARY ========${NC}"
  for s in "${SUMMARY[@]}"; do
    if [[ "$s" == *"Already up to date"* || "$s" == *"Installed new version"* ]]; then
      echo -e "${GREEN}$s${NC}"
    elif [[ "$s" == *"Updated from"* ]]; then
      echo -e "${BLUE}$s${NC}"
    elif [[ "$s" == *"Update failed"* || "$s" == *"Install failed"* ]]; then
      echo -e "${RED}$s${NC}"
    else
      echo -e "${YELLOW}$s${NC}"
    fi
  done
  echo -e "\n${CYAN}=== All tools processed. ===${NC}\n"
}

main
