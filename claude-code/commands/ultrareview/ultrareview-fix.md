---
description: Systematically address all ultrareview findings - errors, alignment issues, gaps, improvements, and unvalidated assumptions
argument-hint: [scope]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
model: claude-opus-4-5-20251101
---

# Ultra-Fix Protocol

You are addressing findings from a preceding ultrareview validation. Work through each finding systematically, implementing fixes with precision and completeness.

## Scope
$ARGUMENTS

If no scope specified, address ALL findings from the most recent ultrareview output in the conversation.

<context_detection>
Determine what you're fixing based on the preceding ultrareview:

**Plan Mode Indicators:**
- Ultrareview analyzed a Plan/Proposal
- Findings reference architecture, approach, or design decisions
- The plan file exists in `.claude/plans/` or similar location
- No implementation code has been written yet

**Implementation Mode Indicators:**
- Ultrareview analyzed Code Changes or existing implementation
- Findings reference specific `file:line` locations
- Code files exist and need modification
- Tests or configurations need updates

Adapt your fix strategy accordingly.
</context_detection>

<investigate_before_fixing>
Before modifying any artifact:
1. Read the current state of files you intend to change
2. Understand the context around each finding
3. Verify the finding is still applicable (code may have changed since ultrareview ran)
4. Plan fixes that don't introduce new issues
</investigate_before_fixing>

<parsing_ultrareview_output>
Extract findings from the preceding ultrareview using these markers:

| Marker | Category | Action Required |
|--------|----------|-----------------|
| 🚨 CRITICAL | Blockers | Fix immediately, blocks all other work |
| ❌ ERRORS FOUND | Bugs/Issues | Fix by severity (HIGH→MEDIUM→LOW) |
| ⚠️ ALIGNMENT ISSUES | Pattern conflicts | Align with codebase conventions |
| 📋 MISSING | Gaps | Fill identified gaps |
| ❓ NEEDS VALIDATION | Uncertainties | Investigate, then fix or dismiss |
| 💡 IMPROVEMENTS | Enhancements | Implement beneficial changes |

Each finding typically contains:
- **Location:** `file:line` or section reference
- **Impact:** What breaks or fails
- **Fix:** Concrete solution (often with code snippet)

Preserve this structure when tracking progress.
</parsing_ultrareview_output>

## Fix Protocol

### Phase 1: Extract and Prioritize Findings

Parse the ultrareview output and use the **TodoWrite tool** to create a structured todo list for tracking progress:

**Priority Order:**
1. 🚨 CRITICAL - Block all other work until resolved
2. ❌ ERRORS (HIGH) - Fix before proceeding
3. ❌ ERRORS (MEDIUM) - Address systematically
4. ❌ ERRORS (LOW) - Address systematically
5. ⚠️ ALIGNMENT ISSUES - Resolve conflicts with codebase
6. 📋 MISSING - Fill identified gaps
7. ❓ NEEDS VALIDATION - Investigate and resolve uncertainty
8. 💡 IMPROVEMENTS - Implement beneficial enhancements

Skip ✅ VALIDATED items - these confirm correct behavior and need no action.

**If ultrareview reported no actionable findings** (only ✅ VALIDATED), confirm the context is ready and exit without changes.

**If findings conflict** (e.g., two fixes require contradictory changes), address in priority order and document the conflict resolution in the summary.

### Phase 2: Plan-Mode Fixes

<plan_fixes>
When fixing a plan or proposal:

**For Each Finding:**
1. Locate the relevant section in the plan file
2. Understand the original intent
3. Craft a revision that addresses the finding while preserving intent
4. Ensure revision integrates with surrounding plan content

**Fix Categories:**

- **CRITICAL/ERRORS**: Rewrite affected sections with correct approach
- **ALIGNMENT ISSUES**: Revise to match existing codebase patterns (cite examples)
- **MISSING**: Add new sections covering gaps (scope, edge cases, dependencies)
- **NEEDS VALIDATION**: Either investigate and document findings, or add explicit validation steps to the plan
- **IMPROVEMENTS**: Incorporate better approaches with rationale

**Plan Coherence Check:**
After all fixes, verify the plan still flows logically and consistently.
</plan_fixes>

### Phase 3: Implementation-Mode Fixes

<implementation_fixes>
When fixing code or configuration:

**For Each Finding:**
1. Read the target file(s) completely
2. Understand the existing implementation context
3. Design a fix that integrates cleanly
4. Implement with minimal disruption to working code
5. Verify fix doesn't break existing functionality

**Fix Categories:**

- **CRITICAL**: Stop and fix immediately before any other changes
- **ERRORS**:
  - Logic errors → Correct the logic, add defensive checks
  - Null handling → Add guards, use optional chaining
  - Type mismatches → Fix types, add validation
  - Missing error handlers → Add try/catch, error boundaries
  - Race conditions → Add synchronization, use proper async patterns
  - Security issues → Apply security best practices, sanitize inputs

- **ALIGNMENT ISSUES**:
  - Pattern violations → Refactor to match existing patterns
  - Naming inconsistencies → Rename to match conventions
  - Structure conflicts → Reorganize to align with codebase

- **MISSING**:
  - Incomplete implementations → Complete the implementation
  - Missing edge cases → Add handling for identified cases
  - Absent tests → Write tests for critical paths
  - Missing documentation → Add inline comments where non-obvious

- **NEEDS VALIDATION**:
  - Investigate the uncertainty first
  - If valid concern: implement fix
  - If false positive: document why (in code comment if relevant)

- **IMPROVEMENTS**:
  - Evaluate cost/benefit of each improvement
  - Implement those with clear benefit and low risk
  - Skip or defer complex improvements (note in summary)
</implementation_fixes>

### Phase 4: Verification

<verification>
After implementing all fixes:

**For Plans:**
- Re-read the complete plan
- Verify internal consistency
- Confirm all findings have been addressed
- Check that plan scope hasn't inadvertently changed

**For Implementations:**
- Run relevant tests if available
- Check for new linting/type errors
- Verify fixed code integrates with surrounding code
- Ensure no regressions in related functionality
</verification>

## Output Format

Use the todo list to track progress. For each finding:

```
[ ] Finding: [brief description]
    Status: [pending | in_progress | completed | skipped]
    Action: [what was done]
    Location: [file:line or plan section]
```

### Summary Report

After all fixes, provide:

**✅ RESOLVED**
- [List each addressed finding with brief description of fix]

**⏭️ DEFERRED** (if any)
- [Finding]: [Reason for deferral]

**⚠️ INTRODUCED CHANGES**
- [Any additional changes made beyond the findings]

**🔍 VERIFICATION STATUS**
- Tests: [pass/fail/not run]
- Lint: [clean/issues]
- Integration: [verified/needs manual check]

## Execution Rules

1. **One finding at a time**: Mark todo in_progress, fix, verify, mark completed
2. **Atomic changes**: Each fix should be independently valid
3. **No scope creep**: Only address items from ultrareview findings
4. **Document decisions**: If you skip or defer something, explain why
5. **Preserve intent**: Fixes should solve problems without changing goals
6. **Use provided code snippets**: When ultrareview provides a fix with code, use it as the starting point
7. **Verify file:line references**: Ultrareview cites specific locations - read those exact lines before editing

<post_fix_workflow>
After completing all fixes, inform the user they can run `/ultrareview` again to:
- Verify all fixes were correctly implemented
- Catch any issues introduced by the fixes
- Confirm the codebase is ready for the next step

This creates an iterative validation loop: ultrareview → ultrareview-fix → ultrareview → ...
</post_fix_workflow>
