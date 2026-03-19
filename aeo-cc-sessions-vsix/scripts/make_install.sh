#!/usr/bin/env bash
set -euo pipefail

VSIX="$(find . -maxdepth 1 -name '*.vsix' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)"
if [[ -z "$VSIX" ]]; then
  echo "No .vsix file found — run 'make package' first" >&2
  exit 1
fi

VERSION="$(node -p "require('./package.json').version")"
EXT_ID="aeyeops.aeo-vsc-cc-sessions"
EXT_REL="${EXT_ID}-${VERSION}"

# Detect environment
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=true
fi

IS_LINUX=false
if [[ "$(uname -s)" == "Linux" ]]; then
  IS_LINUX=true
fi

echo "Environment: WSL=${IS_WSL} Linux=${IS_LINUX}"

# Build target tuples: CLI|EXT_BASE|PROFILE_BASE
declare -a TARGETS=()

if [[ "$IS_WSL" == true ]]; then
  # WSL: Windows VS Code connects via Remote WSL, server lives on WSL side
  # Resolve Windows %APPDATA% for Windows-side profile registration
  # cmd.exe may emit UNC path warnings before the actual value — extract the C:\... path
  WIN_APPDATA="$(cmd.exe /c "echo %APPDATA%" 2>&1 | grep -oP '[A-Z]:\\.*' | tr -d '\r')"
  WIN_APPDATA_WSL="$(wslpath -u "$WIN_APPDATA")"
  echo "Windows APPDATA: $WIN_APPDATA_WSL"

  TARGETS+=(
    "code-insiders|$HOME/.vscode-server-insiders|$HOME/.vscode-server-insiders/data/User/profiles|$WIN_APPDATA_WSL/Code - Insiders/User/profiles"
    "code|$HOME/.vscode-server|$HOME/.vscode-server/data/User/profiles|$WIN_APPDATA_WSL/Code/User/profiles"
  )
elif [[ "$IS_LINUX" == true ]]; then
  # Linux native: VS Code runs locally (no Windows-side profiles)
  TARGETS+=(
    "code-insiders|$HOME/.vscode-insiders|$HOME/.config/Code - Insiders/User/profiles|"
    "code|$HOME/.vscode|$HOME/.config/Code/User/profiles|"
  )
else
  echo "Unsupported platform — install manually with: code --install-extension $VSIX" >&2
  exit 1
fi

# register_profiles PROFILE_BASE EXT_DIR LABEL
#   Register extension in all profile extensions.json under PROFILE_BASE
register_profiles() {
  local profile_base="$1" ext_dir="$2" label="$3"
  [[ -d "$profile_base" ]] || return 0

  for profile in "$profile_base"/*/; do
    local profile_ext="${profile}extensions.json"
    [[ -f "$profile_ext" ]] || continue

    if grep -q "$EXT_ID" "$profile_ext"; then
      echo "Already registered in ${label} profile $(basename "$profile")"
    else
      echo "Registering in ${label} profile $(basename "$profile") ..."
      node -e "
const fs = require('fs');
const p = '$profile_ext';
const d = JSON.parse(fs.readFileSync(p, 'utf8'));
if (d.some(e => e.identifier?.id === '$EXT_ID')) process.exit(0);
d.push({
  identifier: { id: '$EXT_ID' },
  version: '$VERSION',
  location: { '\$mid': 1, path: '$ext_dir', scheme: 'file' },
  relativeLocation: '$EXT_REL',
  metadata: {
    installedTimestamp: Date.now(),
    source: 'vsix',
    isApplicationScoped: false,
    isMachineScoped: false,
    isBuiltin: false,
    pinned: false
  }
});
fs.writeFileSync(p, JSON.stringify(d, null, '\t'));
console.log('Registered');
"
    fi
  done
}

# install_extension CLI EXT_BASE WSL_PROFILE_BASE WIN_PROFILE_BASE
#   1. Try CLI --install-extension
#   2. On failure, fall back to manual VSIX extraction
#   3. Register in all WSL-side and Windows-side profile extensions.json files
install_extension() {
  local cli="$1" ext_base="$2" wsl_profile_base="$3" win_profile_base="$4"
  local ext_dir="${ext_base}/extensions/${EXT_REL}"

  echo ""
  echo "=== Installing for $cli ==="

  # Step 1: Install via CLI, fall back to manual extraction
  # Some broken VS Code servers (e.g. stable 1.109.2 missing cookie dep) crash
  # server-main.js but the wrapper CLI still exits 0 — verify the extension dir exists.
  "$cli" --install-extension "$VSIX" --force 2>&1 || true

  if [[ -d "$ext_dir" && -f "$ext_dir/package.json" ]]; then
    echo "CLI install succeeded"
  else
    echo "CLI install failed or incomplete — falling back to manual extraction"
    mkdir -p "$ext_dir"
    # VSIX is a zip; extract the extension/ subtree into the target
    unzip -o -q "$VSIX" "extension/*" -d "$ext_dir.tmp"
    # vsce packages files under extension/ prefix — move contents up
    cp -a "$ext_dir.tmp/extension/." "$ext_dir/"
    rm -rf "$ext_dir.tmp"
    echo "Extracted to $ext_dir"
  fi

  # Step 2: Register in WSL-side profiles
  register_profiles "$wsl_profile_base" "$ext_dir" "WSL"

  # Step 3: Register in Windows-side profiles (WSL only)
  if [[ -n "$win_profile_base" ]]; then
    register_profiles "$win_profile_base" "$ext_dir" "Windows"
  fi
}

installed=0

for target in "${TARGETS[@]}"; do
  IFS='|' read -r CLI EXT_BASE WSL_PROFILE_BASE WIN_PROFILE_BASE <<< "$target"

  if ! command -v "$CLI" >/dev/null 2>&1; then
    echo "Skipping $CLI — not found in PATH"
    continue
  fi
  if [[ ! -d "$EXT_BASE" ]]; then
    echo "Skipping $CLI — $EXT_BASE does not exist"
    continue
  fi

  install_extension "$CLI" "$EXT_BASE" "$WSL_PROFILE_BASE" "$WIN_PROFILE_BASE"
  installed=$((installed + 1))
done

if [[ "$installed" -eq 0 ]]; then
  echo ""
  echo "No VS Code installations found. Install manually with:"
  echo "  code --install-extension $VSIX"
  echo "  code-insiders --install-extension $VSIX"
  exit 1
fi

echo ""
echo "Done. Reload VS Code (Ctrl+Shift+P → 'Developer: Reload Window') to activate."
