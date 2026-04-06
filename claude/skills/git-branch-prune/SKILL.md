---
name: git-branch-prune
description: Prune stale local (and optionally remote) branches. Shows age, PR status, Linear issue status, and worktree conflicts before deleting anything.
disable-model-invocation: true
allowed-tools: Bash
---

Prune local git branches that are no longer needed. Supports `--yes` (skip
confirmation) and `--remote` (also delete stale remote branches) flags passed
as skill arguments.

## Gather

1. **Fetch and prune** remote tracking refs: `git fetch --prune origin`
2. **List local branches** with tracking info: `git branch -vv`
3. **Identify merged branches**: `git branch --merged origin/main` (excluding `main`/`master` and current branch)
4. **Check worktrees**: `git worktree list` — record which branches are checked out in other worktrees

## Classify

For every local branch (except `main`/`master` and current), collect:

| Field               | How                                                                          |
| ------------------- | ---------------------------------------------------------------------------- |
| **Age**             | `git log -1 --format='%cr' <branch>` (e.g., "3 days ago", "6 weeks ago")     |
| **PR status**       | `gh pr list --head <branch> --state all --json state,number,title --limit 1` |
| **Remote tracking** | From `git branch -vv` output — `gone`, tracking, or no remote                |
| **Worktree**        | Whether the branch is checked out in another worktree                        |

Classify each branch into one of these categories:

- **MERGED** — PR merged (delete)
- **CLOSED** — PR closed without merge (delete)
- **OPEN** — PR is in review (keep)
- **STALE** — No PR, remote is `gone`, last commit older than 14 days (suggest delete, ask user)
- **ZOMBIE** — Remote exists, no PR, zero commits ahead of main (suggest delete, ask user)
- **LOCAL_ONLY** — No PR, no remote — unpushed work (keep, but nudge if older than 14 days)
- **WORKTREE** — Checked out in another worktree (keep, cannot delete)

## Present

Show the plan as a table with columns:

| Branch | Age | Status | PR  | Action |
| ------ | --- | ------ | --- | ------ |

- Sort by action: deletes first, then ask-user, then keeps
- For **LOCAL_ONLY** branches older than 14 days, add a note: "unpushed work from N days ago — still need it?"
- For **STALE** and **ZOMBIE** branches, default action is "ask" unless `--yes` flag

After the table, show summary stats:

```
Summary: N to delete, N to keep, N to review | Oldest branch: X (N days)
```

## Optional: Linear cross-reference

After presenting the table, ask:

> "Want me to cross-reference branch names against Linear issue status?"

If yes:

- Extract issue identifiers from branch names (e.g., `INT-215` from `INT-215/clipboard-and-stuff`)
- Check each issue's status via Linear MCP tools
- Append a column to the table showing Linear status (Done, Canceled, In Progress, etc.)
- Branches tied to Done/Canceled issues with no open PR get flagged as additional delete candidates
- **Still present for confirmation** — never auto-delete based on Linear status alone

## Confirm and delete

1. **Wait for user confirmation** before deleting anything (skip if `--yes`)
2. **Delete confirmed branches** in a single `git branch -D` command
3. If `--remote` flag: also `git push origin --delete <branch>` for deleted branches that had remotes (excluding `gone` ones already pruned)
4. **Show remaining branches** after cleanup with `git branch -vv`
5. **Show final stats**: "Pruned N local branches (N remote). N branches remaining."

## Rules

- Never delete `main`/`master` or the current branch
- Never delete branches with open PRs
- Never delete branches checked out in another worktree
- Never delete branches that only exist locally with no PR unless user explicitly confirms
- Never auto-delete based on Linear status — always confirm
- Always show the plan and wait for confirmation before deleting (unless `--yes`)
- `--yes` only auto-confirms MERGED and CLOSED branches — still asks for STALE, ZOMBIE, and LOCAL_ONLY
