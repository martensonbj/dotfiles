---
name: yalc
description: Link surfaces packages into customer-admin via yalc for local cross-repo testing. Manages the full lifecycle — link, push, status, unlink. Accepts a package name or PR number. Run with no args for a guided wizard.
argument-hint: [link|push|status|unlink] [package|PR#]
allowed-tools: Bash, Read, AskUserQuestion
---

# Yalc — Local Package Linking

Link `@homebotapp/*` packages from the surfaces monorepo into customer-admin
for local development without publishing to GitHub Packages.

```
/yalc link <pkg>        Build, publish, and add to customer-admin
/yalc link <PR#>        Detect packages from PR, checkout branch, build + link
/yalc push [pkg]        Rebuild and push updates (all linked if omitted)
/yalc status            Show what's currently yalc-linked
/yalc unlink [pkg]      Remove a linked package (or all if omitted)
/yalc                   Guided wizard
```

`$ARGUMENTS` provides the subcommand and optional package name or PR number.

## Package Short Names

Users specify packages by short name. Map to full names:

| Short name    | Full name                | Package dir    |
| ------------- | ------------------------ | -------------- |
| `ui`          | `@homebotapp/ui`         | `packages/ui`  |
| `sdks`        | `@homebotapp/sdks`       | `packages/sdks`|
| `mastra-chat` | `@homebotapp/mastra-chat`| `packages/mastra-chat` |
| `utils`       | `@homebotapp/utils`      | `packages/utils` |

These four are the intersection of surfaces exports and customer-admin
dependencies. Only these can be linked.

## Paths

```
SURFACES=~/Sites/homebotapp/surfaces
CUSTOMER_ADMIN=~/Sites/homebotapp/customer-admin
```

## Local Dev Architecture

Customer-admin and its dependencies run in Docker behind Traefik. The Mastra
AI gateway runs locally on the host. This is important to understand because
yalc links files on the host — the Docker container sees them via a volume
mount, but has its own isolated `node_modules`.

```
Docker (docker compose)
├── traefik         *.homebot.test routing
├── customer-admin  mounted from host, but node_modules is a Docker volume
├── lockbox         auth/SSO
├── mikasa          API backend
├── hbdev           postgres, redis, elasticsearch
│
│   customer-admin calls host.docker.internal:4111
│   for AI features
▼
Host (local terminal)
└── surfaces → pnpm mastra:dev  (ai-mastra on :4111)
```

Key implications for yalc:
- `yalc add` and `yalc remove` modify files on the host
- `.yalc/` is visible inside the container (host dir is mounted at `/app`)
- `node_modules` is a **named Docker volume** — isolated from the host
- Must run `npm install` **inside the container** for it to pick up yalc links
- Mastra must be running locally for AI chat features to work

## Prereqs Check

Before any operation (including the wizard), verify:

1. yalc is installed:

```bash
which yalc >/dev/null 2>&1
```

If missing, tell the user to run `npm i -g yalc` and stop.

2. Detect customer-admin's package manager by checking which lockfile exists:

```bash
ls $CUSTOMER_ADMIN/pnpm-lock.yaml $CUSTOMER_ADMIN/package-lock.json $CUSTOMER_ADMIN/yarn.lock 2>/dev/null
```

- `pnpm-lock.yaml` → use `pnpm install`
- `package-lock.json` → use `npm install`
- `yarn.lock` → use `yarn install`

Store this for the session. All `install` commands in customer-admin must use
the detected package manager. **Never mix package managers** — using the wrong
one corrupts `node_modules` and creates stale lockfiles.

## No Arguments — Guided Wizard

If `$ARGUMENTS` is empty, run the interactive wizard.

### Step 1: Check current state

First, silently gather context:

```bash
cd $SURFACES && git branch --show-current
```

```bash
cat $CUSTOMER_ADMIN/yalc.lock 2>/dev/null
```

### Step 2: Present status and prompt

**If packages are already linked**, show their status first (same as the
`status` command output), then ask:

> Packages are currently linked from surfaces (`<branch>`).
>
> What would you like to do?
> - **push** — rebuild and push updates to customer-admin
> - **unlink** — remove all linked packages and restore published versions
> - **link** — link additional packages (PR number or package name)

Use AskUserQuestion and wait for a response. Then execute the chosen command.

**If nothing is linked**, start the link wizard:

> To get started, what would you like to test against customer-admin?
>
> You can provide:
> - A **PR number** (e.g. `512`) — I'll detect the changed packages and check out the branch
> - A **package name** (e.g. `ui`) — I'll build and link just that one from your current branch
>
> Linkable packages: `ui`, `sdks`, `mastra-chat`, `utils`

Use AskUserQuestion and wait for a response.

### Step 3: Branch confirmation (PR flow only)

After fetching PR metadata and before checking out, confirm:

> PR #512: "Add loading state to AiEntryModule"
> Branch: `int-286/add-loading-state-to-ai-entry-module`
> Packages to link: `ui`
>
> I'll check out that branch in surfaces, build, and link into customer-admin.
> Surfaces is currently on `<current-branch>`. Ready to proceed?

Use AskUserQuestion. If the user confirms, proceed with checkout + build + link.
If they decline, stop.

### Step 4: After linking

Report what was done and give next steps:

> Linked `@homebotapp/ui` from branch `int-286/add-loading-state-to-ai-entry-module`
> into customer-admin.
>
> To see your changes:
> 1. Make sure customer-admin is running (however you normally start it)
> 2. You may need to **restart** it to pick up the linked package
> 3. If testing AI chat features, start Mastra locally:
>    `cd ~/Sites/homebotapp/surfaces && pnpm mastra:dev`
> 4. Test at https://customer-admin.homebot.test
>
> After that:
> - `/yalc push` — rebuild + push after making more changes in surfaces
> - `/yalc unlink` — restore published versions when done

## link

Arguments: `link <short-name>` OR `link <PR-number>`

### Determine what to link

Parse the argument after `link`:

- If it matches a known short name (`ui`, `sdks`, `mastra-chat`, `utils`),
  link that single package. Do NOT change branches.
- If it's a number (with or without `#` prefix), treat it as a PR number and
  run the PR detection flow below.
- Anything else → reject with a helpful message listing valid packages.

### PR detection flow

When the argument is a PR number:

1. Fetch PR metadata from the surfaces repo:

```bash
cd $SURFACES && gh pr view <number> --json headRefName,title,files --jq '{branch: .headRefName, title: .title, files: [.files[].path]}'
```

2. Extract changed packages by matching file paths against `packages/<name>/`.
   Filter to only the four linkable packages. If no linkable packages were
   changed, report that and stop.

3. Show what will happen and confirm (same as wizard Step 3):

> PR #<number>: "<title>"
> Branch: `<branch>`
> Packages to link: `<list>`
>
> I'll check out that branch in surfaces, build, and link into customer-admin.
> Surfaces is currently on `<current-branch>`. Ready to proceed?

Use AskUserQuestion. If the user confirms, proceed. If not, stop.

4. Check out the PR branch:

```bash
cd $SURFACES && git checkout <branch-name>
```

5. Continue to the build + publish + add steps below for each package.

### Build, pack, publish, and add (for each package)

**IMPORTANT — gotchas:**

1. Surfaces uses pnpm's `catalog:` protocol for dependencies. A raw
   `yalc publish` from the package directory copies the unresolved `catalog:`
   references, which breaks install in customer-admin. The fix is to use
   `pnpm pack` first (which resolves catalogs to real versions), then
   `yalc publish` from the unpacked tarball.

2. **Customer-admin may run in Docker.** Its `docker-compose.yml` mounts the
   project directory (`.:/app`) but uses a **named Docker volume** for
   `node_modules`. This means `.yalc/` is visible inside the container but
   `node_modules` is isolated — installing on the host doesn't update the
   container's packages. See the "Install dependencies" step below for how
   to handle this.

1. Build the package (and its workspace dependencies) via turborepo:

```bash
cd $SURFACES && pnpm build --filter @homebotapp/<short-name>...
```

The `...` suffix tells turbo to also build upstream dependencies (e.g., `ui`
depends on `utils`).

2. Pack with pnpm to resolve `catalog:` and `workspace:` protocols:

```bash
cd $SURFACES/packages/<short-name> && rm -rf /tmp/yalc-stage && mkdir -p /tmp/yalc-stage && pnpm pack --pack-destination /tmp/yalc-stage
```

3. Unpack and publish to yalc from the resolved tarball:

```bash
cd /tmp/yalc-stage && tar -xzf *.tgz && cd package && yalc publish
```

4. Add to customer-admin:

```bash
cd $CUSTOMER_ADMIN && yalc add @homebotapp/<short-name>
```

5. After ALL packages are published and added, install dependencies. Detect
   whether customer-admin is running in Docker:

```bash
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "customer-admin"
```

**If customer-admin is running in Docker:**

Install inside the container and restart:

```bash
docker exec customer-admin-customer-admin-1 <detected-pkg-manager> install
docker compose -f $CUSTOMER_ADMIN/docker-compose.yml restart
```

**If NOT running in Docker (or no Docker at all):**

Install on the host:

```bash
cd $CUSTOMER_ADMIN && <detected-pkg-manager> install
```

6. Report success with next steps (same as wizard Step 4).

## push

Arguments: `push [short-name]`

If a package name is given, rebuild and push just that one.
If no package name, detect all currently linked packages and push all of them.

**Detect linked packages:**

```bash
cat $CUSTOMER_ADMIN/yalc.lock 2>/dev/null
```

The lock file is JSON with a `packages` object keyed by full package name.
Map full names back to short names for the build step.

If no packages are linked, tell the user and suggest `/yalc link`.

**For each package to push:**

1. Build:

```bash
cd $SURFACES && pnpm build --filter @homebotapp/<short-name>...
```

2. Pack with pnpm to resolve `catalog:` protocols:

```bash
cd $SURFACES/packages/<short-name> && rm -rf /tmp/yalc-stage && mkdir -p /tmp/yalc-stage && pnpm pack --pack-destination /tmp/yalc-stage
```

3. Unpack and push to yalc (auto-updates all consumers):

```bash
cd /tmp/yalc-stage && tar -xzf *.tgz && cd package && yalc push
```

Report which packages were pushed.

## status

No arguments.

1. Check if `$CUSTOMER_ADMIN/yalc.lock` exists. If not, report "No packages
   linked." and suggest `/yalc link` or just `/yalc` to start the wizard.

2. Parse the lock file and display:

```
Yalc Status
────────────
@homebotapp/ui         linked (0.1.8+abc1234)
@homebotapp/sdks       linked (0.1.8+def5678)

surfaces branch: int-286/add-loading-state-to-ai-entry-module
```

3. Show the current `package.json` version strings for linked packages so the
   user can see the rewrite:

```bash
cd $CUSTOMER_ADMIN && python3 -c "
import json
d = json.load(open('package.json'))
deps = {**d.get('dependencies',{}), **d.get('devDependencies',{})}
for name in ['@homebotapp/ui','@homebotapp/sdks','@homebotapp/mastra-chat','@homebotapp/utils']:
    v = deps.get(name)
    if v and ('yalc' in str(v).lower() or 'file:' in str(v)):
        print(f'  {name}: {v}')
"
```

4. Show which branch surfaces is currently on:

```bash
cd $SURFACES && git branch --show-current
```

## unlink

Arguments: `unlink <short-name>` or `unlink` (no args = all)

**Single package:**

```bash
cd $CUSTOMER_ADMIN && yalc remove @homebotapp/<short-name>
```

**All packages (default when no argument given):**

Parse `yalc.lock` for all linked packages, then:

```bash
cd $CUSTOMER_ADMIN && yalc remove --all
```

After removing, restore correct versions:

```bash
cd $CUSTOMER_ADMIN && <detected-pkg-manager> install
```

Report what was unlinked. Remind the user that `package.json` is now restored
to the published versions.

## Safety

- **Never commit yalc artifacts.** If `git status` in customer-admin shows
  changes to `package.json` that contain `file:.yalc`, warn the user loudly.
- `.yalc/` and `yalc.lock` should be in customer-admin's `.gitignore`.
  Check on `link` and warn if missing.
- The `link` and `unlink` commands modify `package.json` — always run
  `npm install` after to keep the lockfile consistent.
- **Use the correct package manager.** Detect it from the lockfile (see
  Prereqs Check). Using the wrong one corrupts `node_modules` and creates
  stale lockfiles. Surfaces always uses `pnpm`; customer-admin may differ.
