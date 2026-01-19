---
description: Deep validation of preceding context - errors, assumptions, alignment, improvements
argument-hint: [focus_area]
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(find:*)
model: claude-opus-4-5-20251101
---

# Ultra-Validation Protocol

Think through each validation dimension systematically. Question every assumption. Cross-reference against actual codebase artifacts.

## Focus Area
$ARGUMENTS

If no focus specified, validate the entire preceding context (plan, code changes, discussion, or proposal).

<context_detection>
First, identify what you're validating:
- **Plan/Proposal**: Architecture design, implementation approach, technical spec
- **Code Changes**: Diff, new files, refactored code, PR
- **Discussion**: Requirements gathering, debugging session, design conversation
- **Configuration**: Environment setup, infrastructure, deployment config

Adapt your validation approach accordingly.
</context_detection>

<investigate_before_answering>
Never speculate about code you have not examined. Read relevant files before making claims. If uncertain, state what you need to investigate.
</investigate_before_answering>

## Validation Steps

### Step 1: Assumption Inventory
List every assumption in the preceding context. For each:
- **VALIDATED**: Confirmed by examining actual code/config/docs (cite file:line)
- **UNVALIDATED**: Not yet verified against codebase
- **CONTRADICTED**: Evidence suggests assumption is wrong

### Step 2: Error & Risk Scan
Examine for issues appropriate to the context type:

**For Code:**
- Logic errors, null handling, type mismatches
- Missing error handlers, unhandled promises
- Race conditions, async timing issues
- Security vulnerabilities, exposed secrets
- Performance issues, N+1 queries, memory leaks

**For Plans/Proposals:**
- Unstated dependencies or prerequisites
- Scope gaps or undefined edge cases
- Resource/timeline assumptions
- Integration risks with existing systems

**For Configuration:**
- Missing environment variables
- Security misconfigurations
- Incompatible version constraints

### Step 3: Omission Detection
Identify what's missing from the preceding context:
- Incomplete implementations or undefined behaviors
- Missing error handling for edge cases
- Absent tests for critical paths
- Undocumented assumptions

### Step 4: Codebase Alignment
Compare against existing patterns:
- Does approach match existing code structure and conventions?
- Are we violating established patterns?
- Will changes integrate cleanly or require broader refactoring?
- Are we introducing inconsistencies?

### Step 5: Enhancement Opportunities
- Can we reduce complexity?
- Are there safer, faster, or cleaner approaches?
- Can we consolidate duplicate logic?
- What optimizations are being missed?

## Output Format

**🚨 CRITICAL** (Must resolve before proceeding)
- Risk: [why critical]
- Action: [specific next step]

**❌ ERRORS FOUND** (Severity: HIGH/MEDIUM/LOW)
- Location: [file:line, section, or concept]
- Impact: [what breaks or fails]
- Fix: [concrete solution]

**⚠️ ALIGNMENT ISSUES** (Conflicts with codebase or conventions)
- Current: [what exists]
- Proposed: [what conflicts]
- Resolution: [how to align]

**📋 MISSING** (Gaps needing attention)

**💡 IMPROVEMENTS** (Better alternatives with expected benefit)

**✅ VALIDATED** (Confirmed with citations)

**❓ NEEDS VALIDATION** (Requires investigation)
