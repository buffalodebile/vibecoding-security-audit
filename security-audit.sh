#!/usr/bin/env bash
# =============================================================================
# Vibecoding Web Security Audit Script
# =============================================================================
# Automated security checks for any vibecoded web project (Next.js, React, Vue, Nuxt,
# SvelteKit, Express, Fastify, Astro, Remix, Angular, and more).
#
# Based on Burak Eregar's 9 security principles for AI-assisted development.
#
# This script is READ-ONLY except for --fix. It never installs packages, never
# fetches code over the network, and never runs destructive dependency changes.
# Its output is a list of CANDIDATES to confirm, not final findings: some matches
# are expected false positives (e.g. public-by-design keys). Review each one.
#
# Usage: ./security-audit.sh [--ci] [--fix]
#   --ci   Exit with non-zero code on any failure (for CI/CD)
#   --fix  Apply safe, reversible fixes (eslint --fix, non-forced npm audit fix).
#          Modifies files in place: review the git diff afterward. Opt-in only.
# =============================================================================

set -euo pipefail

# Colors (disabled in CI for clean logs)
if [ -t 1 ] && [ "${CI:-}" != "true" ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

ERRORS=0
WARNINGS=0
CI_MODE=false
FIX_MODE=false

for arg in "$@"; do
  case $arg in
    --ci) CI_MODE=true ;;
    --fix) FIX_MODE=true ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
pass()   { echo -e "  ${GREEN}PASS${NC} $1"; }
fail()   { echo -e "  ${RED}FAIL${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn()   { echo -e "  ${YELLOW}WARN${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

# Run a project-local CLI without ever downloading it. `npx --no-install` resolves
# only from the project's own node_modules and fails fast if absent, so this can
# never fetch and execute a remote package (unlike a bare `npx <pkg>`).
has_local_bin() {
  [ -f "node_modules/.bin/$1" ] || [ -f "node_modules/.bin/$1.cmd" ] \
    || npx --no-install "$1" --version >/dev/null 2>&1
}
run_local_bin() {
  local bin="$1"; shift
  npx --no-install "$bin" "$@"
}

# -----------------------------------------------------------------------------
# Detect source directory (src/, app/, lib/, pages/, or current dir)
# -----------------------------------------------------------------------------
SRC_DIR=""
for dir in src app lib pages; do
  if [ -d "$dir" ]; then
    SRC_DIR="$dir"
    break
  fi
done
if [ -z "$SRC_DIR" ]; then
  SRC_DIR="."
fi

# Detect framework
FRAMEWORK="unknown"
if [ -f "next.config.js" ] || [ -f "next.config.ts" ] || [ -f "next.config.mjs" ]; then
  FRAMEWORK="next"
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
elif [ -f "svelte.config.js" ] || [ -f "svelte.config.ts" ]; then
  FRAMEWORK="sveltekit"
elif [ -f "astro.config.mjs" ] || [ -f "astro.config.ts" ]; then
  FRAMEWORK="astro"
elif [ -f "angular.json" ]; then
  FRAMEWORK="angular"
elif [ -f "vue.config.js" ] || [ -f "vite.config.ts" ] || [ -f "vite.config.js" ]; then
  FRAMEWORK="vite"
fi

# Detect package manager
PKG_MANAGER="npm"
if [ -f "pnpm-lock.yaml" ]; then
  PKG_MANAGER="pnpm"
elif [ -f "yarn.lock" ]; then
  PKG_MANAGER="yarn"
elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
  PKG_MANAGER="bun"
fi

echo -e "${BLUE}Vibecoding Web Security Audit${NC}"
echo "Source directory: $SRC_DIR"
echo "Framework: $FRAMEWORK | Package manager: $PKG_MANAGER"
echo "Mode: $([ "$CI_MODE" = true ] && echo 'CI' || echo 'local')$([ "$FIX_MODE" = true ] && echo ' + auto-fix' || echo '')"

# File extensions to scan
FILE_EXTS="--include=*.ts --include=*.tsx --include=*.js --include=*.jsx --include=*.vue --include=*.svelte --include=*.astro"

# =============================================================================
# 1. Database imports in client/browser code
# =============================================================================
header "Principle 1: No database access in client code"

DB_PATTERN="from ['\"](@prisma|prisma|@supabase/supabase-js|drizzle-orm|mongoose|typeorm|knex|sequelize|@planetscale|better-sqlite3|pg |mysql2)"

# Check React/Next.js "use client" files
CLIENT_DB_IMPORTS=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "$DB_PATTERN" "$file" 2>/dev/null; then
    echo "$file"
  fi
done || true)

# Check Vue <script> with no server-only marker
VUE_DB_IMPORTS=$(grep -rlE "$DB_PATTERN" --include="*.vue" "$SRC_DIR" 2>/dev/null | while read -r file; do
  if ! grep -qE "(server|defineServerComponent|<script.*server)" "$file" 2>/dev/null; then
    echo "$file"
  fi
done || true)

# Check Svelte non-server files
SVELTE_DB_IMPORTS=$(grep -rlE "$DB_PATTERN" --include="*.svelte" "$SRC_DIR" 2>/dev/null || true)

ALL_CLIENT_DB="$CLIENT_DB_IMPORTS$VUE_DB_IMPORTS$SVELTE_DB_IMPORTS"

if [ -z "$ALL_CLIENT_DB" ]; then
  pass "No database imports found in client/browser files"
else
  fail "Database imports found in client files:"
  echo "$ALL_CLIENT_DB" | while read -r file; do
    [ -n "$file" ] && echo "    - $file"
  done
fi

# =============================================================================
# 2. API endpoint authentication
# =============================================================================
header "Principle 2: Authentication on API endpoints"

AUTH_PATTERNS="(getServerSession|getSession|auth\(|getToken|verifyToken|authenticate|requireAuth|withAuth|getUser|currentUser|clerkClient|getAuth|passport\.|jwt\.verify|lucia|authMiddleware|protect\(|requireLogin|isAuthenticated|ensureAuth)"

# Next.js / Remix route handlers
API_ROUTES=$(find "$SRC_DIR" -path "*/api/*" \( -name "route.ts" -o -name "route.js" -o -name "*.server.ts" -o -name "*.server.js" \) 2>/dev/null || true)

# Express / Fastify style routes
EXPRESS_ROUTES=$(grep -rlE "\.(get|post|put|patch|delete)\(" --include="*.ts" --include="*.js" "$SRC_DIR" 2>/dev/null | grep -iE "(route|controller|handler|endpoint|api)" || true)

ALL_ROUTES=$(echo -e "$API_ROUTES\n$EXPRESS_ROUTES" | sort -u | grep -v "^$" || true)

if [ -n "$ALL_ROUTES" ]; then
  UNPROTECTED=0
  while IFS= read -r route; do
    [ -z "$route" ] && continue
    if ! grep -qE "$AUTH_PATTERNS" "$route" 2>/dev/null; then
      warn "No auth check detected: $route"
      UNPROTECTED=$((UNPROTECTED + 1))
    fi
  done <<< "$ALL_ROUTES"
  if [ "$UNPROTECTED" -eq 0 ]; then
    pass "All API routes appear to have authentication checks"
  fi
else
  pass "No API routes found (or using a different routing pattern)"
fi

# =============================================================================
# 3. Server-side premium feature verification
# =============================================================================
header "Principle 3: Premium features verified server-side"

PREMIUM_PATTERN="(isPremium|isSubscribed|isPro|planType|subscription|tier|billingStatus)"

# React/Next.js "use client" files
PREMIUM_CLIENT=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "$PREMIUM_PATTERN" "$file" 2>/dev/null; then
    if ! grep -qE "(fetch|api/|server|action|trpc|query|useSWR|useQuery)" "$file" 2>/dev/null; then
      echo "$file"
    fi
  fi
done || true)

if [ -z "$PREMIUM_CLIENT" ]; then
  pass "No client-only premium gating detected"
else
  warn "Possible client-only premium gating (verify server-side check exists):"
  echo "$PREMIUM_CLIENT" | while read -r file; do
    echo "    - $file"
  done
fi

# =============================================================================
# 4. Secrets in client-side environment variables
# =============================================================================
header "Principle 4: No secrets in client-exposed env variables"

# Framework-specific public env prefixes:
# - Next.js: NEXT_PUBLIC_
# - Vite/SvelteKit/Astro: VITE_
# - Nuxt: NUXT_PUBLIC_ (or runtime config)
# - Angular: (uses environment.ts files)
# - Create React App: REACT_APP_
PUBLIC_ENV_PATTERN="(NEXT_PUBLIC_|VITE_|NUXT_PUBLIC_|REACT_APP_|EXPO_PUBLIC_).*(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE)"

# Keys that are PUBLIC BY DESIGN and belong in the browser: matching these is
# expected and is NOT a leak (Supabase anon key + RLS, Stripe/Clerk publishable
# keys, Firebase web config, analytics & map tokens, captcha site keys, ...).
PUBLIC_BY_DESIGN="(SUPABASE_ANON|ANON_KEY|STRIPE_PUBLISHABLE|PUBLISHABLE_KEY|CLERK_PUBLISHABLE|FIREBASE|POSTHOG|SENTRY_DSN|MAPBOX|MAPS_API|GA_MEASUREMENT|GTM_|GOOGLE_ANALYTICS|ALGOLIA_SEARCH|AMPLITUDE|MIXPANEL|TURNSTILE_SITE|RECAPTCHA_SITE|HCAPTCHA_SITE|VAPID_PUBLIC)"

# Obvious placeholder values found in templates are not real secrets.
PLACEHOLDER_VALUE="(your[-_]|xxxxx|changeme|placeholder|dummy|example\.com|sk_test_xxx|<[a-z_]+>|\.\.\.)"

# Only a REAL, non-empty value assigned to a client-exposed *secret-named*
# variable is a finding. We therefore drop: build output, template files
# (.env.example/.sample/.template), public-by-design keys, empty assignments
# (e.g. `NEXT_PUBLIC_SUPABASE_ANON_KEY=`), and placeholder values.
EXPOSED_SECRETS=$(grep -rnE "$PUBLIC_ENV_PATTERN" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.vue" --include="*.svelte" --include="*.env*" . 2>/dev/null \
  | grep -vE 'node_modules|\.next|\.nuxt|\.svelte-kit|dist|build|\.output' \
  | grep -vE '\.env\.(example|sample|template|dist)' \
  | grep -viE "$PUBLIC_BY_DESIGN" \
  | grep -vE '(=|:)[[:space:]]*("")?[[:space:]]*$' \
  | grep -viE "$PLACEHOLDER_VALUE" \
  || true)

if [ -z "$EXPOSED_SECRETS" ]; then
  pass "No real secrets detected in client-exposed env variables"
else
  fail "Potential secrets exposed via public env variables (confirm each; public-by-design keys are already excluded):"
  echo "$EXPOSED_SECRETS" | head -20 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 5. Client-side sensitive calculations
# =============================================================================
header "Principle 5: Sensitive calculations are server-side"

CALC_PATTERN="(calculatePrice|calculateScore|computeDiscount|finalPrice|totalAmount|calculateTotal|computePrice|billingAmount|chargeAmount)"

# React "use client" files
PRICE_CLIENT=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "$CALC_PATTERN" "$file" 2>/dev/null; then
    echo "$file"
  fi
done || true)

# Vue/Svelte client components
PRICE_SFC=$(grep -rlE "$CALC_PATTERN" --include="*.vue" --include="*.svelte" "$SRC_DIR" 2>/dev/null || true)

ALL_PRICE="$PRICE_CLIENT$PRICE_SFC"

if [ -z "$ALL_PRICE" ]; then
  pass "No price/score calculations in client components"
else
  warn "Sensitive calculations found in client files (should be server-side):"
  echo "$ALL_PRICE" | while read -r file; do
    [ -n "$file" ] && echo "    - $file"
  done
fi

# =============================================================================
# 6. Input validation
# =============================================================================
header "Principle 6: Input sanitization"

VALIDATION_PATTERN="(zod|yup|joi|validate|sanitize|ajv|superstruct|valibot|z\.object|z\.string|class-validator|express-validator|typebox)"

if [ -n "$ALL_ROUTES" ]; then
  UNVALIDATED=0
  while IFS= read -r route; do
    [ -z "$route" ] && continue
    if ! grep -qE "$VALIDATION_PATTERN" "$route" 2>/dev/null; then
      warn "No input validation library detected: $route"
      UNVALIDATED=$((UNVALIDATED + 1))
    fi
  done <<< "$ALL_ROUTES"
  if [ "$UNVALIDATED" -eq 0 ]; then
    pass "All API routes appear to use input validation"
  fi
else
    pass "No API routes to check"
fi

# =============================================================================
# 7. Rate limiting on expensive endpoints
# =============================================================================
header "Principle 7: Rate limiting on expensive endpoints"

EXPENSIVE_PATTERNS="(openai|anthropic|stripe|sendgrid|resend|twilio|aws-sdk|@google-ai|@azure|generate|ai\/|langchain|cohere|replicate|huggingface)"
RATE_LIMIT_PATTERNS="(rateLimit|rateLimiter|upstash|@upstash\/ratelimit|limiter|throttle|express-rate-limit|bottleneck|p-limit|p-throttle)"

EXPENSIVE_ROUTES=""
if [ -n "$ALL_ROUTES" ]; then
  while IFS= read -r route; do
    [ -z "$route" ] && continue
    if grep -qE "$EXPENSIVE_PATTERNS" "$route" 2>/dev/null; then
      if ! grep -qE "$RATE_LIMIT_PATTERNS" "$route" 2>/dev/null; then
        EXPENSIVE_ROUTES="$EXPENSIVE_ROUTES$route"$'\n'
      fi
    fi
  done <<< "$ALL_ROUTES"
fi

if [ -z "$EXPENSIVE_ROUTES" ]; then
  pass "Expensive endpoints appear to have rate limiting"
else
  warn "Expensive endpoints without rate limiting:"
  echo "$EXPENSIVE_ROUTES" | while read -r file; do
    [ -n "$file" ] && echo "    - $file"
  done
fi

# =============================================================================
# 8. Sensitive data in logs
# =============================================================================
header "Principle 8: No sensitive data in logs"

SENSITIVE_LOGS=$(grep -rnE "console\.(log|info|debug|warn)\(.*\b(password|token|secret|apiKey|api_key|credential|authorization|bearer|private_key|session_id)\b" $FILE_EXTS "$SRC_DIR" 2>/dev/null || true)

# Also check for common logging libraries
LOGGER_LEAKS=$(grep -rnE "(logger|log)\.(info|debug|warn|error)\(.*\b(password|token|secret|apiKey|api_key|credential|bearer)\b" $FILE_EXTS "$SRC_DIR" 2>/dev/null || true)

ALL_LOG_ISSUES="$SENSITIVE_LOGS$LOGGER_LEAKS"

if [ -z "$ALL_LOG_ISSUES" ]; then
  pass "No sensitive data found in logs"
else
  fail "Potential sensitive data in logs:"
  echo "$ALL_LOG_ISSUES" | sort -u | head -20 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 9. Dependency audit
# =============================================================================
header "Dependency Audit"

if [ "$FIX_MODE" = true ]; then
  # Non-forced only. `--force` can push breaking major versions into your
  # dependency tree, so it is intentionally never used. Review the git diff after.
  echo "    --fix: applying non-forced dependency fixes (review the git diff afterward)"
  case "$PKG_MANAGER" in
    npm)  npm audit fix 2>/dev/null || true ;;
    pnpm) pnpm audit --fix 2>/dev/null || true ;;
    *)    echo "    (auto audit-fix skipped for $PKG_MANAGER; run '$PKG_MANAGER audit' and update manually)" ;;
  esac
fi

if [ "$PKG_MANAGER" = "pnpm" ]; then
  AUDIT_OUTPUT=$(pnpm audit --json 2>/dev/null || true)
elif [ "$PKG_MANAGER" = "yarn" ]; then
  AUDIT_OUTPUT=$(yarn audit --json 2>/dev/null || true)
else
  AUDIT_OUTPUT=$(npm audit --json 2>/dev/null || true)
fi

VULNS=$(echo "$AUDIT_OUTPUT" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2 || echo "0")

if [ "${VULNS:-0}" -eq 0 ]; then
  pass "No known vulnerabilities in dependencies"
else
  HIGH_CRIT=$(echo "$AUDIT_OUTPUT" | grep -oE '"(high|critical)":[0-9]+' | awk -F: '{s+=$2} END {print s+0}')
  if [ "${HIGH_CRIT:-0}" -gt 0 ]; then
    fail "$VULNS vulnerabilities found ($HIGH_CRIT high/critical)"
  else
    warn "$VULNS vulnerabilities found (low/moderate)"
  fi
  echo "    Run '$PKG_MANAGER audit' for details"
fi

# =============================================================================
# 10. TypeScript type checking
# =============================================================================
header "TypeScript Type Check"

if [ -f "tsconfig.json" ]; then
  if ! has_local_bin tsc; then
    warn "tsconfig.json present but TypeScript is not installed locally; skipping typecheck (run install first). Not a failure."
  elif run_local_bin tsc --noEmit 2>/dev/null; then
    pass "TypeScript compilation successful"
  else
    fail "TypeScript compilation errors found"
    echo "    Run 'npx --no-install tsc --noEmit' for details"
  fi
else
  pass "No tsconfig.json found, skipping (not a TypeScript project)"
fi

# =============================================================================
# 11. ESLint security rules
# =============================================================================
header "ESLint Check"

ESLINT_TARGET="$SRC_DIR"
if ! has_local_bin eslint; then
  warn "ESLint is not installed locally; skipping lint. Not a failure."
else
  if [ "$FIX_MODE" = true ]; then
    run_local_bin eslint "$ESLINT_TARGET" --fix 2>/dev/null || true
  fi
  if run_local_bin eslint "$ESLINT_TARGET" 2>/dev/null; then
    pass "No ESLint errors"
  else
    warn "ESLint reported issues"
    echo "    Run 'npx --no-install eslint $ESLINT_TARGET' for details"
  fi
fi

# =============================================================================
# 12. Secret scanning (patterns)
# =============================================================================
header "Secret Scanning"

# NOTE: Stripe *publishable* keys (pk_live_/pk_test_) are public by design and are
# deliberately NOT listed here. Only the *secret* keys (sk_*) are real leaks.
SECRET_PATTERNS=(
  'sk-[a-zA-Z0-9]{20,}'           # OpenAI / Anthropic secret keys
  'sk_live_[a-zA-Z0-9]{20,}'      # Stripe SECRET live keys
  'sk_test_[a-zA-Z0-9]{20,}'      # Stripe SECRET test keys
  'ghp_[a-zA-Z0-9]{36}'           # GitHub PAT
  'github_pat_[a-zA-Z0-9_]{40,}'  # GitHub fine-grained PAT
  'gho_[a-zA-Z0-9]{36}'           # GitHub OAuth token
  'glpat-[a-zA-Z0-9\-]{20,}'      # GitLab PAT
  'AKIA[A-Z0-9]{16}'              # AWS access keys
  'xoxb-[0-9]{10,}'               # Slack bot tokens
  'xoxp-[0-9]{10,}'               # Slack user tokens
  'SG\.[a-zA-Z0-9_-]{22}\.'       # SendGrid keys
  'key-[a-zA-Z0-9]{32,}'          # Generic API keys
  'AIza[a-zA-Z0-9_-]{35}'         # Google API keys
  'ya29\.[a-zA-Z0-9_-]{50,}'      # Google OAuth tokens
  'eyJ[a-zA-Z0-9_-]{20,}\.eyJ'    # JWT tokens (hardcoded)
  'mongodb\+srv://[^:]+:[^@]+@'   # MongoDB connection strings with credentials
  'postgres://[^:]+:[^@]+@'       # PostgreSQL connection strings with credentials
  'mysql://[^:]+:[^@]+@'          # MySQL connection strings with credentials
  'redis://[^:]+:[^@]+@'          # Redis connection strings with credentials
)

SECRETS_FOUND=false
SCAN_DIR="$SRC_DIR"

for pattern in "${SECRET_PATTERNS[@]}"; do
  # Exclude build output, lockfiles, template env files (.env.example/.sample/...),
  # and obvious placeholder values so templates don't trip the scanner.
  MATCHES=$(grep -rnE "$pattern" $FILE_EXTS --include="*.env" --include="*.json" --include="*.yaml" --include="*.yml" "$SCAN_DIR" 2>/dev/null \
    | grep -vE "(node_modules|\.next|\.nuxt|dist|build|\.output|\.svelte-kit|\.lock|package-lock)" \
    | grep -vE '\.env\.(example|sample|template|dist)' \
    | grep -viE '(your[-_]|xxxxx|changeme|placeholder|<[a-z_]+>|example_|_example|dummy)' \
    || true)
  if [ -n "$MATCHES" ]; then
    SECRETS_FOUND=true
    fail "Potential hardcoded secret found:"
    echo "$MATCHES" | head -5 | while read -r line; do
      echo "    $line"
    done
  fi
done

if [ "$SECRETS_FOUND" = false ]; then
  pass "No hardcoded secrets detected"
fi

# Check .env files are gitignored
if [ -f ".gitignore" ]; then
  if grep -qE "^\.env" .gitignore 2>/dev/null; then
    pass ".env files are in .gitignore"
  else
    fail ".env files are NOT in .gitignore"
  fi
fi

# =============================================================================
# 13. CORS misconfiguration
# =============================================================================
header "CORS Configuration"

CORS_WILDCARD=$(grep -rnE "(Access-Control-Allow-Origin.*\*|cors\(\)|origin:\s*true|origin:\s*\*)" $FILE_EXTS "$SRC_DIR" 2>/dev/null | grep -vE "(node_modules|test|spec|__test)" || true)

if [ -z "$CORS_WILDCARD" ]; then
  pass "No wildcard CORS detected"
else
  warn "Wildcard or permissive CORS found (review if intentional):"
  echo "$CORS_WILDCARD" | head -10 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 14. SQL injection risk (raw queries)
# =============================================================================
header "SQL Injection Risk"

RAW_SQL=$(grep -rnE "(\.raw\(|\.rawQuery\(|\$\{.*\}.*SELECT|query\(.*\+.*\)|execute\(.*\+)" $FILE_EXTS "$SRC_DIR" 2>/dev/null | grep -vE "(node_modules|test|spec|__test|migration)" || true)

if [ -z "$RAW_SQL" ]; then
  pass "No raw SQL with potential injection detected"
else
  warn "Potential SQL injection (raw queries with string interpolation):"
  echo "$RAW_SQL" | head -10 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 15. Unsafe innerHTML / XSS vectors
# =============================================================================
header "XSS Risk"

XSS_PATTERNS=$(grep -rnE "(dangerouslySetInnerHTML|innerHTML\s*=|v-html=|\{@html|\.html\()" $FILE_EXTS "$SRC_DIR" 2>/dev/null | grep -vE "(node_modules|test|spec|__test)" || true)

if [ -z "$XSS_PATTERNS" ]; then
  pass "No unsafe innerHTML usage detected"
else
  warn "Potential XSS vectors (innerHTML/dangerouslySetInnerHTML):"
  echo "$XSS_PATTERNS" | head -10 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Security Audit Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  Errors:   ${RED}${ERRORS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}Security audit FAILED with $ERRORS error(s).${NC}"
  if [ "$CI_MODE" = true ]; then
    exit 1
  fi
  exit 0
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}Security audit passed with $WARNINGS warning(s).${NC}"
else
  echo -e "${GREEN}Security audit passed. All checks clean.${NC}"
fi
