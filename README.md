# Next.js Security Audit

Automated security checks for Next.js projects. One script, 12 checks, zero config.

Based on [Burak Eregar's 9 security principles](https://x.com/burakeregar) for AI-assisted development.

## What it checks

| # | Check | Type |
|---|-------|------|
| 1 | No database imports in `"use client"` files (Prisma, Supabase, Drizzle, etc.) | Error |
| 2 | Authentication on all API route handlers | Warning |
| 3 | Premium features verified server-side, not just hidden in UI | Warning |
| 4 | No secrets in `NEXT_PUBLIC_*` environment variables | Error |
| 5 | Price/score calculations are server-side only | Warning |
| 6 | Input validation on API routes (Zod, Yup, Joi, etc.) | Warning |
| 7 | Rate limiting on expensive endpoints (AI, payments, email) | Warning |
| 8 | No sensitive data (passwords, tokens) in `console.log` | Error |
| 9 | `npm audit` for dependency vulnerabilities | Error/Warning |
| 10 | TypeScript type checking (`tsc --noEmit`) | Error |
| 11 | ESLint checks | Warning |
| 12 | Hardcoded secret patterns (OpenAI, Stripe, AWS, GitHub, Slack, SendGrid) | Error |

## Quick start

### Option 1: Copy the script (simplest)

```bash
# Download the script into your project
curl -o security-audit.sh https://raw.githubusercontent.com/buffalodebile/nextjs-security-audit/main/security-audit.sh
chmod +x security-audit.sh

# Run it
./security-audit.sh
```

### Option 2: Clone and copy

```bash
git clone https://github.com/buffalodebile/nextjs-security-audit.git
cp nextjs-security-audit/security-audit.sh your-project/
cp -r nextjs-security-audit/.github your-project/
```

## Usage

```bash
# Local run (warnings don't fail)
./security-audit.sh

# CI mode (exits with code 1 on any error)
./security-audit.sh --ci

# Auto-fix mode (runs npm audit fix + eslint --fix)
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
    name: Next.js Security Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
      - run: npm ci
      - name: Run security audit
        run: |
          chmod +x ./security-audit.sh
          ./security-audit.sh --ci
```

That's it. Every push and every PR will now trigger the full security audit. If any **error-level** check fails, the workflow fails and blocks the merge.

### Customizing the trigger

```yaml
# Only on PRs to main
on:
  pull_request:
    branches: [main]

# Only when source code changes
on:
  push:
    paths: ["src/**", "app/**"]

# Scheduled (daily at midnight)
on:
  schedule:
    - cron: "0 0 * * *"
```

## The 9 security principles

1. **Don't talk to the database directly** - Client components (`"use client"`) must never import Prisma, Supabase, or any ORM. Always go through API routes or server actions.

2. **Gatekeep every action** - Every API endpoint must verify the user's identity before doing anything. No anonymous access to sensitive operations.

3. **Don't hide, withhold** - Premium features must be enforced server-side. Hiding a button in the UI is not security, it's decoration.

4. **Keep secrets off the browser** - Never use `NEXT_PUBLIC_*` for API keys, tokens, or credentials. These are visible to anyone who opens DevTools.

5. **Don't do math on the phone** - Price calculations, scoring algorithms, and business logic must run server-side. Client-side values can be tampered with.

6. **Sanitize everything** - Validate all user inputs with a schema library (Zod, Yup, Joi). Never trust `req.body` directly.

7. **Rate limit expensive endpoints** - AI generation, payment processing, and email sending must have rate limits. One bad actor can drain your budget.

8. **Don't log sensitive stuff** - Never `console.log` passwords, tokens, or API keys. Logs end up in Vercel, CloudWatch, and Datadog where more people can see them.

9. **Audit with a rival AI** - If Claude wrote your code, ask Gemini to audit it. Different models catch different blind spots.

## Works with

- Next.js 13+ (App Router)
- Next.js 12 (Pages Router)
- Any project with a `src/` or `app/` directory

## License

MIT
