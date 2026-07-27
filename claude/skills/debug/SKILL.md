---
name: debug
description: Debug a client-GPT or customer-GPT issue (homebotapp/surfaces) from any starting artifact — a Braintrust link, trace id, tool-call failure, console/stack error, or a word-of-mouth symptom ("customer GPT is showing X"). Routes the artifact to the right system of record (Braintrust · Sentry · Datadog · GitHub), traces wrapped errors down to their real cause, scopes blast radius, and confirms root cause with an independent signal before concluding.
---

# /debug — Homebot AI agent debugging

The thing being debugged is **almost always one of two agents in `homebotapp/surfaces`**:

- **customer GPT** → agent slug `customer-agent` (compliance variant: `customer-compliance-agent`)
- **client GPT** → agent slug `client-agent` (compliance variant: `client-compliance-agent`)

Both run in the `ai-mastra` app (`apps/ai-mastra/` in the `surfaces` monorepo). Start from that assumption and zone in fast. Only widen scope if the evidence contradicts it.

## The one rule that matters most

**The message you were handed is almost never the root cause.** Agent errors pass through layers that each rewrite them:

```
model-visible prose ("…lookup failed, please try again" / "I didn't return a response")
   └─ handleToolError wrapper (apps/ai-mastra/src/mastra/helpers/llm-visible-error.ts)
        • LLMVisibleError subclasses → prose passes through verbatim
        • everything else → generic `fallback` string to the model  ← what you usually see
        • the REAL error is captured as `.cause` → Sentry only (label `<toolName>Tool_failed`)
             └─ downstream cause (SemanticClientError / HTTP / DB connection timeout / Zod parse)
```

So: **the model's text and the Braintrust error are the wrapper. The real exception is in Sentry as the `.cause`.** Datadog usually won't have the agent error at all (ai-mastra exports traces to Braintrust, not Datadog APM/LLM-Obs).

## The universal loop

```
1. EXTRACT join keys from whatever you were given:
     which GPT (client/customer) · env (prod/staging/dev) · tool name · timestamp
     · trace id / root_span_id · user/customerProfileId · error message · file:line · service
2. CLASSIFY the layer:  UI ▸ agent/LLM ▸ tool ▸ backend (semantic layer) ▸ datastore
3. ROUTE to that layer's system of record (table below)
4. TRACE THE WRAPPER (the rule above) down to the real `.cause`
5. SCOPE it: one user or many? since when? → bad-data vs. systemic vs. a deploy
6. CONFIRM with an independent signal before concluding (e.g. DBM metrics, not just the error text)
```

## Systems of record

```
agent / tool / LLM spans    → Braintrust   (NOT Datadog)
captured exceptions         → Sentry        org=homebot, project=surfaces  (real cause = .cause)
infra · HTTP · logs · DBM   → Datadog        service ai-mastra = info logs only; backend + DB live here
source code (any repo)      → gh search code --owner homebotapp <term>
```

## Artifact → entry point

```
Braintrust link / trace id   → §A  resolve + read the trace, harvest metadata
tool-call failure / LLM msg  → §B  it's a wrapper → Sentry for <toolName>Tool_failed → read .cause
"customer/client GPT shows X"→ §B  pull the tool name out of the prose, then §B
console error / stack trace  → §C  service + file:line → gh search → read source
backend / DB suspicion       → §D  Datadog logs/APM/DBM
```

---

## §A — Start from a Braintrust link or trace id

Braintrust MCP. Project ids: `mastra-production` = `23c9e29a-680a-4971-b831-393a54a359b3` (resolve staging/dev by name).

```
resolve_object(url=<the braintrust link>)          # → object_id + root_span_id
# List the spans in the trace (NEVER select *, and scope by root_span_id):
sql_query(
  object_type=project_logs, object_ids=[<project id>],
  select="span_id, span_attributes.name AS span_name, created, error, metrics.errors AS errors",
  where="root_span_id = '<root_span_id>'", shape=traces, limit=50)
# Drill into the error span for the harvest (scope by root_span_id AND span_id, else linter blocks it):
sql_query(..., select="span_id, input, output, error, metadata",
  where="root_span_id='<rsid>' AND span_id='<sid>'", shape=spans, preview_length=4000, limit=1)
```

Harvest from `metadata`: `prompt.slug` (which GPT), `environment`, `user_id`/`customerProfileId`, `mastra-trace-id`, `runId`, and the `errorDetails.stack` (gives the **file:line** of the throw, e.g. `tools/get-lo-agent-connections.js:121`). The `error` field is the **wrapper** — go to §B for the cause.

Characterize frequency (systemic vs one-off) — note the lint needs a time bound:
```
sql_query(..., select="count(1) AS n, error", group_by="error",
  where="span_attributes.name = 'tool: ''<toolName>''' AND error IS NOT NULL AND created > now() - interval 14 day",
  order_by="n DESC")
```

## §B — Start from a tool failure, an LLM-visible message, or a word-of-mouth symptom

The model text is the wrapper. Get the real cause from Sentry.

1. **Identify the tool.** Tool files: `apps/ai-mastra/src/mastra/tools/<kebab-name>.ts`. Tool name is camelCase; the Sentry label is **`<toolName>Tool_failed`** (e.g. `getLoAgentConnections` → `getLoAgentConnectionsTool_failed`). If you only have prose, pull the tool name out of it.

2. **Find the issue(s) in Sentry** (org `homebot`, project `surfaces`, region `https://us.sentry.io`):
```
search_issues(organizationSlug=homebot, projectSlugOrId=surfaces,
  query="<toolName>Tool_failed", sort=freq)
```
Multiple groups for one label = multiple distinct `.cause`s (Sentry fingerprints on the cause). Read the top + the most-recent.

3. **Read the real cause** (the chained "During handling of the above exception…" block):
```
get_sentry_resource(resourceType=issue, organizationSlug=homebot, resourceId=<SHORT-ID>)
```
Note env (prod vs staging), `customerProfileId`, `release`, first/last seen, occurrences. The `.cause` is the actual exception (e.g. `SemanticClientError: … connection timeout`, an HTTP status, a Zod parse error).

Identity failures are *typed* and surface their own prose (`ToolAuthError`, `ToolWrongAudienceError`) — a clean message = identity/session issue; the **generic fallback = an untyped failure in the data path** (semantic layer / DB / parse).

## §C — Start from a console error or stack trace

```
gh search code --owner homebotapp "<symbol or error string>" --json repository,path
gh api repos/homebotapp/surfaces/contents/<path> --jq '.content' | base64 -d   # read the file
```
Find the `throw`, see what it wraps, and whether the cause is captured (look for `handleToolError`, `captureError`, `captureMessage`). Then jump to §B (Sentry) or §D (the downstream it calls).

## §D — Confirm the downstream / backend (Datadog)

Most agent data lookups go through `semanticClient` → the **semantic layer** (in prod a remote GraphQL gateway behind nginx → subgraphs → datastores). `client.js` throws `SemanticClientError` on non-2xx (HTTP, e.g. nginx 504) or on GraphQL `body.errors` (e.g. DB connection timeout).

```
# ai-mastra's own logs (info only — confirms the app ran, not the cause):
search_datadog_logs(query="service:ai-mastra", from=<t-1m>, to=<t+1m>)
# Backend errors in a tight window around the timestamp:
search_datadog_logs(query="status:error -service:ai-mastra", from=<t-10s>, to=<t+15s>)
search_datadog_spans(query="status:error", from=<t-10s>, to=<t+15s>)
```

**Confirm DB health before blaming the DB** — enumerate RDS instances, then read connections + CPU around the incident:
```
get_datadog_metric(queries=["max:aws.rds.database_connections{*} by {dbinstanceidentifier}"],
  response_format=scalar, from=<t-15m>, to=<t+5m>)        # find the instance (e.g. markethub-replica)
get_datadog_metric(queries=[
  "avg:aws.rds.database_connections{dbinstanceidentifier:<inst>}",
  "avg:aws.rds.cpuutilization{dbinstanceidentifier:<inst>}"],
  response_format=timeseries, from=<t-15m>, to=<t+15m>)
```
Idle DB + client "connection timeout" ⇒ the bottleneck is the **caller's pool/connectivity**, not the DB. (Load the `datadog/dbm-postgresql` skill for deeper Postgres signals; `datadog/traces` / `datadog/logs` for query syntax.)

---

## Scope & confirm (don't skip)

- **Scope:** `search_issues … sort=freq` (occurrences, users, firstSeen) or the Braintrust `group by error` count. One user/short window = data/identity; many users/many days = systemic or a deploy (check `release` / change-tracking).
- **Confirm:** never conclude on the error text alone. Pull one independent signal that proves the mechanism (DBM metrics, an APM span, the source line). We once "knew" a failure was a DB overload; the DBM pull showed the DB idle and moved the cause to the client pool.

## Worked example

> "Customer GPT shows: *'The getLoAgentConnections lookup ran but I didn't return a response.'*"

```
extract:  GPT=customer (customer-agent) · tool=getLoAgentConnections   [prose = model narration, not the cause]
route §B: Sentry homebot/surfaces, query "getLoAgentConnectionsTool_failed", sort=freq
read:     top issue .cause → SemanticClientError: "Connection terminated due to connection timeout"
scope:    N groups, firstSeen ~2w, many users → systemic, not one bad profile
confirm §D: DBM markethub-replica → ~34 conns / ~1% CPU during the burst → DB idle
verdict:  client-side pg pool / connectivity in the semantic layer (not the replica) → file ticket
```

## Reference constants

```
Repo                 homebotapp/surfaces  (monorepo; app at apps/ai-mastra/)
Agents               customer-agent · customer-compliance-agent · client-agent · client-compliance-agent
Tools dir            apps/ai-mastra/src/mastra/tools/<kebab>.ts        (label: <camelToolName>Tool_failed)
Error wrapper        apps/ai-mastra/src/mastra/helpers/llm-visible-error.ts  (handleToolError, LLMVisibleError)
Data client          apps/ai-mastra/src/mastra/services/semantic-client.ts → semantic layer (prod: remote/nginx)
Braintrust projects  mastra-production (23c9e29a-680a-4971-b831-393a54a359b3) · mastra-staging · mastra-development
Sentry               org=homebot  project=surfaces  region=https://us.sentry.io  (label query: <tool>Tool_failed)
Datadog              service ai-mastra = info logs only; backend errors + DBM (aws.rds.*) live here
Known datastore      markethub Aurora: primary `markethub`, prod replica `markethub-replica` (LO↔agent connections)
```

## Tools this skill uses

Braintrust (`resolve_object`, `sql_query`, `list_recent_objects`) · Sentry (`search_issues`, `get_sentry_resource`, `search_issue_events`) · Datadog (`search_datadog_logs`, `search_datadog_spans`, `get_datadog_trace`, `search_llmobs_spans`, `get_datadog_metric`, DBM tools) · `gh` CLI (`gh search code`, `gh api`). Load tool schemas via ToolSearch as needed; load Datadog skill guides (`datadog/traces`, `datadog/logs`, `datadog/dbm-postgresql`) before their tools.
