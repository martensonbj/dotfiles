# skill-audit

Audit all user-level skills for improvements. Evaluates naming, completeness, workflow fit, safety, overlap, and identifies missing skills.

## How to Use

```
/skill-audit
```

No arguments. Scans every skill in `~/.claude/skills/`.

## How It Works

1. **Inventory** — Reads every `SKILL.md` in your skills directory and presents a summary table (name, description, tools, complexity, README status).
2. **Analyze** — Evaluates each skill against naming conventions, completeness, workflow fit, safety guardrails, and overlap with org-level (`hb:*`) skills.
3. **Report** — Rates each skill (Good / Needs work / Solid but could be great) with specific improvement suggestions and effort estimates.
4. **Act** — Asks which improvements to apply. Say "all quick fixes" or pick by number.

## Examples

```
/skill-audit

### /commit-staged
Rating: Good
What it does well: Clean, focused, delegates to hb:git conventions
Suggested improvements:
1. Add --amend flag support for quick amendments
Effort: Quick fix

### /transfer-context
Rating: Needs work
What it does well: Solves a real pain point
Suggested improvements:
1. Auto-detect context usage % instead of requiring manual invocation
2. Include active task list in the transfer
Effort: Medium

### Missing skills
- No skill for "check CI status and fix failures" (you do this manually with gh + circleci)
- No skill for "sync fork" or "update dependencies"

Want me to apply any of these improvements? Pick numbers or say "all quick fixes".
```

## See Also

- [SKILL.md](./SKILL.md) — AI agent instructions
