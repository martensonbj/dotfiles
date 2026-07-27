# Porting Brief: the `/punch` skill

You (Claude) are receiving a working skill from another engineer's setup.
Your assignment: **port it to this user's ecosystem** — different company,
different tools, different identity. Translate, don't transplant. Everything
environment-specific in the reference implementation is wrong for your user
until proven otherwise.

## What you're porting

`/punch` is a morning-ritual skill. One command produces:

1. An **interactive HTML punchlist** (self-contained file, inline CSS/JS,
   checkboxes with localStorage state, progress bar) — opened in the browser,
   bookmarkable. Design rationale:
   https://claude.com/blog/using-claude-code-the-unreasonable-effectiveness-of-html
2. A **paste-ready standup block** inside it (compose-and-copy ONLY — the
   skill never posts anywhere on its own)
3. **Day-over-day carryover** — unfinished items reappear tomorrow, badged
   `carried`; items whose PR merged / ticket closed get auto-completed

The daily loop:

```
morning            during the day              end of day
───────            ──────────────              ──────────
/punch        →    check boxes in doc     →    "Copy as Markdown"
                   jot in Notes textarea       + /punch sync
                   (/punch note <x> from
                    any session works too)
```

Subcommands: `(none)` morning run · `note <text>` queue an item for tomorrow
· `sync` end-of-day state save (reads clipboard) · `linear` a tracker-only
deep-triage variant · `help`.

## The bundle

- `SKILL.md` — the reference implementation. Read it fully before changing
  anything. Its **Constants** section is 100% environment-specific; its
  command flows and mechanics are ~90% portable.
- `template.html` — the HTML shell. **Ecosystem-agnostic; keep byte-for-byte**
  except the color palette if your user wants their own. The mechanics it
  encodes (deviation-only localStorage, `data-id`/`data-done`/`data-ref` item
  contract, `<!-- id:… -->` comments in the markdown export that `sync` parses)
  are load-bearing — do not redesign them.
- `PORT.md` — this file. Delete it after the port.

## The item contract (do not break this)

Every checklist item is:

```html
<li data-id="punch-slug" data-done="0" data-ref="<canonical PR/ticket URL>">
```

- `data-id` stable across days → carryover matching
- `data-ref` → next morning's "did this actually get done?" source check
- `data-done` flipped by `/punch sync` → the file becomes the state of record

Carryover precedence: synced file → browser localStorage (only if a
browser-automation MCP is available — optional, skip silently) → re-derive
from sources (PR merged? ticket closed?).

## Translation map

For each row, find the equivalent in THIS environment. If a source doesn't
exist here, drop it — the skill must degrade gracefully, never error or
nag about unconnected sources.

```
role in the skill                reference impl          find here
─────────────────                ──────────────          ─────────
issue tracker (in-progress,      Linear MCP              Jira? GitHub Issues?
  priorities, SLA, triage)                                 Asana? Shortcut?
code host (my PRs, CI state,     gh CLI                  gh? glab? Bitbucket?
  review requests)
chat (posted-for-review msgs,    Slack MCP               Slack? Teams? Discord?
  threads awaiting reply,         (#reviewit channel,
  reaction conventions)            ✅=approved 👀=in review)
calendar (today's meetings)      Google Calendar MCP     Google? Outlook? none?
local repos (branches,           ~/Sites/homebotapp/*    where do this user's
  uncommitted, stashes,                                    clones live?
  unpushed = "where I left off")
clipboard (sync command)         pbpaste (macOS)         pbpaste? xclip? wl-paste?
state dir                        ~/.claude/punch/        same, or user preference
```

## Discovery protocol — do this before writing anything

1. **Inventory tools**: what MCP servers and CLIs actually exist in this
   session? (ToolSearch for tracker/chat/calendar tools; `which gh glab` etc.)
2. **Verify identity empirically — never trust config files.** The reference
   setup lost a run because a stale CLAUDE.md claimed the wrong GitHub handle.
   Use `gh api user --jq .login` (or equivalent), the chat MCP's own
   logged-in-user info, `git config user.name`. Confirm each with the user.
3. **Find the hardcodables**: review channel/room ID, tracker team/project,
   repos root, timezone. Look them up live; paste real IDs into Constants.
4. **Interview the user** (don't guess):
   - What does your ideal morning output contain? (recap / schedule+attention /
     punchlist / standup draft — some or all)
   - Where does your standup go, and what format? (the block is
     compose-and-copy; match its markup to that destination)
   - What does "yesterday" mean for you? (the reference uses Tue–Fri =
     previous day, Monday = Fri–Sun)
   - Which repos/projects are "yours" for the local-git scan?
   - Keep the name `/punch` or rename?

## Lessons already paid for (inherit them)

- **Verify, don't assume identity** (see above — this one cost a wasted run).
- **MCP tool names vary by setup.** A previous version of this skill died
  silently because it referenced a renamed MCP server in `allowed-tools`.
  Write the names you discovered, and batch-load via ToolSearch at run start.
- **localStorage is browser-jail.** No file:// page can write to disk; the
  Copy-as-Markdown + `sync` clipboard bridge is the deliberate workaround.
  Resist the urge to add a localhost listener — a daemon that must be running
  when the user clicks is a worse failure mode than a two-step ritual.
- **Never auto-post.** Standup is composed, never sent. The skill is
  read-only against every source; its only writes are the state dir.
- **Dedup hard.** A ticket + its PR + its branch + its chat thread = ONE item.
- **First run has no carryover** — that's expected; day 2 is the real test.

## Acceptance test

1. `/punch` runs end-to-end with at least code-host + local-git sources
2. HTML opens, checkboxes persist across reload, progress bar moves
3. "Copy standup" produces something the user would actually paste
4. `/punch note test` then a regenerate shows the note in the list
5. Next morning: a checked item stays done, an unchecked one carries with
   the `carried` badge, a merged-PR item auto-completes

Work incrementally, show the user the Constants you derived before the first
run, and treat their corrections as the spec.
