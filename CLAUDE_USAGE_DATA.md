# Where the numbers come from

This app has one hard rule: **never fake Claude limits.** Every value on screen is either read from an
official Anthropic surface or shown as *Unavailable* / *Not provided by Claude* with the reason.
This document records what was researched (August 2026), what is used, and what is deliberately not.

## Summary table

| Value | Official? | Source used | When it is unavailable |
| --- | --- | --- | --- |
| 5‑hour used % | ✅ documented | Claude Code status‑line JSON `rate_limits.five_hour.used_percentage` | No Claude Code, API‑key sign‑in, bridge not installed, no session yet |
| 5‑hour reset time | ✅ documented | `rate_limits.five_hour.resets_at` (epoch seconds) | same |
| Weekly used % / reset | ✅ documented | `rate_limits.seven_day.*` | same |
| 5‑hour / weekly *amounts* (tokens, messages) | ❌ | — | **Not provided by Claude.** Only a percentage and reset time are exposed |
| Model‑specific weekly (Opus/Sonnet) | ⚠️ undocumented | usage endpoint (opt‑in) | endpoint disabled |
| API requests / tokens remaining, limit, replenish time | ✅ documented | `anthropic-ratelimit-*` response headers | no API key |
| API `retry-after` | ✅ documented | header on 429 | not rate limited |
| API 7‑day tokens & cost | ✅ documented | Admin Usage & Cost API | no Admin key, individual (non‑org) account |
| Configured RPM / ITPM / OTPM | ✅ documented | Admin Rate Limits API | no Admin key |
| Claude Code installed / version / path | ✅ | `where`/`which claude`, `claude --version` | not installed |
| Sign‑in type, plan, tier, token expiry | ✅ (local metadata) | `~/.claude/.credentials.json` — metadata fields only | not signed in |
| Active session model / context % | ✅ documented | status‑line JSON `model.display_name`, `context_window.used_percentage` | no recent status‑line update |

## 1. Subscription windows (5‑hour, weekly)

### What Anthropic exposes

- Claude Code's **status line** receives JSON on stdin that includes, for Claude.ai subscribers
  (Pro/Max/Team/Enterprise), a documented `rate_limits` object:
  `five_hour.used_percentage`, `five_hour.resets_at`, `seven_day.used_percentage`, `seven_day.resets_at`.
  It appears only after the first API response of a session, each window may be independently
  absent, and Claude Code drops a window once its `resets_at` passes.
  Docs: https://code.claude.com/docs/en/statusline
- Claude Code's `/usage` command shows the same windows (plus usage‑credit spend) interactively.
  There is **no** documented CLI subcommand or JSON flag that prints them non‑interactively.
- There is **no public API** for subscription limits. The Admin/Usage APIs cover the Console (API)
  organisation, not claude.ai plans.

### What the app does

1. **Status‑line bridge (official data, default).** The app installs a small script as
   `statusLine.command` — once automatically on first launch so limits work out of the box, and
   otherwise from the switch in Settings → Claude Code. The script stores the JSON in
   `%LOCALAPPDATA%\ClaudeUsageMonitor\statusline.json` (atomic write) and forwards it to your
   previous status line, or prints a compact `[model] | ctx 34% | 5h 23% | 7d 41%` line if you had none.
   The app reads the file on every refresh; the file's modification time is the observation time.
2. **Usage endpoint (opt‑in, off by default).** `GET https://api.anthropic.com/api/oauth/usage` with
   `Authorization: Bearer <Claude Code OAuth token>` and `anthropic-beta: oauth-2025-04-20` — the
   endpoint Claude Code's own `/usage` calls. It is **not publicly documented**; the parser is
   tolerant (any object with `utilization` + `resets_at` becomes a window) and the UI labels the source
   *"Claude usage endpoint (undocumented)"*. The token is read from `~/.claude/.credentials.json`
   only for the request and is never stored or refreshed by this app. Calls are throttled to ≥60 s
   and back off on 429. If Anthropic changes the endpoint the section simply becomes *Unavailable*.

Per window the freshest observation wins. Absolute used/remaining **amounts are shown as
"Not provided by Claude"** because no source exposes them.

### Freshness rules

- *Stale* after 10 minutes without a new observation (values dimmed, banner shown).
- When `resets_at` passes: the bar empties, the card says *"Window reset — waiting for new data"*,
  a reset notification fires once, and a refresh is scheduled 3 s later. The app never assumes 0 %.

## 2. API usage (Console / API keys)

### Rate‑limit headers (documented)

https://platform.claude.com/docs/en/api/rate-limits — every Messages response carries:

```
anthropic-ratelimit-requests-{limit,remaining,reset}
anthropic-ratelimit-tokens-{limit,remaining,reset}
anthropic-ratelimit-input-tokens-{limit,remaining,reset}
anthropic-ratelimit-output-tokens-{limit,remaining,reset}
retry-after                     (429 only; absent for the monthly spend‑cap 429)
```

Limits use a **token bucket** replenished continuously, so `reset` is when the bucket is full again
— not a fixed window. The `tokens-*` headers reflect the most restrictive limiter in effect.
Remaining token counts are rounded to the nearest thousand. Rate limits are **per model**, which is
why the probe model is configurable.

There is no free endpoint that returns the Messages‑API headers, so the app sends the smallest
possible request: `max_tokens: 1`, one‑word prompt, default model `claude-haiku-4-5`
(~$0.00001 per probe). Headers are parsed on success **and** on 429. Default cadence is 5 minutes;
"Manual only" is available.

"API used %" = `(limit − remaining) / limit` for the tightest limiter — a rounded, per‑minute
headroom figure, not a billing quota.

### Admin APIs (documented, Admin key required)

- `GET /v1/organizations/usage_report/messages` — token usage buckets (uncached input, cache read,
  cache creation, output). Data lands within ~5 minutes; polling once per minute is allowed.
- `GET /v1/organizations/cost_report` — daily cost in cents (USD).
- `GET /v1/organizations/rate_limits?model=…` — configured limits per model group.

These need an Admin API key (`sk-ant-admin…`) or an `org:admin` OAuth token; workspace keys and
individual (non‑organisation) accounts are rejected — the card then shows the API's error.

## 3. Claude Code detection

- Executable: `where claude` on Windows / `which claude` on macOS, falling back to
  `~/.local/bin/claude[.exe]`.
- Version: `claude --version` (cached for 2 minutes).
- Config directory: `CLAUDE_CONFIG_DIR` if set, else `~/.claude`.
- `settings.json`: only `statusLine.command` is read (to detect the bridge / existing status line).
- `.credentials.json`: only `claudeAiOauth.{subscriptionType, rateLimitTier, expiresAt}` are surfaced.
  The access token is read into memory solely for the opt‑in endpoint call.
- Session status: from the status‑line file — "active" if updated within the last 3 minutes.

## 4. What used it (local activity)

The dashboard's **"What used it · this PC"** card and the bar's **TODAY** figure come from the
transcripts Claude Code writes under `~/.claude/projects/<project>/<session>.jsonl` — the same
device‑local data its own `/usage` breakdown is computed from. Per assistant message the app reads
`message.usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens}`,
`message.model`, `timestamp`, `cwd`, and the session's `ai-title` line (falling back to the first
prompt). Multi‑block messages share a `requestId` and are counted once.

- Scope: last 7 days, this machine, this account. Other devices and claude.ai are **not** included.
- Totals use input + cache write + cache read + output (Claude Code's per‑day token basis).
- These are real token counts, **not** limit percentages — Anthropic does not publish how tokens map
  to the 5‑hour/weekly windows, so the app never converts one into the other.
- "Active" sessions are those whose `~/.claude/sessions/<pid>.json` process is still running.
- Cost control: first scan runs in a background isolate; afterwards only files that grew are read from
  their previous byte offset (≤4 MB per file per refresh).

## 4b. How you use it (Claude Code's own statistics)

The **"How you use it"** card reads `~/.claude/stats-cache.json` — the file behind Claude Code's own
`/usage` → **Overview** tab. Nothing in it is derived by this app:

| Field in the file | What the card shows |
| --- | --- |
| `dailyActivity[] {date, messageCount, sessionCount, toolCallCount}` | the heatmap, Active days, Most active day, both streaks, Sessions, tool calls |
| `dailyModelTokens[] {date, tokensByModel}` | Total tokens per range, Favourite model |
| `modelUsage{model → inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens}` | the Input · Output · Cache read · Cache write bar |
| `totalSessions`, `totalMessages` | the all-time totals (authoritative even if day rows are ever pruned) |
| `longestSession {duration, messageCount, timestamp}` | Longest session |
| `firstSessionDate` | where the heatmap starts, and the Active-days denominator |
| `hourCounts {0..23}` | "When you work" — a histogram Claude Code keeps but never displays |

- Dates in `dailyActivity` / `dailyModelTokens` are **local** calendar days (`YYYY-MM-DD`), so they are
  parsed as local midnight; reading them as UTC would slide every day by the offset.
- `duration` is milliseconds and Claude Code **rounds** to the nearest second — 39,464,529 ms is its
  "10h 57m 45s", not 44s — so `FormatUtils.durationLong` rounds the same way.
- Tokens per day are input + cache write + cache read + output, the same basis as §4. Summed, the day
  rows and `modelUsage` agree to the token.

### Topping up the days Claude Code has not finished counting

The file lags: it carries a `lastComputedDate`, and `/usage` renders it **plus** whatever the
transcripts have gained since — which is why its screen can read several sessions ahead of the file.
This app does the same, from the same transcripts (§4), so the card matches `/usage`:

- Only days **on or after `lastComputedDate`** are counted here; everything before it Claude Code has
  already counted in full and is used exactly as written.
- A day is only replaced by a **fuller** count of itself. Claude Code may have seen transcripts that
  have since been deleted, so a thinner local count is ignored rather than blended in.
- Days older than the 7-day transcript scan are never used: the scan cannot prove them complete.
- Counting rules, verified against Claude Code's own cache to the message on days it had finished:
  **messages** = every entry in the transcript's message chain (`user`, `assistant`, `attachment`,
  `system` — the lines that open with `parentUuid`); the bookkeeping lines beside them
  (`file-history-delta`, `queue-operation`, `frame-link`) carry no `uuid` and are not counted.
  **Tool calls** = `tool_use` blocks in assistant content, counted per line (a message split across
  blocks repeats its `requestId`, but its calls are separate calls). **Sessions** = transcripts with
  at least one message that day.
- `modelUsage`, `longestSession` and `hourCounts` are **not** topped up — they are Claude Code's own
  all-time tallies, and the card labels them as such.

### What the card refuses to do

- The input/output/cache split exists per model for **all time only**. For **7 days** it is computed
  from this PC's transcripts instead, and says how many of the range's tokens that actually covers;
  for **30 days** there is no honest source, so it says so and shows nothing.
- Where the all-time split (as of `lastComputedDate`) is smaller than the topped-up token total, the
  difference is stated rather than spread across the four classes.
- Streaks and active days are recomputed inside the chosen range. The longest session is an all-time
  fact and is tagged "all time" when it falls outside the range.
- A day that has not started yet does not break a streak: the current streak counts back from today,
  or from yesterday when today is still silent.
- No stats cache → the card says so and points at `/usage`; an unrecognised `version` is flagged and
  whatever parses is still read.

## 5. Other devices on the same account

Claude exposes **no per-device information** anywhere: the status line and the transcripts are per
machine, and the usage endpoint returns one combined number for the whole account. So each machine
running this monitor publishes **its own real local activity** as `<hostname>.json` into a shared
folder (OneDrive by default, or any synced folder you choose) and reads the other devices' files back.

Per device the file carries: how many Claude Code sessions are open, today's and the week's token
totals, tokens per model, and one entry per session — title, project, the model of its newest
response, total tokens, output tokens, response count, last activity, and whether it is still open.

- Published every **15 s**, and immediately whenever the picture actually changes: a session opens or
  closes, its token total moves, or it switches model. **Every open session is always published**;
  finished ones are capped at 8.
- Read back on the same 15 s tick, so the panel updates without waiting for the main refresh interval.
- A device counts as online for **120 s** after its last write. How fast a change actually arrives is
  bounded by your shared folder's own sync lag, which no application can beat.
- A device that has never written a file is simply **not listed** — nothing is inferred or invented,
  and no Claude API is involved in any of this.

## 6. Explicitly not done

- No scraping of claude.ai or the Console.
- No token refresh or OAuth flow of our own — if the Claude Code token is expired the UI says so and
  asks you to open Claude Code.
- No estimation from local transcripts/token counts (Claude Code's own docs call those approximate
  and device‑local).
- No modification of any Claude file except the `statusLine` key and the `SessionStart` hook, each
  written only through the serialized writer, always after a timestamped backup in
  `%LOCALAPPDATA%\ClaudeUsageMonitor\backups`, and never to a file that fails to parse.

## References

- Rate limits & headers: https://platform.claude.com/docs/en/api/rate-limits
- Rate Limits API: https://platform.claude.com/docs/en/manage-claude/rate-limits-api
- Usage & Cost API: https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- Claude Code status line: https://code.claude.com/docs/en/statusline
- Claude Code `/usage` and costs: https://code.claude.com/docs/en/costs
