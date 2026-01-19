#!/bin/bash

# Ultrareview Loop Stop Hook
# Prevents session exit when an ultrareview-loop is active
# Alternates between ultrareview and ultrareview-fix phases

set -euo pipefail

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)

# Check if ultrareview-loop is active
STATE_FILE=".claude/ultrareview-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  # No active loop - allow exit
  exit 0
fi

# Parse markdown frontmatter (YAML between ---) and extract values
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
TOKEN=$(echo "$FRONTMATTER" | grep '^token:' | sed 's/token: *//' | sed 's/^"\(.*\)"$/\1/')
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
INITIAL_FOCUS=$(echo "$FRONTMATTER" | grep '^initial_focus:' | sed 's/initial_focus: *//' | sed 's/^"\(.*\)"$/\1/')

# Token validation - check if this is our loop
LOOP_TOKEN="${ULTRAREVIEW_LOOP_TOKEN:-}"
if [[ -z "$LOOP_TOKEN" ]] || [[ "$LOOP_TOKEN" != "$TOKEN" ]]; then
  # Not our loop (different session or no token) - allow exit
  exit 0
fi

# Validate numeric fields before arithmetic operations
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ultrareview loop: State file corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: 'iteration' field is not a valid number (got: '$ITERATION')" >&2
  echo "" >&2
  echo "   Ultrareview loop is stopping. Run /ultrareview-loop again to start fresh." >&2
  rm "$STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ultrareview loop: State file corrupted" >&2
  echo "   File: $STATE_FILE" >&2
  echo "   Problem: 'max_iterations' field is not a valid number (got: '$MAX_ITERATIONS')" >&2
  echo "" >&2
  echo "   Ultrareview loop is stopping. Run /ultrareview-loop again to start fresh." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ultrareview loop: Max iterations ($MAX_ITERATIONS) reached."
  rm "$STATE_FILE"
  exit 0
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Ultrareview loop: Transcript file not found" >&2
  echo "   Expected: $TRANSCRIPT_PATH" >&2
  echo "   Ultrareview loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Read last assistant message from transcript (JSONL format)
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Ultrareview loop: No assistant messages found in transcript" >&2
  echo "   Ultrareview loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
if [[ -z "$LAST_LINE" ]]; then
  echo "⚠️  Ultrareview loop: Failed to extract last assistant message" >&2
  echo "   Ultrareview loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Parse JSON with error handling
LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>&1)

if [[ $? -ne 0 ]]; then
  echo "⚠️  Ultrareview loop: Failed to parse assistant message JSON" >&2
  echo "   Error: $LAST_OUTPUT" >&2
  echo "   Ultrareview loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Ultrareview loop: Assistant message contained no text content" >&2
  echo "   Ultrareview loop is stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check for actionable findings in the last output
# Markers: 🚨 CRITICAL, ❌ ERRORS FOUND, ⚠️ ALIGNMENT ISSUES, 📋 MISSING, 💡 IMPROVEMENTS, ❓ NEEDS VALIDATION
HAS_ACTIONABLE=false

# Check for each actionable marker (emoji + text for robustness)
if echo "$LAST_OUTPUT" | grep -q '🚨.*CRITICAL\|CRITICAL.*🚨'; then
  HAS_ACTIONABLE=true
elif echo "$LAST_OUTPUT" | grep -q '❌.*ERRORS\|ERRORS.*❌'; then
  HAS_ACTIONABLE=true
elif echo "$LAST_OUTPUT" | grep -q '⚠️.*ALIGNMENT\|ALIGNMENT.*⚠️'; then
  HAS_ACTIONABLE=true
elif echo "$LAST_OUTPUT" | grep -q '📋.*MISSING\|MISSING.*📋'; then
  HAS_ACTIONABLE=true
elif echo "$LAST_OUTPUT" | grep -q '💡.*IMPROVEMENT\|IMPROVEMENT.*💡'; then
  HAS_ACTIONABLE=true
elif echo "$LAST_OUTPUT" | grep -q '❓.*NEEDS VALIDATION\|VALIDATION.*❓'; then
  HAS_ACTIONABLE=true
fi

# Decision logic based on phase
if [[ "$PHASE" == "review" ]]; then
  if [[ "$HAS_ACTIONABLE" == "false" ]]; then
    # No actionable findings after review - loop complete!
    echo "✅ Ultrareview loop complete: No actionable findings detected."
    echo "   Iterations: $ITERATION"
    rm "$STATE_FILE"
    exit 0
  fi

  # Has findings - switch to fix phase
  NEXT_PHASE="fix"
  NEXT_PROMPT="Run /ultrareview-fix to address the findings from the ultrareview."
else
  # After fix phase, always go back to review
  NEXT_PHASE="review"
  if [[ "$INITIAL_FOCUS" != "null" ]] && [[ -n "$INITIAL_FOCUS" ]]; then
    NEXT_PROMPT="Run /ultrareview $INITIAL_FOCUS to verify the fixes."
  else
    NEXT_PROMPT="Run /ultrareview to verify the fixes."
  fi
fi

# Update state file
NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${STATE_FILE}.tmp.$$"

# Update both iteration and phase
sed -e "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
    -e "s/^phase: .*/phase: $NEXT_PHASE/" \
    "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Build system message
SYSTEM_MSG="🔄 Ultrareview loop iteration $NEXT_ITERATION (phase: $NEXT_PHASE) | Token: $TOKEN"

# Output JSON to block the stop and feed next phase prompt
jq -n \
  --arg prompt "$NEXT_PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
