---
name: standup
description: "Daily standup summary: PRs posted in #reviewit yesterday + current Linear In Progress tickets"
allowed-tools: mcp__claude_ai_Slack__slack_read_channel, mcp__linear__list_issues, mcp__linear__save_issue
---

# Standup

Generate a daily standup summary from two sources:

1. **PRs posted for review** — your messages in `#reviewit` from yesterday
2. **In Progress tickets** — your current Linear issues in "In Progress" state

## Slack: #reviewit PRs

- Channel ID: `C016PESNS56`
- Your Slack user ID: `U0AEAPS47EX`
- Read messages from yesterday (midnight to midnight, Pacific time)
- Filter to messages authored by you (Brenna Martenson, `U0AEAPS47EX`)
- For each PR message, extract:
  - PR URL
  - Brief description (from the bullet points)
  - Linear issue reference if present
  - Reaction summary (checkmarks = approved, eyes = in review)

### Timestamp calculation

"Yesterday" means the previous calendar day in Pacific time (UTC-7 in PDT, UTC-8 in PST).

- `oldest` = yesterday 00:00:00 Pacific → convert to Unix timestamp
- `latest` = today 00:00:00 Pacific → convert to Unix timestamp

## Linear: In Progress tickets

- Use `list_issues` with `assignee: "me"` and `state: "In Progress"`
- For each ticket, show:
  - Issue ID and title
  - Priority if set
  - Milestone if set

## Output format

```
Standup — YYYY-MM-DD
════════════════════

PRs posted for review (yesterday)
─────────────────────────────────
1. repo#NNN — Brief description (INT-XXX)
   Reactions: [checkmark/eyes/rocket summary]

2. repo#NNN — Brief description (INT-XXX)
   Reactions: [summary]

(none posted) — if no messages found

In Progress
───────────
- INT-XXX (Priority) — Title
  Milestone: milestone name
- INT-YYY — Title
```

Keep it scannable. This is read at the start of a workday.
