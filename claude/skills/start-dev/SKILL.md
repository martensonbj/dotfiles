---
name: start-dev
description: Start, triage, and seed the Homebot local dev stack — one command to a logged-in, fully-seeded customer-admin or lab-next. Replaces local-dev + local-triage.
argument-hint: "[status|down|seed|reset]"
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# Start Dev — full local-dev orchestration

One skill, four flows:

```
/start-dev          # Start everything, triage, fix what's fixable, seed PI user, report login
/start-dev status   # Triage only — no changes
/start-dev down     # Stop everything
/start-dev seed     # Re-run idempotent seed flow (no service changes)
/start-dev reset    # DESTRUCTIVE: db:drop + full re-seed (requires confirmation)
```

`$ARGUMENTS` provides the subcommand. Default is the full flow.

## Stack overview (the "lay of the land")

```
customer-admin.homebot.test       Next.js  (docker: customer-admin-customer-admin-1)
surfaces-lab-next.homebot.test    Next.js  (host: pnpm dev in surfaces)
http://localhost:4111             ai-mastra gateway  (host: pnpm dev in surfaces)

mikasa             Rails API     (docker: mikasa)
lockbox            Auth          (docker: lockbox)
hbdev_postgres     Shared PG     (docker — hosts mikasa_development, mikasa_listings_development)
ai-mastra-postgres Surfaces PG   (docker, port 5437)
hbdev_traefik      TLS proxy     (docker)
```

URL gotcha: routes nest under `[lang]`, so visit `/en/insights`, `/en/clients`, etc.
`admin-v2.homebot.test` is a stale hostname, not a local service.

---

## Default flow (`/start-dev` no args)

Goal: a logged-in user with PI + homeowner data, in the minimum possible time. Skip
anything already healthy.

### Phase 1 — Triage (read-only)

Run all checks in parallel:

```bash
# Containers
colima list 2>/dev/null | grep -q Running                       && echo colima:ok       || echo colima:DOWN
docker ps --format '{{.Names}}' | grep -q '^hbdev_traefik$'     && echo traefik:ok      || echo traefik:DOWN
docker ps --format '{{.Names}}' | grep -q '^hbdev_postgres$'    && echo hbdev_pg:ok     || echo hbdev_pg:DOWN
docker ps --format '{{.Names}}' | grep -q '^hbdev_redis$'       && echo redis:ok        || echo redis:DOWN
docker ps --format '{{.Names}}' | grep -q '^hbdev_elasticsearch$' && echo es:ok         || echo es:DOWN
docker ps --format '{{.Names}}' | grep -q '^ai-mastra-postgres$' && echo surfaces_pg:ok || echo surfaces_pg:DOWN
docker ps --format '{{.Names}}' | grep -q '^lockbox$'           && echo lockbox:ok      || echo lockbox:DOWN
docker ps --format '{{.Names}}' | grep -q '^mikasa$'            && echo mikasa:ok       || echo mikasa:DOWN
docker ps --format '{{.Names}}' | grep -q customer-admin        && echo customer-admin:ok || echo customer-admin:DOWN

# Host processes
lsof -i :3000 -sTCP:LISTEN >/dev/null 2>&1 && echo port-3000:listening || echo port-3000:free
lsof -i :4111 -sTCP:LISTEN >/dev/null 2>&1 && echo port-4111:listening || echo port-4111:free

# TLS cert
test -s /tmp/homebot-ca.pem && echo tls:ok || echo tls:MISSING

# Doppler (surfaces project)
cd ~/Sites/homebotapp/surfaces && doppler secrets get MARKETHUB_DATABASE_URL MASTRA_PUBLIC_URL LABS_APP_URL --plain 2>&1
```

Check markethub local-DB correctness. The old PR #663 SSL "patch" is gone —
`pool.ts` evolved to derive SSL from the DSN's `sslmode` param (`resolveSsl`),
so local correctness is now "the DSN carries `?sslmode=disable`", NOT a code
patch. Grepping `isAurora` is a stale false-positive (verified 2026-05-27);
check the DSN instead. The COALESCE fix is still a code-level check.

```bash
cd ~/Sites/homebotapp/surfaces
doppler secrets get MARKETHUB_DATABASE_URL --plain 2>/dev/null | grep -q 'sslmode=disable' \
  && echo ssl-local:ok || echo ssl-local:MISSING_sslmode_disable
grep -q "resolveSsl" apps/ai-mastra/src/graphql/market-subgraph/pool.ts \
  && echo ssl-code:current || echo ssl-code:OLD_pool.ts_predates_PR663
grep -q "COALESCE" apps/ai-mastra/src/graphql/market-subgraph/entities.ts \
  && echo coalesce-patch:ok || echo coalesce-patch:MISSING
```

`ssl-local:MISSING_sslmode_disable` is the only routinely-actionable one — fix it
via the Doppler set command in Phase 2 (the DSN **must** end with
`?sslmode=disable`, or `pool.ts` defaults to SSL-on and local Postgres rejects
the connection). `ssl-code`/`coalesce-patch` only go stale on a pre-PR-#663 branch.

**Partner-data table check — the source the `agentConnections` resolver _actually_
reads now.** The "give me three partners to call" tool resolves through the
market-subgraph `agentConnections` resolver, which (as of the INT-589 era) reads the
**`agent_lo_relationships` table** — `entities.ts` → `buildLoAgentConnectionsSql`,
`FROM agent_lo_relationships`. It NO LONGER calls the legacy
`markethub_lo_agent_connections(...)` function. That table is a pre-aggregated
ELT/dbt artifact that exists in prod Aurora but has **no migration or seed in any
repo** — `seeds:markethub_setup` builds only the `dim_*` tables + the legacy function,
not this. When the table is absent the resolver throws `INTERNAL_ERROR`, the tool
returns the generic `"Agent connections lookup failed"`, and the agent reports a
*fake "tool outage."* (The error is swallowed at 3 layers — Postgres → subgraph →
tool — so the real cause never reaches the chat. This is the #1 partner-tool
false-alarm; do not chase auth/identity for it.)

```bash
docker exec hbdev_postgres psql -U postgres -d mikasa_listings_development -tAc \
  "SELECT COALESCE(to_regclass('public.agent_lo_relationships')::text,'MISSING') AS tbl,
          COALESCE((SELECT count(*) FROM agent_lo_relationships),0)::text AS rows;" 2>&1
```

- `MISSING|0` → table absent → seed it in Phase 2 ("Seed the partner-data table").
- `agent_lo_relationships|0` → table exists but empty → same fix (re-seed).
- `agent_lo_relationships|<n>` (n>0) → ok. Confirm it covers the login NMLS — the
  resolver filters `WHERE loan_officer_nmls_id = <caller nmls>`, so a populated table
  with no row for _your_ LO still returns empty. Spot-check the PI user (`03000000`):
  `... -tAc "SELECT count(*) FROM agent_lo_relationships WHERE loan_officer_nmls_id='03000000' AND deals_together_12m>0;"`

### Phase 1.5 — Auth health check (read-only)

Goal: answer "can the user even log in right now, and if not, what's mismatched?" Two checks: (a) is mikasa's CustomerProfile linked to the lockbox user the auth flow will hand out, (b) is the runtime hitting any 5xx that suggests schema drift in mastra.

**(a) JWT ↔ CustomerProfile alignment:**

```bash
# Grab the most recent JWT from customer-admin auth callback URLs in its docker logs
JWT=$(docker logs --tail 500 customer-admin-customer-admin-1 2>&1 \
  | grep -oE 'access_token=ey[A-Za-z0-9_.-]+' | tail -1 | sed 's/access_token=//')

if [ -z "$JWT" ]; then
  echo "auth:NO_RECENT_LOGIN — can't assess until user logs in once"
else
  PAYLOAD=$(echo "$JWT" | cut -d. -f2 | tr '_-' '/+')
  while [ $((${#PAYLOAD} % 4)) -ne 0 ]; do PAYLOAD="${PAYLOAD}="; done
  JSON=$(echo "$PAYLOAD" | base64 -d 2>/dev/null)
  JWT_SUB=$(echo "$JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); s=d.get("sub",""); print(s.split("/",1)[1] if "/" in s else s)' 2>/dev/null)
  JWT_EMAIL=$(echo "$JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("email",""))' 2>/dev/null)
  JWT_AUD=$(echo "$JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("audience_type",""))' 2>/dev/null)
  echo "auth:last_jwt sub=$JWT_SUB email=$JWT_EMAIL audience_type=$JWT_AUD"

  # Compare to mikasa
  docker exec mikasa bin/rails runner "
    cp = CustomerProfile.find_by(email: '$JWT_EMAIL')
    if cp.nil?
      puts 'auth_mikasa:NO_PROFILE'
    elsif cp.lockbox_uid.nil?
      puts %Q{auth_mikasa:NIL_UID cp=#{cp.id}}
    elsif cp.lockbox_uid == '$JWT_SUB'
      puts %Q{auth_mikasa:LINKED cp=#{cp.id} uid=#{cp.lockbox_uid}}
    else
      puts %Q{auth_mikasa:MISMATCH cp=#{cp.id} mikasa_uid=#{cp.lockbox_uid} jwt_sub=$JWT_SUB}
    end
  " 2>&1 | grep -E '^auth_mikasa:'
fi
```

Outcomes:

- `LINKED` → all good, proceed
- `MISMATCH` → JWT for this email points at a different lockbox user than mikasa expects. Fix in Phase 2: "Repointing the PI LO between consumers" section, prefilled with `mikasa_uid` and `jwt_sub`
- `NIL_UID` → CustomerProfile exists but `lockbox_uid` is `nil`. Next login will auto-link via `find_customer_profile_for_authorizing_user`. No action needed; just have the user log in.
- `NO_PROFILE` → no CustomerProfile for that email. Run Phase 3 seed.
- `NO_RECENT_LOGIN` → not enough info. Have the user try one login, then re-run triage.

**(b) Dev-server error scan (last few minutes):**

Check both layers — customer-admin sees the 5xx status, ai-mastra-postgres sees the actual SQL error:

```bash
# customer-admin: 4xx/5xx on the mastra-proxy session endpoint
docker logs --since 5m customer-admin-customer-admin-1 2>&1 \
  | grep -E 'POST .*/api/mastra/customers/app/sessions [45][0-9][0-9]' | tail -5

# customer-admin: proxy-layer cause (502s surface HERE, not in the DB log)
docker logs --since 5m customer-admin-customer-admin-1 2>&1 \
  | grep -iE 'ECONNREFUSED|\[proxy\]|fetch failed|:4111' | tail -5

# ai-mastra-postgres: actual DB errors (this is where "column does not exist" shows up)
docker logs --since 5m ai-mastra-postgres 2>&1 \
  | grep -iE 'error|fatal|does not exist' | tail -5
```

Classify:

- `... sessions 502` **+** proxy log shows `ECONNREFUSED ...:4111` / `[proxy] ... fetch failed` → **the mastra gateway isn't running** (host process on `:4111`). This is the single most common "Couldn't start your session" cause right after the stack boots — it is NOT auth/schema/data. customer-admin proxies session-create to `host.docker.internal:4111` and nothing is listening. Confirm with `lsof -i :4111` (free = down), then have the user start the gateway — see "Starting the gateway" in Phase 2.
- `... sessions 500` **+** DB log shows `column "X" does not exist` → **pending app-level migration** in `apps/ai-mastra/migrations/`. Fix in Phase 2: `pnpm migrate:up`. Do NOT reach for `init-mastra-storage.ts` first — that only handles Mastra's built-in tables (threads/messages/traces), not app schema.
- `... sessions 500` with no DB error visible → may be a code-level throw in surfaces. Have user paste the stack from their gateway terminal.
- `... sessions 401` → JWT minted before reseed/repoint, or `audience_type: "unknown"` (ES miss). Log out + back in; if persistent, reindex CustomerProfile (see 403 row in Common problems).
- `... sessions 403` → audience_type "unknown" specifically; reindex.

### Phase 2 — Fix what's broken (in dependency order)

For each DOWN service, bring it up. Stop and ask for confirmation before
anything destructive.

1. **colima** — `colima start`
2. **hbdev** — `docker compose -f ~/Sites/homebotapp/hbdev/docker-compose.yml -p hbdev up -d`
3. **surfaces-db** — `cd ~/Sites/homebotapp/surfaces && docker compose up -d` then immediately
   `docker stop ai-mastra && docker rm ai-mastra` (the compose file starts an `ai-mastra` app
   container that conflicts with the host `pnpm dev`; only `ai-mastra-postgres` should remain)
4. **lockbox** — `cd ~/Sites/homebotapp/lockbox && docker compose up -d`, then poll
   `docker logs --tail 3 lockbox` until "Listening on" appears (timeout 120s)
5. **mikasa** — `cd ~/Sites/homebotapp/mikasa && docker compose up -d`, then poll
   `docker logs --tail 3 mikasa` until "Listening on" appears (timeout 120s)
6. **customer-admin** — `cd ~/Sites/homebotapp/customer-admin && docker compose up -d`,
   then poll `docker logs --tail 3 customer-admin-customer-admin-1` until "Ready"
   appears (timeout 120s). Ensure `MASTRA_SANDBOX_ENABLED=true` is in `.env.docker`.

**TLS cert if missing:**

```bash
security find-certificate -a -c homebot.test -p /Library/Keychains/System.keychain > /tmp/homebot-ca.pem
test -s /tmp/homebot-ca.pem || echo "CA not in keychain — run: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Sites/homebotapp/hbdev/.infra/tls/ca.pem"
```

**Doppler `MARKETHUB_DATABASE_URL` if unset (needed for Partner Intel data):**

The `?sslmode=disable` suffix is REQUIRED — `pool.ts` (`resolveSsl`) defaults to
SSL-on, and local Postgres rejects encrypted connections without it. Omitting it
is silent: markethub resolvers just return no data.

```bash
cd ~/Sites/homebotapp/surfaces \
  && doppler secrets set MARKETHUB_DATABASE_URL='postgres://postgres:secret@localhost:5432/mikasa_listings_development?sslmode=disable'
```

**Seed the partner-data table (if Phase 1 reported `MISSING` or empty):**

`agent_lo_relationships` backs the "partners to call" tool and is NOT produced by any
mikasa seed. A static, idempotent seed ships **with this skill**. It builds rows from
whatever `dim_loan_officer` × `dim_agents` are already seeded (so it self-corrects
across reseeds) and populates all 15 timeframes with deterministic, plausible metrics,
forcing `deals_together_12m ≥ 1` so the default window always renders:

```bash
docker exec -i hbdev_postgres psql -U postgres -d mikasa_listings_development -v ON_ERROR_STOP=1 \
  < ~/.claude/skills/start-dev/seed-agent-lo-relationships.sql
```

Expect `INSERT 0 240` (30 seeded LOs × 8 agents). Idempotent: `CREATE TABLE IF NOT
EXISTS` + `TRUNCATE` + `INSERT`. **Re-run after any listings-DB reseed** (`/start-dev
reset` or a mikasa `db:drop`) — the table is dropped with the DB and nothing else
recreates it. No gateway restart needed: the resolver reads the table live per request.

If `INSERT 0 0`, the `dim_*` tables aren't seeded yet — run Phase 3
(`seeds:markethub_setup`) first, then re-run this seed.

**Stale ports holding 3000/4111:** detect with `lsof -ti :<port> -sTCP:LISTEN`,
check `ppid` — if 1 (orphaned), kill it. Otherwise leave it; that's the user's
running `pnpm dev`.

**Surfaces code fixes if stale** (only when Phase 1 reports `ssl-code:OLD…` or
`coalesce-patch:MISSING` — i.e. the clone is on a pre-PR-#663 branch). Both fixes
landed in `main`, so normally there is nothing to do here. If a check is stale,
prefer pulling/rebasing `main` over hand-patching; if you must hand-patch, show
the diff and ask the user to approve.

- SSL — do **NOT** re-introduce the old `isAurora` patch. The current code reads
  `sslmode` from the DSN (`resolveSsl`); the only local requirement is the DSN's
  `?sslmode=disable` (the Doppler set command above). A stale `ssl-code:OLD…`
  means `pool.ts` predates PR #663 — pull `main`.
- ⚠️ **OBSOLETE on current `main`.** `entities.ts` no longer contains
  `LO_AGENT_CONNECTIONS_SQL` and no longer calls `markethub_lo_agent_connections(...)`
  with date params — the resolver migrated to `buildLoAgentConnectionsSql` reading the
  `agent_lo_relationships` table (no date args, timeframe-suffixed columns instead). The
  COALESCE-on-missing-dates patch below applies ONLY to a pre-migration branch; on
  `main` the partner-data problem is a **missing table**, not a NULL-date bug — see the
  Phase 1 "Partner-data table check" and Phase 2 "Seed the partner-data table". Kept for
  historical branches:
  ```sql
  SELECT *
  FROM markethub_lo_agent_connections(
    $1::text,
    COALESCE($2::date, (CURRENT_DATE - INTERVAL '5 years')::date),
    COALESCE($3::date, CURRENT_DATE)
  )
  LIMIT 200
  ```

**Mastra storage schema drift (from Phase 1.5 dev-server error scan):**

If Phase 1.5 detected `POST .../sessions 500`, the underlying cause is almost
always one of two things:

1. **Application schema drift** — a migration in `apps/ai-mastra/migrations/`
   hasn't been applied. Most common cause; happens after switching surfaces
   clones or pulling a branch that adds columns to `app_sessions`,
   `app_async_jobs`, etc.
2. **Mastra built-in table drift** — Mastra's own threads/messages/traces
   tables are missing or out of date. Rare.

Diagnose by checking the DB-side error directly:

```bash
docker logs --since 5m ai-mastra-postgres 2>&1 \
  | grep -iE 'error|fatal|does not exist' | tail -5
```

If you see `column "X" does not exist`, that's case 1 — pending migration.

**Fix for case 1 (the common one):**

```bash
cd ~/Sites/homebotapp/surfaces/apps/ai-mastra && pnpm migrate:up
```

`pnpm migrate:up` runs `doppler run -- node-pg-migrate up --migrations-dir migrations --database-url-var MASTRA_DATABASE_URL`. Idempotent — applied migrations are tracked in a `pgmigrations` table.

**Fix for case 2 (Mastra built-ins):**

```bash
cd ~/Sites/homebotapp/surfaces \
  && doppler run -- pnpm --filter @homebotapp/ai-mastra exec tsx src/scripts/init-mastra-storage.ts
```

This only handles Mastra's own tables (threads/messages/traces) — it does NOT
run app-level migrations. Don't reach for it as a catch-all.

After either fix, the user MUST restart their host gateway (see "Starting the
gateway" below) so mastra drops its cached connection pool. The skill can't do
this itself; remind the user.

**Starting the gateway (host process — the user runs this, never the skill):**

The ai-mastra gateway on `:4111` is what customer-admin proxies session-create
to. If `lsof -i :4111` shows it free, the chat 502s with `ECONNREFUSED :4111`
(see Phase 1.5b) — it must be started from the surfaces repo.

There is a multi-clone trap here. `ai-mastra-postgres` has a hardcoded
`container_name` and fixed port `5437`, so only ONE such container exists
host-wide, and whichever surfaces clone started it OWNS it:

```bash
docker inspect ai-mastra-postgres \
  --format '{{ index .Config.Labels "com.docker.compose.project" }}  ({{ .State.Health.Status }})'
# e.g. "surfaces-reviews  (healthy)" — owned by the surfaces-reviews clone
```

If the owning project ≠ the clone the user wants the gateway from, then
`pnpm dev` / `pnpm mastra:dev` from that other clone FAILS its `docker:postgres`
pre-step with `Conflict. The container name "/ai-mastra-postgres" is already in
use`. (The sibling `lab-next` task then exits 255 — that's just turbo tearing
down the parallel task, not a separate bug.)

**Do NOT `docker rm` the container to clear the conflict** — it's the shared DB
the other clone is actively using; removing it wipes that clone's mastra storage

- sessions. The container is already healthy on 5437 and `MASTRA_DATABASE_URL`
  points there regardless of which clone started it. The fix is to start the
  gateway _directly_, skipping the redundant docker pre-step:

```bash
# No watch (simplest — enough to unblock the chat):
cd ~/Sites/homebotapp/surfaces/apps/ai-mastra && pnpm start

# Watch / hot-reload:
cd ~/Sites/homebotapp/surfaces/apps/ai-mastra \
  && doppler run -- pnpm exec tsx --conditions development --watch src/gateway.ts
```

`tsx` PATH gotcha: a bare `doppler run -- tsx …` fails with
`exec: "tsx": executable file not found in $PATH` — `tsx` lives in
`node_modules/.bin`, which only lands on `$PATH` when the command runs THROUGH
pnpm. Always route via `pnpm start` or `pnpm exec tsx`, never bare `tsx`.

Confirm the gateway is serving before telling the user to retry:

```bash
lsof -i :4111 -sTCP:LISTEN >/dev/null 2>&1 \
  && curl -s -o /dev/null -w 'sessions probe → %{http_code}\n' \
       -X POST http://localhost:4111/customers/app/sessions \
  || echo 'port 4111 still free — gateway not up'
# 401 = gateway up & enforcing auth (good — the real JWT will authorize).
# no output / 000 = still down.
```

With the gateway up, the user clicks **Try Again** in the modal — no reload or
re-login needed if Phase 1.5 auth was `LINKED`.

**Auth reconnect (from Phase 1.5 auth health):**

If Phase 1.5 reported `auth_mikasa:MISMATCH`, jump to the "Repointing the PI LO
between consumers" section near the end of this skill. The mismatch line in
Phase 1.5 output gives both `mikasa_uid` and `jwt_sub` — drop the latter into
the repoint command:

```bash
docker exec mikasa bin/rails runner '
  cp = LoanOfficer.find_by(email: "<email from JWT>")
  cp.update!(lockbox_uid: "<jwt_sub from Phase 1.5>")
'
```

This makes mikasa match whichever consumer the user is currently logged into.
If they need to flip back (e.g. labs-next ↔ customer-admin), re-run with the
other consumer's `jwt_sub`. The repointing section has both pre-discovered UUIDs
for the canonical PI test user.

If `auth_mikasa:NIL_UID`: no action needed — the next login through
`/customer-profiles/whoami` auto-links via `find_customer_profile_for_authorizing_user`
at `mikasa/app/controllers/customer_profiles_controller.rb:293`.

If `auth_mikasa:NO_PROFILE`: skip ahead to Phase 3 seed.

### Phase 3 — Seed the LO (customer-admin / labs-next `/customers` side)

Check for the deterministic Partner Intel LO. If missing or incomplete, seed.

```bash
docker exec mikasa bin/rails runner "
pi = CustomerProfile.find_by(email: 'PartnerIntelUserV2+lenderIndividual@homebot.ai')
puts \"pi_exists=#{!pi.nil?}\"
puts \"pi_id=#{pi&.id}\"
puts \"pi_nmls=#{pi&.nmls}\"
puts \"homeowner_count=#{pi ? Client.where(customer_profile_id: pi.id).count : 0}\"
"
```

- If `pi_exists=false` → run `docker exec mikasa bin/rake seeds:markethub_setup`
- If `homeowner_count < 50` → run `docker exec mikasa bin/rake "seeds:generate_homeowners[<pi_id>,100]"`
- Both tasks are additive — safe to re-run.

**Compile opportunity lists.** Homeowners exist, but the chat tool
`getClientOpportunities` queries `opportunity_status_logs` — a join table that
stays empty until something _evaluates_ each client against each opportunity
list. Without this step, the chat returns "no qualified opportunities" even
with hundreds of seeded clients.

Check first to avoid re-compiling unnecessarily:

```bash
docker exec mikasa bin/rails runner "
pi_id = '<pi_id_from_step_above>'
qualified = OpportunityStatusLog.where(customer_profile_id: pi_id).where.not(state: 'unqualified').count
puts \"qualified=#{qualified}\"
"
```

If `qualified < 50`, run the compile:

```bash
docker exec mikasa bin/rake "one_and_done:compile_opportunity_lists_for_customer_profile[<pi_id>]"
```

This takes a few minutes and is idempotent (creates new logs with later
`created_at`, the query takes the latest per pair). On a freshly-seeded PI LO
with ~519 clients, expect ~100 qualified `likely_to_sell` rows. Other list
types (Ready for Refi, High Equity, Just Listed, Likely to Buy, Highly
Engaged) require loan / listing / event data that `basic_homeowner` doesn't
generate — those will remain at 0 until richer seed data is added.

**Verify the PI profile is indexed in elasticsearch.** Lockbox queries the
`customers-development` index at JWT-issuance time to populate `audience_type`,
`customer_id`, `customer_type`. If the profile isn't there (fresh ES container
after a colima restart, or seed callbacks didn't fire), the JWT comes back with
`audience_type: "unknown"` and every `/api/mastra/customers/app/*` route 403s.

```bash
PROFILE_ID=$(docker exec mikasa bin/rails runner \
  "puts CustomerProfile.find_by!(email: 'PartnerIntelUserV2+lenderIndividual@homebot.ai').id" 2>&1 | tail -1)

curl -sk -o /dev/null -w "%{http_code}\n" \
  "https://es.homebot.test/customers-development/_doc/${PROFILE_ID}"
```

- `200` → profile is indexed, you're done.
- `404` (doc not found) → reindex via runner:
  ```bash
  docker exec mikasa bin/rails runner \
    "CustomerProfile.find_by!(email: 'PartnerIntelUserV2+lenderIndividual@homebot.ai').__elasticsearch__.index_document"
  ```
- `index_not_found_exception` → whole index missing, rebuild it:
  ```bash
  docker exec mikasa bin/rails runner "CustomerProfile.import"
  ```

### Phase 3.5 — Seed the Client (labs-next `/clients` side)

The client portal at `https://surfaces-lab-next.homebot.test/clients` needs a
homeowner who can log into Lockbox. The lab-next README points at
`testclient@homebot.ai` / `Secret123!`, but it's not in any seed task — devs
create it manually. The skill automates that.

The chain is:

1. **Lockbox** auth user must exist with `created_from_clients: true` (else JWT
   gets `audience_type: "unknown"` → 403 on every `/clients` route).
2. **Mikasa** must have a matching `Client` record linked to the PI LO so the
   JWT's identity maps to data the agent can read.
3. **Enrichment**: `seed-mastra-test-data.sh` populates `legacy_home_data`,
   `legacy_home_avms`, `legacy_home_loans`, and `clients.mobile` for _all_
   clients under the PI LO — this is what makes the chat experience rich.

**Step 1 — Lockbox user.** Schema-verified: `User` requires `email` + `password`
(8-72 chars, must contain digit + lower + upper + symbol). `Secret123!` passes.
Optional first/last name kept for readability.

```bash
docker exec lockbox bundle exec rails runner "
u = User.find_or_initialize_by(email: 'testclient@homebot.ai')
if u.new_record?
  u.first_name = 'Test'
  u.last_name = 'Client'
  u.password = 'Secret123!'
  u.password_confirmation = 'Secret123!'
  u.created_from_clients = true
  u.save!
  puts \"created uid=#{u.id}\"
elsif !u.created_from_clients
  u.update!(created_from_clients: true)
  puts \"updated_flag uid=#{u.id}\"
else
  puts \"exists uid=#{u.id}\"
end
"
```

If this fails, do NOT swallow the error — read it, adjust, retry.

**Step 2 — Capture the Lockbox UID for the next step:**

```bash
LOCKBOX_UID=$(docker exec lockbox bundle exec rails runner \
  "puts User.find_by!(email: 'testclient@homebot.ai').id" 2>&1 | tail -1)
```

**Step 3 — Matching mikasa Client record.** Schema-verified: `Client` requires
`customer_profile`, `_id` (24-char hex BSON ObjectId — Homebot's Mongo legacy
ID), `email`, and the validator-required `name` field (which is a derived
getter from `first_name + last_name` — there's no `name=` setter, you must
pass `first_name`/`last_name` separately). Link via `lockbox_uid` column.
Use the `:basic_homeowner` factory so the client comes pre-wired with
home/equity data (matches what `seeds:generate_homeowners` produces).

```bash
docker exec mikasa bin/rails runner "
require 'factory_bot_rails'
pi = CustomerProfile.find_by!(email: 'PartnerIntelUserV2+lenderIndividual@homebot.ai')
existing = Client.find_by(email: 'testclient@homebot.ai')
if existing
  existing.update!(lockbox_uid: '${LOCKBOX_UID}', customer_profile_id: pi.id) \
    if existing.lockbox_uid != '${LOCKBOX_UID}' || existing.customer_profile_id != pi.id
  puts \"exists client_id=#{existing.id} _id=#{existing._id}\"
else
  c = FactoryBot.create(:basic_homeowner,
    customer_profile: pi,
    email: 'testclient@homebot.ai',
    first_name: 'Test',
    last_name: 'Client',
    lockbox_uid: '${LOCKBOX_UID}'
  )
  puts \"created client_id=#{c.id} _id=#{c._id}\"
end
"
```

**Step 4 — Enrich client home data:**

```bash
PI_ID=$(docker exec mikasa bin/rails runner \
  "puts CustomerProfile.find_by!(email: 'PartnerIntelUserV2+lenderIndividual@homebot.ai').id" 2>/dev/null | tail -1)

CUSTOMER_PROFILE_ID="$PI_ID" \
  ~/Sites/homebotapp/surfaces/apps/ai-mastra/src/scripts/seed-mastra-test-data.sh
```

This script is idempotent and seeds enrichment for every Client under the PI
LO — `testclient@homebot.ai`, the 100 homeowners from `generate_homeowners`,
and any others. After it runs the chat has real data to display.

### Phase 4 — Verify markethub data is queryable end-to-end

⚠️ Verify the object the resolver **actually** reads — the `agent_lo_relationships`
table — NOT the legacy `markethub_lo_agent_connections()` function. Querying the
legacy function is a **false green**: it can return rows while the live tool is dead,
because the resolver migrated off it. (This exact stale check masked a real outage
once — verify the table.)

```bash
# 1. The table the partners tool reads, scoped to the PI login's NMLS:
docker exec hbdev_postgres psql -U postgres -d mikasa_listings_development -tAc \
  "SELECT count(*) FROM agent_lo_relationships
   WHERE loan_officer_nmls_id='03000000' AND deals_together_12m>0;"
```

Expect a non-zero count (PI user `03000000` gets 8 partner rows from the bundled seed).
If 0 → run Phase 2 "Seed the partner-data table". If the table is missing entirely,
Phase 1's partner-data check already flagged it.

```bash
# 2. End-to-end through the gateway (the tool's real path). Needs the host gateway
#    on :4111 (Phase 2) and the surfaces Doppler env for the API key:
cd ~/Sites/homebotapp/surfaces && doppler run -- bash -c '
  Q="query(\$n:ID!){ loanOfficer(filter:{nmlsId:{eq:\$n}}){ agentConnections(timeframe: MONTHS_12){ agentName dealsWithYou } } }"
  curl -s "${SEMANTIC_GRAPHQL_URL:-http://localhost:4111/graphql}" -X POST \
    -H "content-type: application/json" -H "x-api-key: $SEMANTIC_API_KEY" \
    --data "{\"query\":\"$Q\",\"variables\":{\"n\":\"03000000\"}}" | head -c 400'
```

Good = a `data.loanOfficer.agentConnections` array of agents. Bad = `INTERNAL_ERROR` /
`serviceName: markethub` → the table is missing or empty (Phase 2 seed), or `:4111` is
down (Phase 2 "Starting the gateway"), or a 401 means you didn't run under
`doppler run` (no `SEMANTIC_API_KEY`).

### Phase 5 — Final status report

```
✓ Stack ready
─────────────
Containers:  all up
Gateway:     :4111 — if free, start it (Phase 2 "Starting the gateway"). Mind the
             clone-ownership trap: from a non-owning clone use
             `cd apps/ai-mastra && pnpm start`, NOT `pnpm dev`/`pnpm mastra:dev`.
ssl-local:   ✓ (DSN has ?sslmode=disable)   coalesce ✓
LO seed:     PI user exists (NMLS 03000000, 100 homeowners)
Partner data: agent_lo_relationships seeded (8 partner rows for NMLS 03000000) — the
             "partners to call" tool source; re-seed after any listings-DB reset
Client seed: testclient@homebot.ai linked to PI LO, enrichment data loaded

Log in as LO (customer-admin OR labs-next /customers):
  https://customer-admin.homebot.test/en
  https://surfaces-lab-next.homebot.test/customers   (after gateway + labs-next up)
  → PartnerIntelUserV2+lenderIndividual@homebot.ai / Secret1!

Log in as Client (labs-next /clients):
  https://surfaces-lab-next.homebot.test/clients     (after gateway + labs-next up)
  → testclient@homebot.ai / Secret123!
```

**Stale-session warning.** JWTs from any previous login (including from before
this skill ran) bake in `audience_type`, `customer_id`, and the auth UUID at
issuance time. A pre-existing browser session will hit:

- `Record not found ... <some-uuid>` — JWT points at a user that no longer
  exists (db:drop wiped them).
- 403 on `/api/mastra/customers/app/sessions` — JWT has stale or "unknown"
  audience_type.

If the report just regenerated seed data after a wipe/reset, end with:

> Before logging in, clear cookies for `*.homebot.test` (DevTools → Application
> → Cookies → right-click "Clear") or use an incognito window. Otherwise your
> existing JWT may reference users that no longer exist.

If the gateway (`:4111`) isn't running, remind the user to start it per Phase 2
"Starting the gateway" — don't try to start a long-running host process from the
skill, and don't suggest a bare `pnpm dev` without first checking which clone
owns `ai-mastra-postgres`.

---

## `/start-dev status` — triage only, no changes

Run Phase 1 above. Report the state. Do NOT apply any fixes. End with a
"Problems Found" list and one-line fix suggestion per problem.

---

## `/start-dev down`

Stop in reverse dependency order:

```bash
cd ~/Sites/homebotapp/customer-admin && docker compose down
cd ~/Sites/homebotapp/mikasa && docker compose down
cd ~/Sites/homebotapp/lockbox && docker compose down
cd ~/Sites/homebotapp/surfaces && docker compose down
docker compose -f ~/Sites/homebotapp/hbdev/docker-compose.yml -p hbdev down
colima stop
```

Do NOT kill the host `pnpm dev` processes — the user owns those terminals.

---

## `/start-dev seed`

Run Phase 3 + Phase 4 only, plus the Phase 2 "Seed the partner-data table" step
(`agent_lo_relationships`). Useful when the stack is already up but data is missing
(e.g. after pulling a fresh mikasa migration, or after a listings-DB reseed that
dropped `agent_lo_relationships`).

---

## `/start-dev reset` — DESTRUCTIVE

Drops and recreates the mikasa databases, then re-seeds from scratch. **Always**
prompt for confirmation first (AskUserQuestion) with this question:

> This will drop and recreate `mikasa_development` and `mikasa_listings_development`,
> wiping ALL local seed data. Type "reset" to confirm.

Only proceed if confirmed.

```bash
docker exec mikasa bin/rails db:drop db:create db:migrate
docker exec mikasa bin/rake seeds:markethub_setup
# Then look up the new pi_id and run generate_homeowners

# db:drop wiped agent_lo_relationships too — re-seed it (seeds:markethub_setup does NOT):
docker exec -i hbdev_postgres psql -U postgres -d mikasa_listings_development -v ON_ERROR_STOP=1 \
  < ~/.claude/skills/start-dev/seed-agent-lo-relationships.sql
```

After reset, you'll need to manually restart `pnpm mastra:dev` so it drops the
cached pool. Remind the user.

---

## Known surfaces bugs (PR #663, merged 2026-05-07)

These caused silent failures — the chat returns "no data" answers that look like
the user simply has no data. Both fixes are now in `main`, in
`surfaces/apps/ai-mastra/src/graphql/market-subgraph/`:

1. **pool.ts** — originally hardcoded `ssl: { rejectUnauthorized: false }`, which
   broke local Postgres (no SSL). The fix evolved PAST the PR #663 `isAurora`
   hostname check: `pool.ts` now derives SSL from the DSN's `sslmode` param via
   `resolveSsl()`. So there is **no code patch to apply** anymore — local
   correctness is purely "`MARKETHUB_DATABASE_URL` ends with `?sslmode=disable`".
   Phase 1's `ssl-code:current` confirms the code is on the new path; `ssl-local`
   confirms the DSN. (The old `grep isAurora` check was a permanent
   false-positive — removed 2026-05-27.)
2. **entities.ts** `LO_AGENT_CONNECTIONS_SQL` passed `null` for missing dates —
   Postgres function defaults don't apply for explicit-NULL, so the function
   returned 0 rows. Fix: wrap in COALESCE. ⚠️ **Now historical** — a later migration
   replaced this whole resolver path (legacy function + date args) with the
   `agent_lo_relationships` table read. On current `main` the `coalesce-patch` grep is
   a dead signal; the live partner-data risk is a **missing/empty
   `agent_lo_relationships` table** (Phase 1 check, Phase 2 seed).

Since both landed in `main`, a clone tracking `main` already has them — only act
if `ssl-code` comes back stale (user is on an old branch). `coalesce-patch` no longer
applies to `main` (see note above).

---

## Common problems

| Symptom                                                                                         | Cause                                                                                            | Check                                                                           |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| 502 on `surfaces-lab-next.homebot.test`                                                         | `pnpm dev` not running                                                                           | port-3000 listening?                                                            |
| Chat says "no transactions" / "no opportunities"                                                | Markethub patches missing OR seed didn't run                                                     | Phase 1 + Phase 3                                                               |
| "Partners to call" tool reports a "lookup outage" / "Agent connections lookup failed"           | `agent_lo_relationships` table missing/empty (ELT artifact, no local seed) — NOT auth/identity   | Phase 1 "Partner-data table check"; fix via Phase 2 "Seed the partner-data table" |
| 500 with `mastra_threads` missing                                                               | Mastra storage init not run                                                                      | See init script                                                                 |
| 404 on every route                                                                              | Stale package builds                                                                             | `pnpm build`                                                                    |
| `EADDRINUSE :::4111`                                                                            | Orphaned pnpm process                                                                            | Stale port detection                                                            |
| Login redirect loop                                                                             | `/tmp/homebot-ca.pem` missing                                                                    | TLS check                                                                       |
| `Record not found <uuid>` in layout                                                             | Stale JWT, OR consumer↔mikasa lockbox_uid mismatch                                               | See "Repointing the PI LO" below                                                |
| "Couldn't start your session" modal · `POST /customers/app/sessions 502` + `ECONNREFUSED :4111` | mastra gateway (host `:4111`) not running                                                        | `lsof -i :4111` (free = down); start gateway per Phase 2 "Starting the gateway" |
| `sessionCreationFailed` in surfaces gateway, `POST /customers/app/sessions 500`                 | Pending `apps/ai-mastra/migrations/*.sql` not applied (e.g. `audience` column on `app_sessions`) | `cd apps/ai-mastra && pnpm migrate:up` + restart gateway                        |
| 403 on `/api/mastra/customers/app/sessions`                                                     | JWT `audience_type: "unknown"` (ES miss)                                                         | Reindex CustomerProfile + re-login                                              |
| Chat says "no qualified opportunities"                                                          | `opportunity_status_logs` empty (compile not run)                                                | Run `compile_opportunity_lists_for_customer_profile`                            |

### Repointing the PI LO between consumers (labs-next ↔ customer-admin)

**Symptom:** `whoami` returns 404 with `Record not found <uuid>`, but you already cleared cookies and re-authed. One consumer works, the other 404s — flipping the consumer flips which one breaks.

**Why this happens:** mikasa links auth → data via `CustomerProfile.lockbox_uid == JWT.sub_id` (`app/models/authorizing_user.rb:101`). The `PartnerIntelUserV2+lenderIndividual@homebot.ai` account has **two distinct lockbox user records** for the same email — one per consumer — and they hand out different `sub`s:

| Consumer                         | JWT `sub` (lockbox user)               |
| -------------------------------- | -------------------------------------- |
| `surfaces-lab-next.homebot.test` | `5e66cc56-7baf-4785-bbb4-a1c202b58cab` |
| `customer-admin.homebot.test`    | `d915c796-361e-412b-8719-048e0de11069` |

Mikasa's `LoanOfficer.lockbox_uid` column can only hold one of those at a time. Whichever it holds is the consumer that works; the other 404s. (The "right" fix is at the auth layer — figure out why two lockbox records exist for one email — but that's a separate investigation. The pragmatic fix is to repoint mikasa when you swap consumers.)

**Repoint command** (run after a reseed _or_ when switching consumers):

```bash
# For testing in customer-admin:
docker exec mikasa rails runner '
  cp = LoanOfficer.find_by(email: "PartnerIntelUserV2+lenderIndividual@homebot.ai")
  cp.update!(lockbox_uid: "d915c796-361e-412b-8719-048e0de11069")
  puts "→ customer-admin (#{cp.email} lockbox_uid=#{cp.lockbox_uid})"
'

# For testing in labs-next:
docker exec mikasa rails runner '
  cp = LoanOfficer.find_by(email: "PartnerIntelUserV2+lenderIndividual@homebot.ai")
  cp.update!(lockbox_uid: "5e66cc56-7baf-4785-bbb4-a1c202b58cab")
  puts "→ labs-next (#{cp.email} lockbox_uid=#{cp.lockbox_uid})"
'
```

**Confirm which sub each consumer is sending** before assuming the UUIDs above are still correct. Decode the JWT in the browser cookie:

- customer-admin cookie: DevTools → Application → Cookies → `homebot-session-cookie` (URL-decoded JSON has `access_token`)
- labs-next: the surfaces server logs print `userId: <uuid>` on `POST /customers/app/sessions`

Paste the JWT payload (base64-decode the middle segment) and read `sub` — that's the UUID to put in `lockbox_uid`.

**Verified 2026-05-13:** The repoint command works end-to-end. Updates `LoanOfficer.lockbox_uid` and the next `whoami` succeeds without any cache invalidation or re-auth on mikasa's side (the JWT-trust cache is keyed on the JWT itself, not the lookup result). The browser still uses its existing cookie — no need to clear it.

---

For Mastra storage init:

```bash
cd ~/Sites/homebotapp/surfaces \
  && doppler run -- pnpm --filter @homebotapp/ai-mastra exec tsx src/scripts/init-mastra-storage.ts
```

---

## Paths

```
~/.claude/skills/start-dev/seed-agent-lo-relationships.sql   # bundled partner-data seed (Phase 2)
~/Sites/homebotapp/hbdev/docker-compose.yml
~/Sites/homebotapp/hbdev/.infra/tls/ca.pem
~/Sites/homebotapp/surfaces/docker-compose.yml
~/Sites/homebotapp/surfaces/apps/ai-mastra/src/graphql/market-subgraph/pool.ts
~/Sites/homebotapp/surfaces/apps/ai-mastra/src/graphql/market-subgraph/entities.ts
~/Sites/homebotapp/lockbox/docker-compose.yml
~/Sites/homebotapp/mikasa/docker-compose.yml
~/Sites/homebotapp/mikasa/lib/tasks/seeds/markethub_setup.rake
~/Sites/homebotapp/mikasa/lib/tasks/seeds/generate_homeowners.rake
~/Sites/homebotapp/customer-admin/docker-compose.yml
~/Sites/homebotapp/customer-admin/.env.docker
```
