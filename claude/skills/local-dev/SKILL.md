---
name: local-dev
description: Manage the Homebot local dev stack on Colima. Starts all services, checks status, or stops everything. Use when starting work, checking what's running, or shutting down.
argument-hint: [status|down]
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Local Dev Environment Manager

Start, check, or stop the full Homebot local dev stack.

```
/local-dev          # Start everything (skips what's already running)
/local-dev status   # Show what's running
/local-dev down     # Stop everything
```

`$ARGUMENTS` provides optional subcommand. Default (no argument) is start.

## Service Startup Order

Services must start in this order due to dependencies:

```
1. colima              VM runtime
2. hbdev               Traefik, PG11, Redis, ES7, Kibana, MailHog
3. surfaces-db         PG18 for surfaces (port 5437)
4. lockbox             Auth service (SSO)
5. mikasa              API backend
6. customer-admin      Frontend
```

Surfaces app itself runs locally via `pnpm dev` — not managed here.

## State Detection

Check each service by looking for a key container or process:

```bash
colima list 2>/dev/null | grep -q Running                                # colima
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "hbdev_traefik"   # hbdev
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-mastra-postgres" # surfaces-db
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^lockbox$"       # lockbox
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^mikasa$"        # mikasa
docker ps --format '{{.Names}}' 2>/dev/null | grep -q "customer-admin"  # customer-admin
```

## Status (`/local-dev status`)

Run all state checks and present:

```
Local Dev Status
────────────────
Colima:         running (10 CPU / 12 GiB)
hbdev:          up
surfaces-db:    up
lockbox:        up
mikasa:         up
customer-admin: up
```

## Start (`/local-dev` with no arguments)

For each service in order, skip if already running, start if not.

**colima:**

```bash
colima start
```

**hbdev:**

```bash
docker compose -f ~/Sites/homebotapp/hbdev/docker-compose.yml -p hbdev up -d
```

**surfaces-db:**

```bash
cd ~/Sites/homebotapp/surfaces && docker compose up -d
```

**IMPORTANT:** The surfaces `docker-compose.yml` starts both a Postgres container
(`ai-mastra-postgres`) AND an `ai-mastra` app container. The app container binds
to port 4111 and conflicts with the local `pnpm dev` Mastra server. After
starting surfaces-db, immediately stop the app container:

```bash
docker stop ai-mastra && docker rm ai-mastra
```

Only the `ai-mastra-postgres` container is needed for local development. The
Mastra gateway runs locally via `pnpm dev`.

**lockbox:**

```bash
cd ~/Sites/homebotapp/lockbox && docker compose up -d
```

Wait for Puma — poll `docker logs --tail 3 lockbox` until "Listening on" appears. Timeout after 120s.

**mikasa:**

```bash
cd ~/Sites/homebotapp/mikasa && docker compose up -d
```

Wait for Puma — poll `docker logs --tail 3 mikasa` until "Listening on" appears. Timeout after 120s.

**customer-admin:**

```bash
cd ~/Sites/homebotapp/customer-admin && docker compose up -d
```

Wait for Next.js — poll `docker logs --tail 3 customer-admin-customer-admin-1` until "Ready" appears. Timeout after 120s.

### After starting, verify with health checks:

```bash
curl -sk -o /dev/null -w "%{http_code}" https://traefik.homebot.test          # expect 301
curl -sk -o /dev/null -w "%{http_code}" https://es.homebot.test               # expect 200
curl -sk -o /dev/null -w "%{http_code}" https://sso.homebot.test              # expect 404
curl -sk -o /dev/null -w "%{http_code}" https://mikasa.homebot.test           # expect 204
curl -sk -o /dev/null -w "%{http_code}" https://customer-admin.homebot.test/en # expect 307
```

Report final status. Remind that surfaces app runs locally: `cd ~/Sites/homebotapp/surfaces && pnpm dev`

### After health checks pass, seed ai-mastra test data:

Ask the user for their `CUSTOMER_PROFILE_ID`. If they don't know it, find it:

```bash
docker exec hbdev_postgres psql -U postgres -d mikasa_development -t -c "
SELECT DISTINCT c.customer_profile_id
FROM clients c WHERE c.first_name ILIKE 'Test%' LIMIT 5;
"
```

Then run the mastra seed script:

```bash
CUSTOMER_PROFILE_ID='<uuid>' ~/Sites/homebotapp/surfaces/apps/ai-mastra/src/scripts/seed-mastra-test-data.sh
```

This backfills `legacy_home_data`, `legacy_home_avms`, `legacy_home_loans`, and
`clients.mobile` for all clients under the profile. Idempotent — safe to re-run.
The script prints a verification table on completion.

## Stop (`/local-dev down`)

Stop in reverse order, skip anything already stopped:

```bash
cd ~/Sites/homebotapp/customer-admin && docker compose down
cd ~/Sites/homebotapp/mikasa && docker compose down
cd ~/Sites/homebotapp/lockbox && docker compose down
cd ~/Sites/homebotapp/surfaces && docker compose down
docker compose -f ~/Sites/homebotapp/hbdev/docker-compose.yml -p hbdev down
colima stop
```

Report what was stopped.

## Error Recovery

| Problem                             | Fix                                                             |
| ----------------------------------- | --------------------------------------------------------------- |
| "container name already in use"     | `docker rm <name>` then retry                                   |
| Network label conflict on `homebot` | Stop surfaces → `docker network rm homebot` → start hbdev first |
| Lockbox bundler crash               | Check `Gemfile.lock` BUNDLED WITH matches Docker image bundler  |
| Container exits immediately         | `docker logs --tail 20 <name>` to diagnose                      |

## Paths

```
~/Sites/homebotapp/hbdev/docker-compose.yml
~/Sites/homebotapp/surfaces/docker-compose.yml
~/Sites/homebotapp/lockbox/docker-compose.yml
~/Sites/homebotapp/mikasa/docker-compose.yml
~/Sites/homebotapp/customer-admin/docker-compose.yml
```
