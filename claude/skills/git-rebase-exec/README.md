# git-rebase-exec

Execute a rebase onto main and guide through merge conflicts one at a time. Typical use: checkout a PR branch with GitHub merge conflicts, run this skill, resolve interactively.

## How to Use

```
/git-rebase-exec
```

No arguments. Operates on the current branch, always rebases onto `origin/main` (fetched fresh).

## How It Works

1. **Assess** — Fetches `origin/main`, shows how many commits are on your branch vs new on main.
2. **Rebase** — Runs `git rebase origin/main`. If clean, shows history and reminds about `pnpm build` + force-push.
3. **Resolve conflicts** — When conflicts hit:
   - Shows a triage summary (file count, commit being replayed)
   - Auto-resolves `pnpm-lock.yaml` by regenerating
   - Walks through each file: explains both sides, recommends a resolution, waits for your confirmation, then applies the fix and stages
   - Continues the rebase and repeats if more conflicts appear
4. **Post-rebase** — Shows rebased history, summarizes decisions, reminds about `pnpm build` and force-push.

The skill handles staging (`git add`) and continuing (`git rebase --continue`) itself, but never force-pushes — that's always manual.

## Examples

Clean rebase:

```
/git-rebase-exec

Branch: int-254-build-aientrymodule
Commits on branch: 4
New on main: 12

Rebase completed cleanly.
Run `pnpm build` to rebuild shared packages before typechecking.
Force-push with `git push --force-with-lease` when ready.
```

Rebase with conflicts:

```
/git-rebase-exec

Conflicts in 3 files:
  packages/ui/src/ai/suggestion/index.tsx
  packages/sdks/src/ai/catalogs/domain.ts
  pnpm-lock.yaml

Auto-resolved pnpm-lock.yaml by regenerating.

packages/ui/src/ai/suggestion/index.tsx:
  HEAD added a `size` prop; your branch added an `icon` prop.
  Recommendation: Keep both — they're independent additions.
  Confirm? [y]
```

## Caveats

- Never run this while another rebase is stuck without checking `git status` first — the skill detects in-progress rebases and picks up where you left off.
- After rebasing, always run `pnpm build` before typechecking. Stale `.d.ts` files from shared packages cause phantom type errors.

## See Also

- [SKILL.md](./SKILL.md) — AI agent instructions
- `/git-branch-prune` — Clean up stale branches
- `/git-safe-rebase` — Pre-rebase safety analysis (coming soon)
