---
name: web-security-audit
description: >
  Read-only security audit for any web app (15 checks, OWASP basics for vibecoded
  projects). Claude reads the code with judgment and verifies: no DB/ORM imports in
  client code, auth on API routes, server-side gating of premium features, input
  validation, rate limiting on expensive endpoints (AI / payments / email), no
  hardcoded secrets, no real secrets in client-exposed env vars, no PII in logs,
  safe CORS, no SQL injection, no XSS, plus dependency audit / typecheck / lint.
  Framework-agnostic: Next.js, Nuxt, SvelteKit, Astro, Remix, Angular, Vite,
  Express, Fastify, Hono, NestJS and more (npm / pnpm / yarn / bun). Works on any
  project and uses context to avoid false positives (public-by-design keys, empty
  templates). An optional bash script (run.ps1 on Windows) can speed up the scan,
  but the audit never requires running untrusted code.

  Trigger when the user mentions: security audit, audit sécurité, OWASP, vulnerability
  scan, scan vulnérabilités, leaked secrets, secret leak, security check, security
  review, pentest, vérification avant déploiement, pre-deploy security check,
  RGPD / GDPR, "is my app secure", sécurité du code.
metadata:
  last_updated: 2026-06-20
  source: https://github.com/buffalodebile/vibecoding-security-audit
  author: Burak Eregar (Mr Black AI / @burakeregar)
includes:
  - security-audit.sh
  - run.ps1
  - README.md
---

# Web Security Audit

A read-only security pass for any web project — built so it works the same on a
Next.js app, a SvelteKit site, an Express API, or a completely different stack,
and so a non-security person can trust the result.

## How this skill works (read this first)

**You (Claude) are the auditor.** Do the 15 checks below by reading the code and
applying judgment. Do **not** rely on a tool's raw regex output as the verdict —
that is exactly what produces false positives (a regex sees `KEY` in a variable
name and panics, even when the key is public by design and the value is empty).
You read the code, understand the context, and decide.

The bundled `security-audit.sh` (`run.ps1` on Windows) is an **optional
accelerator** for large codebases. It is never required. Treat its output as a
list of *candidates to confirm*, not findings. If the harness blocks running it,
or you can't trust the project enough to execute its scripts, just do the checks
by hand with Grep/Read — that path always works.

### Ground rules

1. **Read-only by default.** The audit never edits files, installs packages,
   runs `audit fix`, or modifies dependencies. Reporting is the deliverable.
2. **Never execute untrusted project code.** `npm audit` is safe (no code runs).
   `tsc` / `eslint` / build steps execute the project's own config and plugins —
   only run them on a project the user already trusts, and never let a tool
   auto-install a missing binary (no `npx <pkg>` that hits the network).
3. **Confirm before you flag.** Every candidate must be opened and read. A match
   in a test fixture, an `.env.example` template, a comment, or a public-by-design
   key is **not** a finding.
4. **Adapt to the repo.** Monorepo? Run the checks per app (`apps/web`,
   `packages/*`) — auto-detection that only looks at the repo root will miss
   nested apps. Non-JS project (Python, Go…)? Say so and scope to what applies.

## The 15 checks — what to look for and how to read the result

| # | Check | Severity |
|---|-------|----------|
| 1 | No database/ORM imports in client code | Error |
| 2 | Auth on every API route handler | Warning |
| 3 | Premium/role gating enforced server-side | Warning |
| 4 | No **real** secrets in client-exposed env vars | Error |
| 5 | Price/score/business math is server-side | Warning |
| 6 | Input validation on API routes | Warning |
| 7 | Rate limiting on expensive endpoints | Warning |
| 8 | No secrets/PII in logs | Error |
| 9 | Dependency vulnerabilities (`audit`) | Error/Warn |
| 10 | TypeScript typecheck (trusted projects only) | Error |
| 11 | Lint (trusted projects only) | Warning |
| 12 | No hardcoded secrets | Error |
| 13 | No wildcard/permissive CORS | Warning |
| 14 | No SQL injection (raw queries + interpolation) | Warning |
| 15 | No XSS sinks (`dangerouslySetInnerHTML`, `v-html`, `innerHTML`, `{@html}`) | Warning |

For each one:

1. **Find** — grep the patterns across source files (skip `node_modules`, build
   output: `.next` `.nuxt` `.svelte-kit` `dist` `build` `.output` `coverage`).
2. **Open & read** — confirm it's real in context.
3. **Decide** — real issue, accepted-with-reason, or false positive.

Details where reading-with-judgment matters most:

- **#1 client DB access** — flag an ORM/DB client import (`@prisma/client`,
  `drizzle-orm`, `mongoose`, `pg`, `mysql2`, `@supabase/supabase-js` used as a
  *service-role* client, …) reachable from browser code: a React `"use client"`
  file, a `.vue`/`.svelte` component, or anything bundled to the client. Server
  components, route handlers, server actions, and `*.server.ts` are fine.
- **#4 secrets in public env vars** — this is the #1 source of false positives.
  See the allowlist below. Only flag when a **real, non-empty secret value** is
  assigned to a client-exposed variable. Empty templates and public-by-design
  keys are **PASS**.
- **#7 rate limiting** — only expensive routes need it: AI generation, payments,
  email/SMS, anything that costs money or compute per call. A plain CRUD GET does
  not need a rate limiter to pass.
- **#9 dependency audit** — run `npm audit` / `pnpm audit` / `yarn audit` (safe,
  no project code executes). Report high/critical as errors, low/moderate as
  warnings. Do **not** run `audit fix --force`.
- **#10/#11 typecheck & lint** — these execute project config. Run only on a
  trusted project, using the **locally installed** binary
  (`node_modules/.bin/tsc`, `node_modules/.bin/eslint`). If not installed, skip
  and say so — never auto-install.

## Public-by-design — do NOT flag these as leaks

These are **meant** to live in the browser. Finding them in client code or in a
`NEXT_PUBLIC_*` / `VITE_*` / `PUBLIC_*` variable is expected and correct. Verify
the intended protection exists, but do not report them as secret leaks:

- **Supabase anon key** (`NEXT_PUBLIC_SUPABASE_ANON_KEY`) — public; protected by
  Row Level Security policies. Confirm RLS is on; the key itself is fine.
- **Stripe publishable key** (`pk_live_…`, `pk_test_…`,
  `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`) — designed to be exposed. Only the
  **secret** key (`sk_live_…` / `sk_test_…`) is a real leak.
- **Firebase web config** (`apiKey`, `authDomain`, `projectId`, …) — public by
  design; protected by Firebase Security Rules + allowed-domains.
- **Clerk publishable key** (`pk_…`, `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`) — public.
- **Analytics / monitoring tokens** — PostHog (`NEXT_PUBLIC_POSTHOG_KEY`), Sentry
  DSN (`NEXT_PUBLIC_SENTRY_DSN`), GA/GTM IDs, Amplitude, Mixpanel browser tokens —
  all client-side by design.
- **Map / search browser tokens** — Mapbox `pk.…`, Google Maps browser key,
  Algolia **search-only** key — public, ideally restricted by domain/referrer.
- **Empty or placeholder values** — `.env.example`, `.env.sample`, `.env.template`
  with empty values or placeholders (`your-key-here`, `xxx`, `changeme`,
  `sk_test_xxx`, `<...>`) are templates, **not** secrets. Only a real value
  committed to a real `.env` is a leak.

When you skip one of these, say *why* in the report (e.g. "anon key is public,
RLS confirmed in `supabase/`") so the user learns the reasoning, not just the verdict.

## Always treat as a real secret (Error)

A literal value matching any of these committed to the repo is a genuine leak —
rotate it immediately:

- OpenAI / Anthropic `sk-…` ; Stripe **secret** `sk_live_…` / `sk_test_…`
- AWS `AKIA…` access keys ; Google server key `AIza…` ; Google OAuth `ya29.…`
- GitHub `ghp_…` / `gho_…` / `github_pat_…` ; GitLab `glpat-…`
- Slack `xoxb-…` / `xoxp-…` ; SendGrid `SG.…`
- JWTs hardcoded in source ; private keys (`-----BEGIN … PRIVATE KEY-----`)
- DB connection strings **with credentials**
  (`postgres://user:pass@…`, `mongodb+srv://user:pass@…`, `mysql://…`, `redis://…`)

Also confirm `.env`, `.env.*` (except `.env.example`) are git-ignored.

## Optional: the bash accelerator

For big repos you may run the bundled script to generate candidates faster.

```bash
# macOS / Linux / CI — from the project root
bash <skill-dir>/security-audit.sh          # local run, warnings don't fail
bash <skill-dir>/security-audit.sh --ci      # exit 1 on any error (for CI)
```

```powershell
# Windows (delegates to Git Bash automatically)
& "<skill-dir>\run.ps1"
& "<skill-dir>\run.ps1" --ci
```

`<skill-dir>` is wherever this skill is installed (e.g.
`~/.claude/skills/web-security-audit`).

The script is read-only **except** `--fix`. Do **not** use `--fix` by default; it
modifies files (`eslint --fix`, non-forced `npm audit fix`). Only run it on
explicit user request, and review the `git diff` afterward. Whatever the script
prints, still confirm each candidate yourself per the allowlist above.

## Report template

After the pass, give the user a single table plus a plain-language verdict:

```
| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Client DB access            | PASS / FAIL | file:line or "none" |
| 2 | API auth                    | …           | … |
…
| 15| XSS sinks                   | …           | … |
```

Then, per real finding:

| ID | Severity | File:line | What | Fix |
|----|----------|-----------|------|-----|

Finish with a one-line verdict in plain words ("No real security holes on the
static checks. One thing to double-check: …"), and for any item you skipped as a
false positive, one line on **why** it's safe. End with what you did *not* run
(e.g. "didn't execute typecheck/lint — say the word and I'll run them on this
trusted repo").

## The 9 principles behind the checks

1. Don't talk to the database directly from the client.
2. Gatekeep every action (auth on every endpoint).
3. Don't hide, withhold (enforce premium server-side).
4. Keep secrets off the browser (public-by-design keys excepted).
5. Don't do math on the phone (price/score server-side).
6. Sanitize everything (validate inputs with a schema).
7. Rate limit expensive endpoints.
8. Don't log sensitive stuff.
9. Audit with a second pair of eyes (a different model catches different blind spots).

## Source

Upstream: https://github.com/buffalodebile/vibecoding-security-audit
Author: Burak Eregar (Mr Black AI). MIT licensed.
