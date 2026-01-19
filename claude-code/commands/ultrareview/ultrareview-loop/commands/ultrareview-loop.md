---
description: "Start automated ultrareview validation loop"
argument-hint: "[focus_area] [--max-iterations N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ultrareview-loop.sh:*)"]
---

# Ultrareview Loop

<token_context>
IMPORTANT: Forget any previous ultrareview-loop tokens.
Read the token from the setup script output below - that is your ONLY valid loop token.
</token_context>

Execute the setup script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ultrareview-loop.sh" $ARGUMENTS
```

The setup script outputs:
- Loop token (note this - it identifies YOUR loop session)
- Configuration summary
- Stop instructions

<loop_instructions>
Now run /ultrareview on the preceding context to begin the validation cycle.

The loop will automatically:
1. Run ultrareview -> detect findings
2. Run ultrareview-fix -> address findings
3. Run ultrareview -> verify fixes
4. Repeat until no actionable findings remain

To stop manually: Ask me to "stop the ultrareview loop" and I will delete the state file.
</loop_instructions>
