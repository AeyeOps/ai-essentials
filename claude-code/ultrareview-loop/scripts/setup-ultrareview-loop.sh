#!/bin/bash

# Ultrareview Loop Setup Script
# Creates state file and session token for ultrareview loop

set -euo pipefail

# Parse arguments
FOCUS_PARTS=()
MAX_ITERATIONS=10

# Parse options and positional arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ultrareview Loop - Automated validation cycle

USAGE:
  /ultrareview-loop [FOCUS...] [OPTIONS]

ARGUMENTS:
  FOCUS...    Initial focus area for ultrareview (passed to first /ultrareview)

OPTIONS:
  --max-iterations <n>    Maximum iterations before auto-stop (default: 10)
  -h, --help              Show this help message

DESCRIPTION:
  Starts an automated ultrareview validation loop. The stop hook alternates
  between /ultrareview and /ultrareview-fix until no actionable findings remain.

  The loop detects these actionable markers:
    - 🚨 CRITICAL
    - ❌ ERRORS FOUND
    - ⚠️ ALIGNMENT ISSUES
    - 📋 MISSING
    - 💡 IMPROVEMENTS
    - ❓ NEEDS VALIDATION

  When none are found (only ✅ VALIDATED or empty), the loop completes.

EXAMPLES:
  /ultrareview-loop "the API changes"
  /ultrareview-loop --max-iterations 15 "authentication flow"
  /ultrareview-loop  (validates entire preceding context)

STOPPING:
  - Automatically when no actionable findings remain
  - Automatically when --max-iterations is reached
  - Manually: ask "stop the ultrareview loop" (Claude deletes state file)
  - Manually: rm .claude/ultrareview-loop.local.md

MONITORING:
  head -10 .claude/ultrareview-loop.local.md
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --max-iterations requires a number argument" >&2
        echo "" >&2
        echo "   Valid examples:" >&2
        echo "     --max-iterations 10" >&2
        echo "     --max-iterations 20" >&2
        echo "" >&2
        echo "   You provided: --max-iterations (with no number)" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: --max-iterations must be a positive integer, got: $2" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    *)
      # Non-option argument - collect as focus parts
      FOCUS_PARTS+=("$1")
      shift
      ;;
  esac
done

# Join focus parts with spaces
INITIAL_FOCUS="${FOCUS_PARTS[*]:-}"

# Generate unique session token (ulr-<8-char-uuid>)
TOKEN="ulr-$(cat /proc/sys/kernel/random/uuid | cut -c1-8)"

# Create state file with YAML frontmatter
mkdir -p .claude

# Quote initial_focus for YAML if it contains special chars
if [[ -n "$INITIAL_FOCUS" ]]; then
  INITIAL_FOCUS_YAML="\"$INITIAL_FOCUS\""
else
  INITIAL_FOCUS_YAML="null"
fi

cat > .claude/ultrareview-loop.local.md <<EOF
---
active: true
token: "$TOKEN"
iteration: 1
max_iterations: $MAX_ITERATIONS
phase: review
initial_focus: $INITIAL_FOCUS_YAML
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---
EOF

# Write token to CLAUDE_ENV_FILE for session environment
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo "ULTRAREVIEW_LOOP_TOKEN=$TOKEN" >> "$CLAUDE_ENV_FILE"
fi

# Output setup confirmation
cat <<EOF
🔄 Ultrareview loop activated!

Token: $TOKEN
Iteration: 1
Max iterations: $MAX_ITERATIONS
Phase: review
Focus: $(if [[ -n "$INITIAL_FOCUS" ]]; then echo "$INITIAL_FOCUS"; else echo "(entire context)"; fi)

The loop will cycle: ultrareview → ultrareview-fix → ultrareview → ...
until no actionable findings remain (no 🚨❌⚠️📋💡❓ markers).

To stop manually: ask "stop the ultrareview loop"
To monitor: head -10 .claude/ultrareview-loop.local.md
EOF
