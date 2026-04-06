# git-branch-prune

Prune stale local git branches. Shows branch age, PR status, and optionally Linear issue status before deleting anything.

## How to Use

```
/git-branch-prune
/git-branch-prune --yes        # auto-confirm merged/closed, still asks for ambiguous
/git-branch-prune --remote     # also delete stale remote branches
/git-branch-prune --yes --remote
```

## How It Works

The skill fetches remote refs, classifies every local branch by age, PR status, remote tracking state, and worktree conflicts, then presents a table with proposed actions. You confirm before anything is deleted.

Branch categories:

- **MERGED / CLOSED** — PR merged or closed. Auto-deleted with `--yes`.
- **OPEN** — PR in review. Always kept.
- **STALE** — No PR, remote gone, last commit >14 days. Asks before deleting.
- **ZOMBIE** — Remote exists, no PR, zero commits ahead of main. Asks before deleting.
- **LOCAL_ONLY** — Unpushed work. Kept, but nudges if >14 days old.
- **WORKTREE** — Checked out in another worktree. Cannot be deleted.

After the table, optionally cross-references branch names against Linear issue status (Done/Canceled issues flag branches as additional delete candidates).

## Examples

Basic usage — review and confirm:

```
/git-branch-prune

| Branch                    | Age       | Status  | PR   | Action |
|---------------------------|-----------|---------|------|--------|
| int-237/rename-components | 3 days    | MERGED  | #406 | Delete |
| INT-185/toModelOutput     | 5 days    | MERGED  | #401 | Delete |
| bm/fix/ts-error           | 2 weeks   | STALE   | —    | Ask    |
| INT-215/clipboard-stuff   | 14 days   | LOCAL   | —    | Keep   |

Summary: 2 to delete, 1 to review, 1 to keep | Oldest: bm/fix/ts-error (14 days)
```

Quick cleanup with remote branch deletion:

```
/git-branch-prune --yes --remote

Pruned 8 local branches (5 remote). 3 branches remaining.
```

## See Also

- [SKILL.md](./SKILL.md) — AI agent instructions
- `/git-rebase-exec` — Execute rebases and resolve conflicts
- `/git-safe-rebase` — Pre-rebase safety analysis (coming soon)
