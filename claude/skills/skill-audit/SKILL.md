---
name: skill-audit
description: "Audit user-level skills for improvements — naming, gaps, redundancy, and enhancement opportunities"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

Audit all user-level skills (in `~/.claude/skills/`) and suggest improvements.
This is a meta-skill for maintaining skill quality over time.

## Step 1 — Inventory

List all skill directories in `~/.claude/skills/`. For each, read the SKILL.md
and extract:

- Name and description
- Allowed tools
- Whether it has `disable-model-invocation`
- Approximate line count / complexity
- Whether it has a README.md

Present as a compact table:

| Skill | Description | Tools | Lines | README |
| ----- | ----------- | ----- | ----- | ------ |

## Step 2 — Analyze each skill

For each skill, evaluate against these criteria:

### Naming

- Is the name short, memorable, and consistent with the naming convention?
- Does it use the `verb-noun` or `noun` pattern used by other skills?
- Would a shorter alias improve usability?

### Completeness

- Does it handle the common happy path well?
- Does it handle common edge cases? (errors, empty states, unusual input)
- Are there steps where the user is asked to do something the skill could do itself?
- Does it reference project conventions (CLAUDE.md) where relevant?

### Workflow fit

- Does it match how the user actually uses it? (check conversation history
  and memory for usage patterns if available)
- Are there manual steps before/after invoking the skill that could be folded in?
- Could it compose with other skills (e.g., rebase calling smart-rebase first)?

### Safety

- Does it have appropriate guardrails for destructive actions?
- Does it confirm before irreversible operations?
- Does it avoid doing things it shouldn't (force-push, delete without asking)?

### Overlap and gaps

- Does it overlap with another skill? Could they be merged?
- Is there a workflow the user does regularly that has no skill?
- Are there org-level (`hb:*`) skills that duplicate or conflict with user skills?

## Step 3 — Report

For each skill, output a section:

```
### /skill-name

**Rating:** Good / Needs work / Solid but could be great

**What it does well:**
- ...

**Suggested improvements:**
1. ...
2. ...

**Effort:** Quick fix / Medium / Significant rework
```

Then add a final section:

```
### Missing skills

Workflows you do regularly that don't have a skill yet:
- ...
```

## Step 4 — Act

After presenting the report, ask:

> "Want me to apply any of these improvements? Pick numbers or say 'all quick fixes'."

For each improvement the user approves:

1. Edit the SKILL.md in place
2. Show a brief diff summary of what changed
3. Move to the next one

## Principles

- Skills should be opinionated — they encode how the user works, not how
  things could theoretically work
- Shorter is better — a 20-line skill that nails the workflow beats an
  80-line skill that covers every edge case
- Skills should reduce friction, not add ceremony
- If a skill asks "are you sure?" for something the user always says yes to,
  remove the question
- User-level skills should complement org-level skills, not duplicate them
