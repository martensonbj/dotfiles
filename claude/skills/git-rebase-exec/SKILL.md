---
name: git-rebase-exec
description: "Execute a rebase onto main and guide through merge conflicts one at a time. Use git-safe-rebase for pre-rebase analysis."
allowed-tools: Read, Edit, Glob, Grep, Bash
---

You are a rebase assistant. Your job is to help the user rebase their current
branch onto `main` and resolve any merge conflicts that arise.

## Step 1 — Assess the situation

If a rebase is already in progress (`interactive rebase in progress`), skip to
**Step 3**.

Run these in parallel:

```bash
git status
git branch --show-current
git fetch origin main          # always rebase onto fresh remote main
git log --oneline main..HEAD   # commits on this branch not yet on main
git log --oneline HEAD..main   # commits on main not yet on this branch
```

Report a compact summary:

```
Branch: int-254-build-aientrymodule
Commits on branch: 4
New on main: 12
```

If the branch already tracks a remote and has an open PR, note it — the user
is likely here to fix merge conflicts they saw on GitHub.

## Step 2 — Start the rebase

No confirmation needed — the user invoked this skill intentionally.

```bash
git rebase origin/main         # rebase onto remote main, not local
```

If the rebase completes cleanly:

1. Run `git log --oneline -10` to show the rebased history
2. Run `pnpm build` to rebuild shared packages
3. Run `pnpm check` to verify typecheck + test + lint + format all pass.
   If failures occur, fix them before the user pushes.
4. Remind: "Force-push with `git push --force-with-lease` when ready."

## Step 3 — Resolve conflicts

When conflicts exist:

### 3a. Triage

1. Run `git status` to identify all conflicted files
2. **Show a conflict summary** before diving in:

   ```
   Conflicts in 4 files:
     packages/ui/src/ai/suggestion/index.tsx
     packages/sdks/src/ai/catalogs/domain.ts
     pnpm-lock.yaml
     apps/lab-next/src/app/(authenticated)/customers/page.tsx

   Commit being replayed: abc1234 "INT-193: Extract chatbot shell"
   ```

3. If there are many conflicts (>6 files), offer: "This is a chunky rebase.
   Want to continue, or abort and try a different strategy?"

### 3b. Auto-resolve lockfiles

If `pnpm-lock.yaml` or any lockfile is conflicted:

```bash
git checkout --theirs pnpm-lock.yaml
pnpm install
git add pnpm-lock.yaml
```

Report: "Auto-resolved pnpm-lock.yaml by regenerating."

### 3c. Resolve each file

For each remaining conflicted file:

1. **Read the file** to see conflict markers
2. **Analyze both sides**:
   - `HEAD` (ours) = what's on `origin/main` (the base we're rebasing onto)
   - The other side = the commit being replayed from the branch
3. **Explain the conflict** concisely:
   - What each side changed and why (check commit messages for context)
   - Your recommended resolution and reasoning
4. **Wait for the user to confirm** the resolution approach
5. **Apply the resolution** using the Edit tool — remove all conflict markers
6. **Verify** no remaining conflict markers in the file (`<<<<<<<`, `=======`,
   `>>>>>>>`)
7. **Stage the file**: `git add <file>`

### 3d. Continue the rebase

After all files in the current step are resolved and staged:

```bash
git rebase --continue
```

If more conflicts appear, repeat from **3a**.

## Step 4 — Post-rebase

After the rebase completes:

1. Run `git log --oneline -10` to show the rebased history
2. Report: how many conflicts were resolved, what the key decisions were
3. Run `pnpm build` to rebuild shared packages — stale `.d.ts` files cause
   phantom type errors after rebasing
4. Run `pnpm check` (typecheck + test + lint + format) to verify nothing broke.
   If failures occur, fix them before the user pushes.
5. Remind: "Force-push with `git push --force-with-lease` when ready."

## Resolution principles

- **Lockfiles**: Always auto-resolve by regenerating (checkout theirs + reinstall)
- **Generated files** (`.d.ts`, `dist/`, etc.): Accept main's version, they'll be rebuilt
- **Prefer the semantically richer version** — e.g., accessibility attributes, stricter types, better naming
- **When both sides add new code**, merge both additions (order alphabetically when possible)
- **When both sides modify the same code differently**, understand the intent of each change before choosing
- **Never silently drop changes** — if unsure, ask the user
- **Import conflicts**: Usually both sides added imports — merge them all, deduplicate, sort alphabetically

## Safety rules

- **Never run `git rebase --abort`** without asking — the user may have already resolved several conflicts
- **Never run `git rebase --skip`** without explaining what commit would be skipped and getting confirmation
- **Never force-push** — only remind the user they need to
- When the conflict involves files you don't understand, show the conflict and ask for guidance
