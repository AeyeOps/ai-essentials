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
- Kiro CLI (Amazon)
- Codex CLI (OpenAI)

Notes
- Script requires curl, bash, and package managers for the respective tools.
- It may perform network operations and install system packages.
- Kiro CLI updates attempt the built-in updater first, then fall back to the package if needed.

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

KIRO_DEB_URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/kiro-cli.deb"
: "${KIRO_UPDATE_TIMEOUT:=180}"
: "${KIRO_UPDATE_HELP_TIMEOUT:=10}"

declare -a KIRO_UPDATE_CMD
KIRO_SELF_UPDATE_VERSION=""
KIRO_SELF_UPDATE_REASON=""
KIRO_SELF_UPDATE_RESULT=""

declare -a SUMMARY

##########
# HELPER #
##########
run_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif command -v sudo &>/dev/null; then
    sudo "$@"
  else
    echo -e "${YELLOW}Elevated privileges required for: $*${NC}"
    echo -e "${YELLOW}sudo not available; please rerun with appropriate permissions.${NC}"
    return 1
  fi
}

record_summary() {
  local tool="$1" result="$2"
  SUMMARY+=("$tool: $result")
}

# Download and install the Kiro CLI .deb package. Retries dependency fixes if needed.
install_kiro_from_deb() {
  local debfile
  debfile=$(mktemp --suffix=.deb)

  echo -e "${BLUE}Downloading latest Kiro CLI package...${NC}"
  if ! curl -fLo "$debfile" "$KIRO_DEB_URL"; then
    echo -e "${YELLOW}Failed to download Kiro CLI package.${NC}"
    rm -f "$debfile"
    return 1
  fi

  echo -e "${BLUE}Installing Kiro CLI package via dpkg...${NC}"
  if ! run_as_root dpkg -i "$debfile"; then
    echo -e "${YELLOW}dpkg reported issues; attempting to fix dependencies via apt-get -f.${NC}"
    if run_as_root apt-get install -f -y; then
      if ! run_as_root dpkg -i "$debfile"; then
        echo -e "${YELLOW}Kiro CLI package install still failing after dependency fix.${NC}"
        rm -f "$debfile"
        return 1
      fi
    else
      echo -e "${YELLOW}Unable to fix dependencies for Kiro CLI package.${NC}"
      rm -f "$debfile"
      return 1
    fi
  fi

  rm -f "$debfile"
  return 0
}

build_kiro_update_command() {
  local help_output status

  if ! command -v kiro-cli &>/dev/null; then
    KIRO_UPDATE_CMD=(kiro-cli update)
    return
  fi

  if command -v timeout &>/dev/null; then
    help_output=$(timeout "$KIRO_UPDATE_HELP_TIMEOUT" kiro-cli update --help 2>&1)
    status=$?
  else
    help_output=$(kiro-cli update --help 2>&1)
    status=$?
  fi

  if [[ $status -eq 0 ]] && grep -q -- '--yes' <<<"$help_output"; then
    KIRO_UPDATE_CMD=(kiro-cli update --yes)
    return
  fi

  KIRO_UPDATE_CMD=(kiro-cli update)
}

run_kiro_self_update() {
  local local_version="$1"
  local update_output status joined_cmd hinted_version normalized_output

  KIRO_SELF_UPDATE_VERSION=""
  KIRO_SELF_UPDATE_REASON=""
  KIRO_SELF_UPDATE_RESULT=""

  build_kiro_update_command
  joined_cmd="${KIRO_UPDATE_CMD[*]}"
  echo -e "${BLUE}Attempting in-place update via ${joined_cmd} (timeout ${KIRO_UPDATE_TIMEOUT}s if available)...${NC}"

  if command -v timeout &>/dev/null; then
    update_output=$(timeout "$KIRO_UPDATE_TIMEOUT" "${KIRO_UPDATE_CMD[@]}" 2>&1)
    status=$?
  else
    update_output=$("${KIRO_UPDATE_CMD[@]}" 2>&1)
    status=$?
  fi

  if [[ $status -eq 124 ]]; then
    KIRO_SELF_UPDATE_RESULT="timeout"
    KIRO_SELF_UPDATE_REASON="Self-update timed out after ${KIRO_UPDATE_TIMEOUT}s."
    echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
    return 1
  fi

  if [[ $status -ne 0 ]]; then
    KIRO_SELF_UPDATE_RESULT="failed"
    KIRO_SELF_UPDATE_REASON="Self-update failed: $(echo "$update_output" | tail -n1)"
    echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
    return 1
  fi

  KIRO_SELF_UPDATE_VERSION=$(get_kiro_local_version || true)
  hinted_version=$(echo "$update_output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?' || true)

  normalized_output=$(echo "$update_output" | tr '\n' ' ')

  if [[ -z "$KIRO_SELF_UPDATE_VERSION" && -n "$hinted_version" ]]; then
    KIRO_SELF_UPDATE_VERSION="$hinted_version"
  fi

  if grep -qiE 'no updates available|already up|latest version' <<<"$update_output"; then
    KIRO_SELF_UPDATE_RESULT="up_to_date"
    KIRO_SELF_UPDATE_REASON="${normalized_output:-Self-update reports current version.}"
    KIRO_SELF_UPDATE_VERSION=${KIRO_SELF_UPDATE_VERSION:-$local_version}
    return 0
  fi

  if [[ -n "$KIRO_SELF_UPDATE_VERSION" && -n "$local_version" && "$KIRO_SELF_UPDATE_VERSION" != "$local_version" ]]; then
    KIRO_SELF_UPDATE_RESULT="updated"
    KIRO_SELF_UPDATE_REASON="Updated from $local_version to $KIRO_SELF_UPDATE_VERSION"
    return 0
  fi

  KIRO_SELF_UPDATE_RESULT="unknown"
  KIRO_SELF_UPDATE_REASON="Self-update completed but status unclear"
  return 0
}

get_kiro_local_version() {
  local output version

  if ! command -v kiro-cli &>/dev/null; then
    return 1
  fi

  output=$(kiro-cli --version 2>/dev/null || true)
  version=$(echo "$output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?')

  if [[ -z "$version" ]]; then
    output=$(kiro-cli version 2>/dev/null || true)
    version=$(echo "$output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?')
  fi

  if [[ -n "$version" ]]; then
    printf '%s' "$version"
    return 0
  fi

  return 1
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
    local_version=$(gemini --version 2>/dev/null | awk '{print $NF}' || true)
    old_version="$local_version"
    if [[ -n "$local_version" ]]; then
      echo -e "${GREEN}Detected Gemini version: $local_version${NC}"
    else
      echo -e "${YELLOW}Gemini CLI found but version check failed (config issue?).${NC}"
    fi
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
      new_version=$(gemini --version 2>/dev/null | awk '{print $NF}' || true)
      record_summary "Gemini CLI" "Updated from $old_version to ${new_version:-unknown}"
    else
      record_summary "Gemini CLI" "Update failed: $(echo "$out" | tail -20)"
    fi
  fi
}

### ========== KIRO CLI ==========
handle_kiro() {
  echo -e "\n${CYAN}=== Kiro CLI (Amazon) ===${NC}"
  local local_version="" new_version install_status installed=0
  set +e

  if command -v kiro-cli &>/dev/null; then
    installed=1
    if local_version=$(get_kiro_local_version); then
      echo -e "${GREEN}Detected Kiro CLI version: $local_version${NC}"
    else
      local_version="unknown"
      echo -e "${YELLOW}Detected Kiro CLI installation but unable to parse version.${NC}"
    fi
  fi

  if (( ! installed )); then
    echo -e "${YELLOW}Kiro CLI is not installed.${NC}"
    install_kiro_from_deb
    install_status=$?
    new_version=$(get_kiro_local_version || true)
    if [[ $install_status -ne 0 ]]; then
      record_summary "Kiro CLI" "Installation failed"
    elif [[ -n "$new_version" ]]; then
      record_summary "Kiro CLI" "Installed new version $new_version"
    else
      record_summary "Kiro CLI" "Installed new version (unable to detect version)"
    fi
    set -e
    return
  fi

  if run_kiro_self_update "$local_version"; then
    case "$KIRO_SELF_UPDATE_RESULT" in
      up_to_date)
        record_summary "Kiro CLI" "Already up to date (${KIRO_SELF_UPDATE_VERSION:-$local_version})"
        set -e
        return
        ;;
      updated)
        record_summary "Kiro CLI" "Updated via kiro-cli update from $local_version to ${KIRO_SELF_UPDATE_VERSION:-unknown}"
        set -e
        return
        ;;
      unknown)
        echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
        ;;
    esac
  else
    echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
  fi

  echo -e "${BLUE}Falling back to Kiro CLI package reinstall...${NC}"
  install_kiro_from_deb
  install_status=$?
  new_version=$(get_kiro_local_version || true)
  if [[ $install_status -ne 0 ]]; then
    record_summary "Kiro CLI" "Package reinstall failed after kiro-cli update (${KIRO_SELF_UPDATE_REASON:-unknown reason})"
  elif [[ -z "$new_version" ]]; then
    record_summary "Kiro CLI" "Package reinstall completed but version unknown"
  elif [[ "$new_version" == "$local_version" ]]; then
    record_summary "Kiro CLI" "Package reinstall completed but version unchanged ($local_version)"
  else
    record_summary "Kiro CLI" "Updated from $local_version to $new_version via package"
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
    local_version=$(codex --version 2>/dev/null | awk '{print $NF}' || true)
    old_version="$local_version"
    if [[ -n "$local_version" ]]; then
      echo -e "${GREEN}Detected Codex version: $local_version${NC}"
    else
      echo -e "${YELLOW}Codex CLI found but version check failed.${NC}"
    fi
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
    return
  fi

  if out=$(npm install -g @openai/codex --verbose 2>&1); then
    new_version=$(codex --version 2>/dev/null | awk '{print $NF}' || true)
    record_summary "Codex CLI" "Updated from $old_version to ${new_version:-unknown}"
    return
  fi

  if grep -q "ENOTEMPTY" <<<"$out"; then
    local npm_root codex_dir tmp_out cleanup_status
    npm_root=$(npm root -g 2>/dev/null || true)
    if [[ -n "$npm_root" ]]; then
      codex_dir="$npm_root/@openai/codex"
      echo -e "${YELLOW}Detected ENOTEMPTY during Codex update; cleaning $codex_dir and retrying...${NC}"
      rm -rf "$codex_dir"
      cleanup_status=$?
      if [[ -d "$npm_root/@openai" ]]; then
        find "$npm_root/@openai" -maxdepth 1 -type d -name '.codex-*' -exec rm -rf {} + 2>/dev/null || true
      fi
      if [[ $cleanup_status -eq 0 ]]; then
        if tmp_out=$(npm install -g @openai/codex --verbose 2>&1); then
          new_version=$(codex --version 2>/dev/null | awk '{print $NF}' || true)
          record_summary "Codex CLI" "Updated from $old_version to ${new_version:-unknown} after cleanup"
          return
        fi
        out="$tmp_out"
      else
        echo -e "${YELLOW}Cleanup step failed (exit $cleanup_status).${NC}"
      fi
    fi
  fi

  record_summary "Codex CLI" "Update failed: $(echo "${out:-unknown error}" | tail -20)"
}

#####################
### MAIN SECTION  ###
#####################

main() {
  handle_claude_code
  handle_crush
  handle_gemini
  handle_kiro
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
