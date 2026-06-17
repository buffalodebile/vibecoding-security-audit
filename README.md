# Vibecoding Web Security Audit

Automated security checks for any **vibecoded** web project. One script, 15 checks, zero config.

When you build fast with an AI assistant — "vibecoding" — it's easy to ship code that works but quietly leaks secrets, skips auth, or trusts the client. This tool is the safety net: it catches the security mistakes that AI-generated code most often makes, so you can keep moving fast without shipping holes.

Works with Next.js, React, Vue, Nuxt, SvelteKit, Astro, Remix, Angular, Express, Fastify, and more.

Based on [Burak Eregar's 9 security principles](https://x.com/burakeregar) for AI-assisted (vibecoding) development.

## What it checks

| # | Check | Type |
|---|-------|------|
| 1 | No database imports in client/browser code (Prisma, Supabase, Drizzle, Mongoose, etc.) | Error |
| 2 | Authentication on all API route handlers | Warning |
| 3 | Premium features verified server-side, not just hidden in UI | Warning |
| 4 | No secrets in client-exposed env variables (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, etc.) | Error |
| 5 | Price/score calculations are server-side only | Warning |
| 6 | Input validation on API routes (Zod, Yup, Joi, etc.) | Warning |
| 7 | Rate limiting on expensive endpoints (AI, payments, email) | Warning |
| 8 | No sensitive data (passwords, tokens) in logs | Error |
| 9 | Dependency vulnerabilities (`npm/pnpm/yarn audit`) | Error/Warning |
| 10 | TypeScript type checking (`tsc --noEmit`) | Error |
| 11 | ESLint checks | Warning |
| 12 | Hardcoded secrets (OpenAI, Stripe, AWS, GitHub, Google, Slack, SendGrid, JWTs, DB connection strings) | Error |
| 13 | CORS misconfiguration (wildcard origins) | Warning |
| 14 | SQL injection risk (raw queries with string interpolation) | Warning |
| 15 | XSS vectors (`dangerouslySetInnerHTML`, `v-html`, `innerHTML`, `{@html}`) | Warning |

## Auto-detection

The script automatically detects:
- **Source directory**: `src/`, `app/`, `lib/`, `pages/`, or current directory
- **Framework**: Next.js, Nuxt, SvelteKit, Astro, Angular, Vite
- **Package manager**: npm, pnpm, yarn, bun
- **Client-side patterns**: `"use client"` (React), `.vue` (Vue), `.svelte` (Svelte)

## Quick start

### Option 1: Copy the script (simplest)

```bash
# Download the script into your project
curl -o security-audit.sh https://raw.githubusercontent.com/buffalodebile/vibecoding-security-audit/main/security-audit.sh
chmod +x security-audit.sh

# Run it
./security-audit.sh
```

### Option 2: Clone and copy

```bash
git clone https://github.com/buffalodebile/vibecoding-security-audit.git
cp vibecoding-security-audit/security-audit.sh your-project/
cp -r vibecoding-security-audit/.github your-project/
```

## Usage

```bash
# Local run (warnings don't fail)
./security-audit.sh

# CI mode (exits with code 1 on any error)
./security-audit.sh --ci

# Auto-fix mode (runs audit fix + eslint --fix)
./security-audit.sh --fix
```

## GitHub Action: run on every push

Copy `.github/workflows/security-audit.yml` into your project, or create the file manually:

```yaml
# .github/workflows/security-audit.yml
name: Security Audit

on:
  push:
    branches: ["*"]
  pull_request:
    branches: [main, master]

permissions:
  contents: read

jobs:
  security-audit:
    name: Vibecoding Web Security Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Detect Node project
        id: node
        run: |
          if [ -f package.json ]; then
            echo "present=true" >> "$GITHUB_OUTPUT"
          else
            echo "present=false" >> "$GITHUB_OUTPUT"
          fi
      - uses: actions/setup-node@v5
        if: steps.node.outputs.present == 'true'
        with:
          node-version: "22"
      - name: Install dependencies
        if: steps.node.outputs.present == 'true'
        run: |
          if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
            npm ci
          else
            npm install
          fi
      - name: Run security audit
        run: |
          chmod +x ./security-audit.sh
          ./security-audit.sh --ci
```

That's it. Every push and every PR will now trigger the full security audit. If any **error-level** check fails, the workflow fails and blocks the merge. The Node setup steps are skipped automatically when the repo has no `package.json` (so the audit still runs on plain/static projects).

### Using pnpm or yarn

```yaml
      # pnpm
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - run: pnpm install --frozen-lockfile

      # yarn
      - run: yarn install --frozen-lockfile
```

### Customizing the trigger

```yaml
# Only on PRs to main
on:
  pull_request:
    branches: [main]

# Only when source code changes
on:
  push:
    paths: ["src/**", "app/**", "lib/**", "pages/**"]

# Scheduled (daily at midnight)
on:
  schedule:
    - cron: "0 0 * * *"
```

## The 9 security principles

1. **Don't talk to the database directly** - Client/browser code must never import an ORM or database client. Always go through API routes or server actions.

2. **Gatekeep every action** - Every API endpoint must verify the user's identity before doing anything. No anonymous access to sensitive operations.

3. **Don't hide, withhold** - Premium features must be enforced server-side. Hiding a button in the UI is not security, it's decoration.

4. **Keep secrets off the browser** - Never expose API keys, tokens, or credentials in client-side environment variables (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, etc.). These are visible to anyone who opens DevTools.

5. **Don't do math on the phone** - Price calculations, scoring algorithms, and business logic must run server-side. Client-side values can be tampered with.

6. **Sanitize everything** - Validate all user inputs with a schema library (Zod, Yup, Joi). Never trust request bodies directly.

7. **Rate limit expensive endpoints** - AI generation, payment processing, and email sending must have rate limits. One bad actor can drain your budget.

8. **Don't log sensitive stuff** - Never log passwords, tokens, or API keys. Logs end up in Vercel, CloudWatch, and Datadog where more people can see them.

9. **Audit with a rival AI** - If Claude wrote your code, ask Gemini to audit it. Different models catch different blind spots.

## Works with

- **React**: Next.js, Remix, Create React App, Vite
- **Vue**: Nuxt, Vite
- **Svelte**: SvelteKit
- **Other**: Astro, Angular, Express, Fastify, Hono, NestJS
- **Package managers**: npm, pnpm, yarn, bun
- Any project with JavaScript/TypeScript source code

## License

MIT
