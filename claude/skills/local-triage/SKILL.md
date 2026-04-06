---
name: local-triage
description: Diagnose the local Homebot dev stack. Checks containers, TLS, Doppler env vars, health endpoints, and ports — then reports findings and offers to fix.
argument-hint: ""
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Local Dev Triage

Diagnose the Homebot local dev stack and report what's broken.

```
/local-triage    # Run full diagnostic, report findings, offer to fix
```

## Diagnostic Steps

Run all checks in parallel where possible, then compile a single report.

### 1. Container Status

Check each service container:

```bash
colima list 2>/dev/null | grep -q Running && echo "colima: up" || echo "colima: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "hbdev_traefik" && echo "traefik: up" || echo "traefik: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "hbdev_postgres" && echo "hbdev-pg: up" || echo "hbdev-pg: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "hbdev_redis" && echo "redis: up" || echo "redis: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "hbdev_elasticsearch" && echo "elasticsearch: up" || echo "elasticsearch: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-mastra-postgres" && echo "surfaces-db: up" || echo "surfaces-db: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^lockbox$" && echo "lockbox: up" || echo "lockbox: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^mikasa$" && echo "mikasa: up" || echo "mikasa: DOWN"
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "customer-admin" && echo "customer-admin: up" || echo "customer-admin: DOWN"
```

### 2. TLS Certificate

The dev server needs `/tmp/homebot-ca.pem` for `NODE_EXTRA_CA_CERTS`. This file
is cleared on reboot.

```bash
# Check file exists and has content
test -s /tmp/homebot-ca.pem && echo "tls-cert: ok" || echo "tls-cert: MISSING or EMPTY"
```

**Fix:** Export from macOS keychain:

```bash
security find-certificate -a -c homebot.test -p /Library/Keychains/System.keychain > /tmp/homebot-ca.pem
```

If that produces an empty file, the CA cert is not in the system keychain. Fix:

```bash
sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" "$HOME/Sites/homebotapp/hbdev/.infra/tls/ca.pem"
```

Then re-run the export. If the cert source file doesn't exist either, report
that hbdev may not be cloned or the TLS infra is missing.

### 3. Doppler Environment Variables

Check that key env vars resolve in Doppler:

```bash
doppler secrets get LABS_APP_URL LOCKBOX_URL LABS_LOCKBOX_CLIENT_ID MASTRA_PUBLIC_URL --plain 2>&1
```

Expected: all four return non-empty values. If any are missing, report which
ones and suggest checking the Doppler dashboard.

### 4. Health Check Endpoints

Only run these for services whose containers are up:

```bash
curl -sk -o /dev/null -w "%{http_code}" https://traefik.homebot.test          # expect 301
curl -sk -o /dev/null -w "%{http_code}" https://es.homebot.test               # expect 200
curl -sk -o /dev/null -w "%{http_code}" https://sso.homebot.test              # expect 404
curl -sk -o /dev/null -w "%{http_code}" https://mikasa.homebot.test           # expect 204
curl -sk -o /dev/null -w "%{http_code}" https://customer-admin.homebot.test/en # expect 307
curl -sk -o /dev/null -w "%{http_code}" https://surfaces-lab-next.homebot.test # expect 200 (if pnpm dev running)
```

A **502** from Traefik means the upstream service container is down or the local
process (e.g. `pnpm dev`) is not running.

A **000** (connection refused) means Traefik itself is not running.

### 5. Branch Freshness

Check if the current branch is missing recent main commits that could cause
breakage (e.g. env var renames, middleware changes):

```bash
git merge-base HEAD main
```

Then check if main has commits after the merge-base:

```bash
git log --oneline "$(git merge-base HEAD main)..main"
```

If there are commits on main not in the branch, report them and flag any that
touch `middleware.ts`, `constants.ts`, `package.json`, or env var configuration
as high-risk. These are the most common source of "everything looks up but the
app errors."

Also verify the middleware isn't crashing by curling localhost directly:

```bash
curl -s http://localhost:3000/stories 2>&1 | head -5
```

If the response contains `TypeError` or `500`, read the error — it usually
points to a missing env var or a code change the branch hasn't picked up yet.
The fix is to rebase onto main.

### 6. Mastra Storage Tables

If surfaces-db (`ai-mastra-postgres`) is running, check that Mastra's internal
tables exist. These are created by a one-time init script, not by node-pg-migrate
migrations. A fresh database or a recreated container will be missing them.

```bash
docker exec ai-mastra-postgres psql -U ai_mastra -d ai_mastra -c "\dt public.mastra_*" 2>&1
```

Expected: a list of tables including `mastra_threads`, `mastra_messages`, etc.
If "Did not find any tables", report it.

**Fix:**

```bash
doppler run -- pnpm --filter @homebotapp/ai-mastra exec tsx src/scripts/init-mastra-storage.ts
```

This is safe to re-run (idempotent). Without these tables, the app will 500 on
any session/chat endpoint with `relation "public.mastra_threads" does not exist`.

### 7. Port Checks

Check if key local processes are listening:

```bash
lsof -i :3000 -sTCP:LISTEN 2>/dev/null | grep -q LISTEN && echo "port-3000: listening (lab-next)" || echo "port-3000: NOT listening"
lsof -i :4111 -sTCP:LISTEN 2>/dev/null | grep -q LISTEN && echo "port-4111: listening (ai-mastra)" || echo "port-4111: NOT listening"
```

Port 3000 = Next.js dev server (`pnpm dev` in surfaces).
Port 4111 = Mastra gateway (`pnpm dev` in surfaces, or the Docker container which should be stopped).

#### Stale port detection

When a port IS listening, check whether the holder is a stale/orphaned process.
This happens when a previous `pnpm dev` session dies without releasing the port
(e.g. terminal closed, clone switched). The new `pnpm dev` will crash with
`EADDRINUSE`.

For each listening port, capture the PID and its parent:

```bash
for port in 3000 4111; do
  pid=$(lsof -ti :$port -sTCP:LISTEN 2>/dev/null)
  if [ -n "$pid" ]; then
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    cmd=$(ps -o command= -p "$pid" 2>/dev/null | head -c 80)
    # A stale process typically has ppid=1 (orphaned) or its parent is
    # launchd/init rather than a terminal or turbo process
    if [ "$ppid" = "1" ]; then
      echo "port-$port: STALE (pid $pid, orphaned) — $cmd"
    else
      echo "port-$port: listening (pid $pid, ppid $ppid) — $cmd"
    fi
  fi
done
```

If any port is flagged STALE, report it with a fix.

**Fix:**

```bash
kill <pid>    # Kill the orphaned process, then restart pnpm dev
```

The symptom is: `pnpm dev` crashes immediately with
`Error: listen EADDRINUSE: address already in use :::4111` (or :::3000).
The process holding the port is a leftover from a previous session or clone.

### 8. Package Build Freshness

When switching between multiple local clones (e.g. `surfaces` and
`surfaces-review`), the `restart` alias restarts Docker containers but does NOT
rebuild packages. If `pnpm dev` runs before `pnpm build`, the `dist/` output is
stale and Next.js will silently 404 every route whose layout imports from a
shared package (e.g. `@homebotapp/ui`).

Check that key shared-package exports resolve:

```bash
node -e "require.resolve('@homebotapp/ui/base/sidebar')" 2>&1 && echo "ui-exports: ok" || echo "ui-exports: STALE — run pnpm build"
```

If the check fails, report it.

**Fix:**

```bash
pnpm build
```

Then restart the dev server. The symptom is: all containers up, port 3000
listening, health endpoints return 404 (not 502), and curling localhost directly
also returns 404 with the Next.js default not-found page.

## Report Format

Present findings as a clean status report:

```
Local Dev Triage
════════════════

Containers
──────────
colima:         up
traefik:        up
hbdev-pg:       up
redis:          up
elasticsearch:  up
surfaces-db:    up
lockbox:        up
mikasa:         up
customer-admin: up

TLS
───
/tmp/homebot-ca.pem:  ok (1338 bytes)

Doppler
───────
LABS_APP_URL:           set
LOCKBOX_URL:            set
LABS_LOCKBOX_CLIENT_ID: set
MASTRA_PUBLIC_URL:      set

Health Endpoints
────────────────
traefik.homebot.test:          301 (ok)
es.homebot.test:               200 (ok)
sso.homebot.test:              404 (ok)
mikasa.homebot.test:           204 (ok)
customer-admin.homebot.test:   307 (ok)
surfaces-lab-next.homebot.test: 502 (FAIL — upstream not running)

Mastra Storage
──────────────
mastra_threads:  ok (tables exist)

Package Builds
──────────────
ui-exports:  ok

Local Processes
───────────────
port 3000 (lab-next):    NOT listening
port 4111 (ai-mastra):   NOT listening
```

After the report, list any problems found with a one-line fix for each:

```
Problems Found
──────────────
1. traefik: DOWN — run: docker compose -f ~/Sites/homebotapp/hbdev/docker-compose.yml -p hbdev up -d
2. /tmp/homebot-ca.pem: EMPTY — run: security find-certificate -a -c homebot.test -p /Library/Keychains/System.keychain > /tmp/homebot-ca.pem
3. port 3000: NOT listening — run: cd ~/Sites/homebotapp/surfaces && pnpm dev
```

If there are no problems, report "All clear."

## Offer to Fix

After presenting the report, ask:

> Want me to attempt fixes for the issues above?

If the user says yes, apply fixes in dependency order (same order as `/local-dev` startup):

1. Start missing containers (colima first, then hbdev, then others)
2. Export TLS cert if missing
3. Kill stale/orphaned processes holding ports
4. Initialize Mastra storage tables if missing
5. Report what was fixed and what still needs manual action (e.g. `pnpm dev`)

If a fix requires `sudo` (e.g. adding the CA cert to the keychain), tell the
user the exact command to run — do not attempt `sudo` automatically.

## Common Problem Patterns

| Symptom                                        | Likely Cause                                                                                                                       | Check                    |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| Browser shows nothing / ERR_SSL_PROTOCOL_ERROR | Traefik not running                                                                                                                | Container check          |
| 502 on surfaces-lab-next.homebot.test          | Next.js dev server not running                                                                                                     | Port 3000 check          |
| 502 on other \*.homebot.test                   | Upstream container down                                                                                                            | Container + health check |
| Node SELF_SIGNED_CERT_IN_CHAIN errors          | `/tmp/homebot-ca.pem` missing                                                                                                      | TLS cert check           |
| Auth redirects fail / empty LABS_APP_URL       | Doppler vars not set or stale                                                                                                      | Doppler check            |
| Everything looks up but page is blank          | Check browser console for JS errors                                                                                                | Manual                   |
| 500 / TypeError: Invalid URL from middleware   | Branch missing env var rename from main                                                                                            | Branch freshness check   |
| 404 on all routes (even /stories)              | Stale build after switching clones — `restart` alias swaps the Docker container but `pnpm build` is still needed before `pnpm dev` | Module resolution check  |
| 404 on all routes, middleware not crashing     | Middleware crashing before route handler runs                                                                                      | Curl localhost directly  |
| Rebased but still broken                       | Rebase happened before the fix landed on main                                                                                      | Branch freshness check   |
| 500 on /sessions, "mastra_threads" not found   | Mastra storage tables not initialized                                                                                              | Mastra storage check     |
| EADDRINUSE :::4111 or :::3000 on `pnpm dev`    | Orphaned node process from a previous session or clone holding the port                                                            | Stale port detection     |

## Paths

```
~/Sites/homebotapp/hbdev/docker-compose.yml
~/Sites/homebotapp/hbdev/.infra/tls/ca.pem
~/Sites/homebotapp/surfaces/docker-compose.yml
~/Sites/homebotapp/lockbox/docker-compose.yml
~/Sites/homebotapp/mikasa/docker-compose.yml
~/Sites/homebotapp/customer-admin/docker-compose.yml
```
