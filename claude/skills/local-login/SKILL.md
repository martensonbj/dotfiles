---
name: local-login
description: One-command local login — /login [all|customer-admin|cfe|lab-next] [email]. Repairs login-blocking drift (dead containers, mikasa lockbox creds, stale CA pem), finds or seeds a usable user, and delivers a ready-to-paste login URL per app. Complements /start-dev (stack boot); this skill owns authentication.
argument-hint: "[all|customer-admin|cfe|lab-next] [email]"
allowed-tools: Bash, Read, AskUserQuestion
---

# Login — get me signed in, whatever it takes

`$ARGUMENTS` = `[target] [email]`. Target defaults to `customer-admin`.
`all` = customer-admin + cfe from the same seed family. Email pins a specific
user (never silently substitute a different one — repair or report instead).

Division of labor: **`/start-dev`** boots and triages the whole stack;
**`/login`** assumes a mostly-alive stack and owns the path from "stack up" to
"authenticated in a browser." When Phase 0 finds the stack fundamentally down
(postgres/traefik missing, mikasa won't boot), stop and point to `/start-dev`.

## Persona per target

| Target           | Logs in as                  | Landing                               |
| ---------------- | --------------------------- | ------------------------------------- |
| `customer-admin` | LoanOfficer CustomerProfile | `/en/dashboard`                       |
| `cfe`            | homeowner Client of that LO | `/reports/<client_id>/home/<home_id>` |
| `lab-next`       | the LO customer             | `/customers`                          |

## Shared paths

```bash
# hb plugin scripts (resolve newest cached version — do NOT hardcode)
HB_SKILLS=$(ls -d ~/.claude/plugins/cache/homebotapp/hb/*/skills 2>/dev/null | sort -V | tail -1)
RESOLVER="$HB_SKILLS/e2e-seed/scripts/find-usable-customer.rb"
SEEDER="$HB_SKILLS/e2e-seed/scripts/seed-profile.rb"
AUTH_SETUP="$HB_SKILLS/e2e-seed/scripts/auth-setup.rb"
VERIFY_SYNC="$HB_SKILLS/e2e-seed/scripts/verify-sync.rb"
```

---

## Phase 0 — repair login-blocking drift (fix, don't just report)

Run all checks; fix what's listed; anything else → `/start-dev status`.

### 0a. Containers (docker restart leaves app stacks exited; only hbdev_* returns)

```bash
docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E '^(mikasa|lockbox)'
```

Anything `Exited` → start dependencies first, then apps:

```bash
docker start lockbox_postgres lockbox_redis mikasa_redis 2>/dev/null; sleep 3
docker start lockbox lockbox_sidekiq mikasa mikasa_sidekiq 2>/dev/null
```

### 0b. mikasa Lockbox OAuth creds (REQUIRED for the CFE login path)

```bash
docker exec mikasa sh -c '[ -n "$(printenv LOCKBOX_CLIENT_ID)" ] && [ "$EMAIL_ACCESS_TOKENS" = "true" ] && echo OK || echo MISSING'
```

`MISSING` → every `FrontendUris::Client.fetch_report_url` call (incl. the
chromebot endpoint) 500s with `ArgumentError: app_id and app_secret must be
passed in or set in the configuration block`. Fix: append to
`~/Sites/homebotapp/mikasa/.env` the three lines documented in its
`.env.example` (`EMAIL_ACCESS_TOKENS=true` + `LOCKBOX_CLIENT_ID/SECRET` — the
"Mikasa Local" ClientApplication values from lockbox `db/seeds.rb`), then
recreate: `cd ~/Sites/homebotapp/mikasa && docker compose up -d app sidekiq`
(services are `app`/`sidekiq`, not `mikasa`).

### 0c. CA pem freshness (customer-admin only; hbdev regenerates its CA)

```bash
cd ~/Sites/homebotapp/customer-admin && echo | openssl s_client -connect api.homebot.test:443 -CAfile homebot-root-ca.pem 2>/dev/null | grep -q 'Verify return code: 0' || /bin/cp -f ~/Sites/homebotapp/hbdev/.infra/tls/ca.pem homebot-root-ca.pem
```

(If replaced, the customer-admin dev server needs a restart —
`NODE_EXTRA_CA_CERTS` loads at process start. `scripts/check-cert.js` does NOT
catch expiry, so don't trust a passing preflight.)

### 0d. Target dev server up?

| App            | Check                                                | Start if down                                                          |
| -------------- | ---------------------------------------------------- | ---------------------------------------------------------------------- |
| customer-admin | `curl -sk https://customer-admin.homebot.test` ≠ 404/502 | `npm run dev` in customer-admin (background). Port 3000 busy? `lsof -ti :3000` — usually lab-next; ask before killing. |
| cfe            | `curl -sk https://c.homebot.test` = 200              | `make tunnel` + `./node_modules/.bin/vite` in clients-frontend-v2 (two background tasks; `pnpm start`'s concurrently is flaky). Module-resolution crashes (yargs `looksLikeNumber`, d3-path `Path`) = corrupted node_modules → `rm -rf node_modules && pnpm install`. |
| lab-next       | `lsof -i :4111` (gateway) + lab-next port            | `/start-dev` owns surfaces boot                                         |

Also flag (non-blocking): missing `MASTRA_PUBLIC_URL` in customer-admin `.env`
→ HomebotAI page renders blank. Local default `http://localhost:4111`.

---

## Phase 1 — resolve a usable user (read-only)

```bash
docker cp "$RESOLVER" mikasa:/tmp/find-usable-customer.rb
docker exec ${EMAIL:+-e EMAIL=$EMAIL} mikasa bundle exec rails runner /tmp/find-usable-customer.rb 2>/dev/null | grep -E '^[A-Z_]+='
```

- `RESOLVER_MATCH=true` → capture the `E2E_*` ids, go to Phase 3.
- `RESOLVER_MATCH=false` + specific email given → report why (`DATA_HEALTH`),
  offer `verify-sync.rb` repair; do NOT seed a different user.
- `RESOLVER_MATCH=false`, no email → Phase 2.

## Phase 2 — seed (only when nothing usable exists)

```bash
docker cp "$SEEDER" mikasa:/tmp/seed-profile.rb
docker exec mikasa bundle exec rails runner /tmp/seed-profile.rb 2>&1 | grep -E '^E2E_[A-Z_2]+='
```

Creates LO + 2 homeowners (real Denver addresses, pinned $525k core_logic
AVMs) + 1 buyer, all Lockbox-synced. **Never** use mikasa's
`seeds:basic_hbn_lender_partner_persona_setup` — it trips the "Client already
has an active LoanOfficer team membership" validation (broken as of 2026-07).

## Phase 3 — mint and deliver the login URL

Always set the password first (also sets `created_from_clients: true` on
clients — without it the JWT resolves `audience_type=unknown`):

```bash
docker cp "$AUTH_SETUP" lockbox:/tmp/auth-setup.rb
docker exec -e LOCKBOX_UID=<profile-uid> ${CLIENT_UID:+-e CLIENT_LOCKBOX_UIDS=$CLIENT_UID} lockbox bundle exec rails runner /tmp/auth-setup.rb
```

### customer-admin / lab-next (customer JWT)

`auth-setup.rb` prints a JWT for the profile UID. Build:

```
https://customer-admin.homebot.test/auth/callback?access_token=<jwt>&nonce=e2e&state=e2e&token_type=bearer
https://surfaces-lab-next.homebot.test/auth/callback?access_token=<jwt>&token_type=bearer&state=e2e
```

### cfe (client) — use the chromebot endpoint, nothing else

```bash
curl -sk "https://mikasa.homebot.test/chromebot/sign_in_link?email=<client-email-urlencoded>" | python3 -c 'import json,sys; print(json.load(sys.stdin)["report_url"], end="")'
```

Returns a production-shape URL (`state=<home_id>&type=homes` in query params).
**Do NOT use `local-auth`'s `local-magic-link.rb` for CFE** — it emits a random
`state` with no `type`, and CFE's `AuthCallback.tsx` treats `state` as the
resource id, so it bounces to the guest page (known bug, botfiles).

### Delivery (no browser MCP assumed)

1. `printf '%s' "$URL" | pbcopy` — tell the user it's in their clipboard.
   For `all`: clipboard gets the first URL; print both (JWT masked to
   first ~20 chars) so the second is copyable from the transcript.
2. Cookie hygiene: recommend incognito, or clear the app's cookies first —
   `homebot-session-cookie` (customer-admin) / `homebot-session-token` +
   `homebot-session-cookie` (CFE). Stale parent-domain `.homebot.test`
   cookies cause impersonation artifacts and guest bounces.
3. Fallbacks, always printed:
   - Password: app login page → email → "Sign in with password" → `TestPass1!`
   - MailHog magic-link email: `https://mail.homebot.test` (customer-admin
     and lab-next only — see CFE warning above)

## Verify (don't claim success blindly)

Probe the target with the minted URL's session where possible; otherwise state
exactly what was delivered and what the user should see (customer-admin:
dashboard greeting; CFE: digest with a real home value — a "$0 / almost ready"
modal means the seed's AVM pinning failed, re-run Phase 2's seeder which is
idempotent).

## Guardrails

- Never run against anything but local dev (scripts self-abort outside
  development/test — keep it that way).
- Ask before killing processes you didn't start (port squatters).
- Specific email given = that user or a repair report, never a substitute.
