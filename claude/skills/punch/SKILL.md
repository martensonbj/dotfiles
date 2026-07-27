---
name: punch
description: >-
  Morning punchlist. Gathers yesterday's activity, where you left off, in-flight
  work, and carryover from the prior punchlist into an interactive HTML doc with
  a paste-ready standup. Use at the start of a workday or when planning the day.
  Commands: (none) · linear · note <text> · sync · help
argument-hint: "[linear | note <text> | sync]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, ToolSearch, mcp__claude_ai_Google_Calendar__list_events, mcp__claude_ai_Linear__list_issues, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Slack__slack_read_thread, mcp__claude_ai_Slack__slack_search_public_and_private
---

# Punch

One command in the morning → an interactive HTML punchlist + a paste-ready
standup. Unfinished items carry over day to day.

## Constants

- **GitHub handle**: `martensonbj` (Brenna Martenson — NOT `mkitt`, who is
  Matt Kitt; ignore any global CLAUDE.md claim to the contrary)
- **Slack user ID**: `U0AEAPS47EX` (Brenna Martenson)
- **#reviewit channel ID**: `C016PESNS56`
- **Reaction convention** in #reviewit: ✅/white_check_mark = approved,
  👀/eyes = in review
- **Repos root**: `~/Sites/homebotapp/` — every direct subdirectory with a
  `.git` is in scope. Skip review clones (`surfaces-reviews`) for "my work"
  signals; they hold other people's branches.
- **State dir**: `~/.claude/punch/` (create on first run)
  - `PUNCH-YYYY-MM-DD.html` — dated punchlists
  - `PUNCH.html` — symlink to the latest (stable bookmark target)
  - `tomorrow.md` — queued notes for the next run
- **Template**: `template.html` in this skill's directory

## Commands

Parse the first word of `$ARGUMENTS`:

- *(empty)* — full morning run (below)
- `note <text>` — append `- <text> _(added YYYY-MM-DD HH:MM)_` to
  `~/.claude/punch/tomorrow.md` (create if missing), confirm in one line, stop.
  Do NOT run the full gather.
- `sync` — end-of-day state sync. The user has clicked **Copy as Markdown**
  in the doc; the export is on the clipboard. Run `pbpaste`, parse the
  `- [x]/- [ ]` lines and their `<!-- id:… -->` comments, and flip the
  matching items' `data-done` attributes in today's `PUNCH-*.html` via Edit.
  If notes lines are pasted along with it (or the user pastes the export as
  the argument instead), treat any `/punch note …` lines as `note` commands
  too. Confirm with a one-line summary (`synced: 7 done, 4 open`), stop.
  If `pbpaste` doesn't look like a punch export, say so and stop — don't
  guess.
- `linear` — deep Linear-only triage punchlist (below). No git/GitHub/Slack/
  Calendar gather, no carryover, no sync — Linear is the state store and every
  run re-derives from it.
- `help` — print the command list and section map, stop.

## Linear Triage Run (`/punch linear`)

A deep pass over MY Linear world only. Load `mcp__claude_ai_Linear__list_issues`
via ToolSearch, then gather (parallel where possible):

- `assignee: "me"` for each state type: `started`, `unstarted`, plus
  `completed` with `updatedAt: -P2D` (context only)
- Issues I created that are unassigned or assigned elsewhere but stalled
  (`createdBy` me via query if needed — best effort, skip if noisy)

Bucket into sections (this replaces the standard section set — same HTML
shell, same item markup, `data-ref` = the Linear issue URL):

1. **SLA / queue jumpers** — anything with `slaBreachesAt` set or priority
   Urgent. Note shows time-to-breach.
2. **In Progress — active** — started, touched within 7 days, ordered by
   priority then SLA then recency. Note: what state it's really in (PR open?
   In QA? — use `status` verbatim).
3. **In Progress — stale** — started but untouched 7+ days. These are the
   triage targets: the note should pose the question (still real? → backlog?
   close? hand off?).
4. **In Review / QA — needs a nudge or a verify** — statuses like In Review,
   In QA. Checking the box = verified or nudged.
5. **Unstarted — committed** — unstarted High/Urgent or in the current cycle.
   Order by priority.
6. **Hygiene** — umbrella tickets that may be closeable, duplicates,
   issues whose milestone/cycle looks wrong. Judgment section; keep short.

Output: `~/.claude/punch/TRIAGE-YYYY-MM-DD.html` from the same
`template.html` — repurpose the shell: standup section header becomes
"Triage summary" (a 3–5 line plain-text read of the state of my board:
counts per bucket, oldest stale item, nearest SLA), Yesterday section becomes
"Recently completed (context)", Notes section stays as-is. Update the
`{{DATE_*}}` tokens and STORAGE_KEY (`punch-triage-YYYY-MM-DD`). `open` when
written. No symlink, no carryover parsing, no `tomorrow.md` drain.

Terminal digest: counts per bucket + the single most urgent triage call.
This run never modifies Linear — it proposes; you act in Linear (or ask in
the session and I'll use the Linear tools on request).

## Morning Run

### 0 — Setup

Batch-load MCP tools up front with `ToolSearch` so the gather phase doesn't
stall: `select:mcp__claude_ai_Linear__list_issues,mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_channel,mcp__claude_ai_Google_Calendar__list_events`.

**Source detection**: only query what's connected. Local git and `gh` are
always available. If a Linear/Slack/Calendar MCP tool fails to load, skip that
source silently — never error, never tell the user to connect something.
A punchlist built from git + GitHub alone is still useful.

**Workday logic**: "yesterday" = last workday. Tue–Fri → previous day.
Monday → Friday through Sunday. After a holiday → last workday before it.

### 1 — Read state

- Find the most recent `~/.claude/punch/PUNCH-*.html` older than today
  (there may be a gap — weekend, PTO). This is the **prior punchlist**.
- Read `~/.claude/punch/tomorrow.md` if it exists — these are **queued notes**.

### 2 — Gather (run sources in parallel)

Use background agents (`run_in_background`) for the independent sources and
collect results. Each source maps to punchlist sections:

**Local git** (Bash, per repo under the repos root):

- current branch, `git status --porcelain` (uncommitted), `git log --oneline
  @{upstream}..HEAD 2>/dev/null` (unpushed), `git stash list`
- `git log --author="Brenna" --oneline --since=<yesterday-start>` — what I did
- branches by `-committerdate`, flag branches >1 week stale with no open PR
  → *where I left off* feeds Standup + Punch list; stale branches → Quick wins
  or Needs a ticket

**GitHub** (`gh` CLI or the `activity-github` subagent):

- my open PRs with CI + review state → Punch list (babysit/merge) or
  Waiting on others (approved-pending, awaiting review)
- PRs requesting my review → Quick wins (small) or Punch list (large)
- PRs I merged yesterday + review comments needing my response → Yesterday /
  Punch list

**Linear** (`list_issues`):

- `assignee: "me"`, state started → Punch list, ordered by priority then
  recency. Skip issues untouched for 2+ weeks (backlog noise).
- completed yesterday → Yesterday
- urgent/high unstarted → Punch list bottom or Quick wins if small

**Slack** (`slack_search_public_and_private`, `slack_read_channel` for
#reviewit):

- my #reviewit posts since yesterday + reactions (see convention) → Standup +
  Waiting on others
- `to:<@U0AEAPS47EX> after:<yesterday>` — threads/DMs awaiting my reply →
  Quick wins
- threads where I committed to work or someone asked me for something with no
  Linear issue attached → **Needs a ticket?**

**Calendar** (`list_events`, today):

- meetings today → Standup context + a line in the terminal digest

**Giles queue** (optional): if `~/Sites/martensonbj/giles/sponge/on_deck.md`
exists, pull only `[⚡ MM/DD]` deadline items due within 3 days → Quick wins.
Skip silently if absent.

### 3 — Carryover

Parse the prior punchlist's `<li data-id=… data-done=… data-ref=…>` items
(sections punch/quick/ticket/watch only). Completion truth, in order of
preference:

1. **Synced file** — if the user ran `/punch sync`, `data-done` is truth.
2. **Browser localStorage** — if Claude-in-Chrome MCP is available, read the
   un-synced clicks directly: load `tabs_context_mcp` + `javascript_tool`
   (+ `navigate`/`tabs_create_mcp`) via ToolSearch, open the prior punchlist's
   `file://` path (reuse an existing tab showing it if one exists), and run
   `localStorage.getItem("<STORAGE_KEY from the prior file>")`. The value is a
   deviations map `{ "<data-id>": bool, notes: "..." }` — overlay it on
   `data-done`, and treat a non-empty `notes` string as queued notes (append
   to the `tomorrow.md` drain). Skip silently on any failure — no browser, no
   tab, dialog in the way — never stall the run on this.
3. **Source re-derivation** — the backstop below.

Either way:

- Items with `data-done="1"` → done; list under Yesterday, don't carry.
- For each item with `data-done="0"`, check sources as a backstop (the user
  may not have synced): PR in `data-ref` merged? Linear issue done? Slack
  thread answered? If confirmed done → list it under Yesterday as completed,
  don't carry it.
- Otherwise **carry it over** into the same section: keep its `data-id` and
  `data-ref`, add a `<span class="badge carried">carried</span>` after the
  label text, and refresh its note with current status.
- Drop carried items that have gone stale past usefulness (e.g. a watch item
  whose ticket was cancelled) — mention the drop in the terminal digest.

Queued notes from `tomorrow.md` become unchecked Punch-list or Quick-wins
items (judge by content), with note `from yesterday's notes`. Then **clear
`tomorrow.md`** (truncate, don't delete).

### 4 — Compose

- **Dedup hard**: a Linear issue + its PR + its branch + its Slack thread are
  ONE item. Prefer the most specific description; link all refs inside it.
- **Punch list order**: prod regressions / SLA queue-jumpers → carried
  in-flight work → Linear In Progress by priority → ready-to-start.
- **Quick wins**: anything ≤ ~20 min — replies, small reviews, branch cleanup,
  giles deadline items.
- **Standup block** (Slack mrkdwn, compose-and-copy only — never post):

  ```
  *Yesterday:* merged surfaces#988 (INT-620); window-aware reconcile fix on #990
  *Today:* babysit #990 CI → publish train; throw-once experiment (INT-608)
  *Watch:* #972 awaiting second review
  ```

  3–5 lines total. Plain refs (`repo#NNN`, `INT-NNN`) — no URLs, Slack
  unfurls are noisy.

### 5 — Emit HTML

1. Copy `template.html` from this skill's directory — **do not regenerate the
   CSS/JS**, only replace the `{{PLACEHOLDER}}` tokens:
   - `{{DATE_HUMAN}}` / `{{DATE_ISO}}` / `{{GENERATED_AT}}` /
     `{{YESTERDAY_LABEL}}` (e.g. "Tue Jun 2")
   - `{{STANDUP_BLOCK}}` — the standup text (HTML-escaped)
   - `{{PUNCH_ITEMS}}`, `{{QUICK_ITEMS}}`, `{{TICKET_ITEMS}}`,
     `{{WATCH_ITEMS}}` — `<li>` items per the markup spec below
   - `{{YESTERDAY_CONTENT}}` — a `<ul class="plain">` debrief of completed
     work and activity
   - `{{NOTES_CONSUMED}}` — if queued notes were drained this morning, a
     short `<p class="section-note">Pulled in: …</p>`; otherwise empty string
2. Item markup spec:

   ```html
   <li data-id="punch-int622-ship" data-done="0"
       data-ref="https://github.com/homebotapp/surfaces/pull/990">
     <input type="checkbox" id="c-punch-int622-ship" />
     <label for="c-punch-int622-ship">
       Ship <a class="ref" href="…">#990</a> — CI running → merge
       <span class="note">branch int-622-…, rebased on #988</span>
     </label>
   </li>
   ```

   - `data-id`: `<section>-<slug>` — **stable across days** so carryover
     matching works
   - `data-ref`: the canonical PR URL or Linear issue URL for tomorrow's
     completion re-derivation; omit only when there's truly no ref
   - `data-done="1"` only for items completed before generation (rare)
   - Every ticket/PR/thread mention is an `<a class="ref">` link
3. Write to `~/.claude/punch/PUNCH-YYYY-MM-DD.html`, then
   `ln -sf PUNCH-YYYY-MM-DD.html ~/.claude/punch/PUNCH.html`, then
   `open ~/.claude/punch/PUNCH-YYYY-MM-DD.html`.

### 6 — Terminal digest

Short — the HTML is the artifact. Format:

```
Punch — Wed Jun 3 · ~/.claude/punch/PUNCH-2026-06-03.html

Top of the list: <single most important item>
Carried over: N items (M auto-completed from sources: #988 merged, INT-620 done)
Meetings: 2 (10:00 team sync, 14:00 design review)
Notes drained: 2 from tomorrow.md

Standup block is in the doc — "Copy standup" pastes into Slack.
If any carried item is actually done, tell me and I'll regenerate.
```

Omit lines that don't apply. If the user corrects carryover state, update the
HTML in place (flip `data-done`, move to Yesterday) and re-`open` it.

## Output Conventions

- No emoji in generated content (badges and reaction names excepted)
- One-line items; details go in the `note` span
- Omit empty sections' placeholder content but keep the section shells —
  an empty "Needs a ticket?" with no `<li>` is fine
- Never post to Slack, never modify Linear, never push git — this skill is
  read-only against all sources; its only writes are under `~/.claude/punch/`
