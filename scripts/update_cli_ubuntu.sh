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
- Codex CLI (OpenAI)

Notes
- Script requires curl, bash, and package managers for the respective tools.
- It may perform network operations and install system packages.
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

# DISABLED: KIRO_DEB_URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/kiro-cli.deb"
# DISABLED: : "${KIRO_UPDATE_TIMEOUT:=180}"
# DISABLED: : "${KIRO_UPDATE_HELP_TIMEOUT:=10}"
# DISABLED:
# DISABLED: declare -a KIRO_UPDATE_CMD
# DISABLED: KIRO_SELF_UPDATE_VERSION=""
# DISABLED: KIRO_SELF_UPDATE_REASON=""
# DISABLED: KIRO_SELF_UPDATE_RESULT=""

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

# DISABLED: # Download and install the Kiro CLI .deb package. Retries dependency fixes if needed.
# DISABLED: install_kiro_from_deb() {
# DISABLED:   local debfile
# DISABLED:   debfile=$(mktemp --suffix=.deb)
# DISABLED:
# DISABLED:   echo -e "${BLUE}Downloading latest Kiro CLI package...${NC}"
# DISABLED:   if ! curl -fLo "$debfile" "$KIRO_DEB_URL"; then
# DISABLED:     echo -e "${YELLOW}Failed to download Kiro CLI package.${NC}"
# DISABLED:     rm -f "$debfile"
# DISABLED:     return 1
# DISABLED:   fi
# DISABLED:
# DISABLED:   echo -e "${BLUE}Installing Kiro CLI package via dpkg...${NC}"
# DISABLED:   if ! run_as_root dpkg -i "$debfile"; then
# DISABLED:     echo -e "${YELLOW}dpkg reported issues; attempting to fix dependencies via apt-get -f.${NC}"
# DISABLED:     if run_as_root apt-get install -f -y; then
# DISABLED:       if ! run_as_root dpkg -i "$debfile"; then
# DISABLED:         echo -e "${YELLOW}Kiro CLI package install still failing after dependency fix.${NC}"
# DISABLED:         rm -f "$debfile"
# DISABLED:         return 1
# DISABLED:       fi
# DISABLED:     else
# DISABLED:       echo -e "${YELLOW}Unable to fix dependencies for Kiro CLI package.${NC}"
# DISABLED:       rm -f "$debfile"
# DISABLED:       return 1
# DISABLED:     fi
# DISABLED:   fi
# DISABLED:
# DISABLED:   rm -f "$debfile"
# DISABLED:   return 0
# DISABLED: }

# DISABLED: build_kiro_update_command() {
# DISABLED:   local help_output status
# DISABLED:
# DISABLED:   if ! command -v kiro-cli &>/dev/null; then
# DISABLED:     KIRO_UPDATE_CMD=(kiro-cli update)
# DISABLED:     return
# DISABLED:   fi
# DISABLED:
# DISABLED:   if command -v timeout &>/dev/null; then
# DISABLED:     help_output=$(timeout "$KIRO_UPDATE_HELP_TIMEOUT" kiro-cli update --help 2>&1)
# DISABLED:     status=$?
# DISABLED:   else
# DISABLED:     help_output=$(kiro-cli update --help 2>&1)
# DISABLED:     status=$?
# DISABLED:   fi
# DISABLED:
# DISABLED:   if [[ $status -eq 0 ]] && grep -q -- '--yes' <<<"$help_output"; then
# DISABLED:     KIRO_UPDATE_CMD=(kiro-cli update --yes)
# DISABLED:     return
# DISABLED:   fi
# DISABLED:
# DISABLED:   KIRO_UPDATE_CMD=(kiro-cli update)
# DISABLED: }

# DISABLED: run_kiro_self_update() {
# DISABLED:   local local_version="$1"
# DISABLED:   local update_output status joined_cmd hinted_version normalized_output
# DISABLED:
# DISABLED:   KIRO_SELF_UPDATE_VERSION=""
# DISABLED:   KIRO_SELF_UPDATE_REASON=""
# DISABLED:   KIRO_SELF_UPDATE_RESULT=""
# DISABLED:
# DISABLED:   build_kiro_update_command
# DISABLED:   joined_cmd="${KIRO_UPDATE_CMD[*]}"
# DISABLED:   echo -e "${BLUE}Attempting in-place update via ${joined_cmd} (timeout ${KIRO_UPDATE_TIMEOUT}s if available)...${NC}"
# DISABLED:
# DISABLED:   if command -v timeout &>/dev/null; then
# DISABLED:     update_output=$(timeout "$KIRO_UPDATE_TIMEOUT" "${KIRO_UPDATE_CMD[@]}" 2>&1)
# DISABLED:     status=$?
# DISABLED:   else
# DISABLED:     update_output=$("${KIRO_UPDATE_CMD[@]}" 2>&1)
# DISABLED:     status=$?
# DISABLED:   fi
# DISABLED:
# DISABLED:   if [[ $status -eq 124 ]]; then
# DISABLED:     KIRO_SELF_UPDATE_RESULT="timeout"
# DISABLED:     KIRO_SELF_UPDATE_REASON="Self-update timed out after ${KIRO_UPDATE_TIMEOUT}s."
# DISABLED:     echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
# DISABLED:     return 1
# DISABLED:   fi
# DISABLED:
# DISABLED:   if [[ $status -ne 0 ]]; then
# DISABLED:     KIRO_SELF_UPDATE_RESULT="failed"
# DISABLED:     KIRO_SELF_UPDATE_REASON="Self-update failed: $(echo "$update_output" | tail -n1)"
# DISABLED:     echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
# DISABLED:     return 1
# DISABLED:   fi
# DISABLED:
# DISABLED:   KIRO_SELF_UPDATE_VERSION=$(get_kiro_local_version || true)
# DISABLED:   hinted_version=$(echo "$update_output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?' || true)
# DISABLED:
# DISABLED:   normalized_output=$(echo "$update_output" | tr '\n' ' ')
# DISABLED:
# DISABLED:   if [[ -z "$KIRO_SELF_UPDATE_VERSION" && -n "$hinted_version" ]]; then
# DISABLED:     KIRO_SELF_UPDATE_VERSION="$hinted_version"
# DISABLED:   fi
# DISABLED:
# DISABLED:   if grep -qiE 'no updates available|already up|latest version' <<<"$update_output"; then
# DISABLED:     KIRO_SELF_UPDATE_RESULT="up_to_date"
# DISABLED:     KIRO_SELF_UPDATE_REASON="${normalized_output:-Self-update reports current version.}"
# DISABLED:     KIRO_SELF_UPDATE_VERSION=${KIRO_SELF_UPDATE_VERSION:-$local_version}
# DISABLED:     return 0
# DISABLED:   fi
# DISABLED:
# DISABLED:   if [[ -n "$KIRO_SELF_UPDATE_VERSION" && -n "$local_version" && "$KIRO_SELF_UPDATE_VERSION" != "$local_version" ]]; then
# DISABLED:     KIRO_SELF_UPDATE_RESULT="updated"
# DISABLED:     KIRO_SELF_UPDATE_REASON="Updated from $local_version to $KIRO_SELF_UPDATE_VERSION"
# DISABLED:     return 0
# DISABLED:   fi
# DISABLED:
# DISABLED:   KIRO_SELF_UPDATE_RESULT="unknown"
# DISABLED:   KIRO_SELF_UPDATE_REASON="Self-update completed but status unclear"
# DISABLED:   return 0
# DISABLED: }

# DISABLED: get_kiro_local_version() {
# DISABLED:   local output version
# DISABLED:
# DISABLED:   if ! command -v kiro-cli &>/dev/null; then
# DISABLED:     return 1
# DISABLED:   fi
# DISABLED:
# DISABLED:   output=$(kiro-cli --version 2>/dev/null || true)
# DISABLED:   version=$(echo "$output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?')
# DISABLED:
# DISABLED:   if [[ -z "$version" ]]; then
# DISABLED:     output=$(kiro-cli version 2>/dev/null || true)
# DISABLED:     version=$(echo "$output" | grep -m1 -Eo '[0-9]+(\.[0-9]+)+(-[[:alnum:].]+)?')
# DISABLED:   fi
# DISABLED:
# DISABLED:   if [[ -n "$version" ]]; then
# DISABLED:     printf '%s' "$version"
# DISABLED:     return 0
# DISABLED:   fi
# DISABLED:
# DISABLED:   return 1
# DISABLED: }

### ========== CLAUDE CODE ==========
handle_claude_code() {
  echo -e "\n${CYAN}=== Claude Code (Anthropic, native nightly) ===${NC}"
  local local_version remote_version new_version
  local tmpfile
  tmpfile=$(mktemp)
  set +e

  if [[ -x "$HOME/.local/bin/claude" ]]; then
    local_version=$("$HOME/.local/bin/claude" --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo -e "${GREEN}Detected Claude Code version: $local_version ($HOME/.local/bin/claude)${NC}"
  elif command -v claude &>/dev/null; then
    local_version=$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo -e "${GREEN}Detected Claude Code version: $local_version ($(command -v claude))${NC}"
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
        new_version=$( ("$HOME/.local/bin/claude" --version 2>/dev/null || claude --version 2>/dev/null) | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
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

# DISABLED: ### ========== KIRO CLI ==========
# DISABLED: handle_kiro() {
# DISABLED:   echo -e "\n${CYAN}=== Kiro CLI (Amazon) ===${NC}"
# DISABLED:   local local_version="" new_version install_status installed=0
# DISABLED:   set +e
# DISABLED:
# DISABLED:   if command -v kiro-cli &>/dev/null; then
# DISABLED:     installed=1
# DISABLED:     if local_version=$(get_kiro_local_version); then
# DISABLED:       echo -e "${GREEN}Detected Kiro CLI version: $local_version${NC}"
# DISABLED:     else
# DISABLED:       local_version="unknown"
# DISABLED:       echo -e "${YELLOW}Detected Kiro CLI installation but unable to parse version.${NC}"
# DISABLED:     fi
# DISABLED:   fi
# DISABLED:
# DISABLED:   if (( ! installed )); then
# DISABLED:     echo -e "${YELLOW}Kiro CLI is not installed.${NC}"
# DISABLED:     install_kiro_from_deb
# DISABLED:     install_status=$?
# DISABLED:     new_version=$(get_kiro_local_version || true)
# DISABLED:     if [[ $install_status -ne 0 ]]; then
# DISABLED:       record_summary "Kiro CLI" "Installation failed"
# DISABLED:     elif [[ -n "$new_version" ]]; then
# DISABLED:       record_summary "Kiro CLI" "Installed new version $new_version"
# DISABLED:     else
# DISABLED:       record_summary "Kiro CLI" "Installed new version (unable to detect version)"
# DISABLED:     fi
# DISABLED:     set -e
# DISABLED:     return
# DISABLED:   fi
# DISABLED:
# DISABLED:   if run_kiro_self_update "$local_version"; then
# DISABLED:     case "$KIRO_SELF_UPDATE_RESULT" in
# DISABLED:       up_to_date)
# DISABLED:         record_summary "Kiro CLI" "Already up to date (${KIRO_SELF_UPDATE_VERSION:-$local_version})"
# DISABLED:         set -e
# DISABLED:         return
# DISABLED:         ;;
# DISABLED:       updated)
# DISABLED:         record_summary "Kiro CLI" "Updated via kiro-cli update from $local_version to ${KIRO_SELF_UPDATE_VERSION:-unknown}"
# DISABLED:         set -e
# DISABLED:         return
# DISABLED:         ;;
# DISABLED:       unknown)
# DISABLED:         echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
# DISABLED:         ;;
# DISABLED:     esac
# DISABLED:   else
# DISABLED:     echo -e "${YELLOW}${KIRO_SELF_UPDATE_REASON}${NC}"
# DISABLED:   fi
# DISABLED:
# DISABLED:   echo -e "${BLUE}Falling back to Kiro CLI package reinstall...${NC}"
# DISABLED:   install_kiro_from_deb
# DISABLED:   install_status=$?
# DISABLED:   new_version=$(get_kiro_local_version || true)
# DISABLED:   if [[ $install_status -ne 0 ]]; then
# DISABLED:     record_summary "Kiro CLI" "Package reinstall failed after kiro-cli update (${KIRO_SELF_UPDATE_REASON:-unknown reason})"
# DISABLED:   elif [[ -z "$new_version" ]]; then
# DISABLED:     record_summary "Kiro CLI" "Package reinstall completed but version unknown"
# DISABLED:   elif [[ "$new_version" == "$local_version" ]]; then
# DISABLED:     record_summary "Kiro CLI" "Package reinstall completed but version unchanged ($local_version)"
# DISABLED:   else
# DISABLED:     record_summary "Kiro CLI" "Updated from $local_version to $new_version via package"
# DISABLED:   fi
# DISABLED:   set -e
# DISABLED: }

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
  # DISABLED: handle_kiro
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
