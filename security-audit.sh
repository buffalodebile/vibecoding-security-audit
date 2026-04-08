#!/usr/bin/env bash
# =============================================================================
# Next.js Security Audit Script
# =============================================================================
# Automated security checks for Next.js projects.
# Based on Burak Eregar's 9 security principles for AI-assisted development.
#
# Usage: ./security-audit.sh [--ci] [--fix]
#   --ci   Exit with non-zero code on any failure (for CI/CD)
#   --fix  Auto-fix issues where possible (npm audit fix, eslint --fix)
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

# Detect source directory
SRC_DIR="src"
if [ ! -d "$SRC_DIR" ]; then
  SRC_DIR="app"
  if [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Error: No src/ or app/ directory found.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}Next.js Security Audit${NC}"
echo "Source directory: $SRC_DIR"
echo "Mode: $([ "$CI_MODE" = true ] && echo 'CI' || echo 'local')$([ "$FIX_MODE" = true ] && echo ' + auto-fix' || echo '')"

# =============================================================================
# 1. Database imports in client components
# =============================================================================
header "Principle 1: No database access in client code"

CLIENT_DB_IMPORTS=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "from ['\"](@prisma|prisma|@supabase/supabase-js|drizzle-orm|mongoose|typeorm|knex|sequelize)" "$file" 2>/dev/null; then
    echo "$file"
  fi
done || true)

if [ -z "$CLIENT_DB_IMPORTS" ]; then
  pass "No database imports found in 'use client' files"
else
  fail "Database imports found in client files:"
  echo "$CLIENT_DB_IMPORTS" | while read -r file; do
    echo "    - $file"
  done
fi

# =============================================================================
# 2. API endpoint authentication
# =============================================================================
header "Principle 2: Authentication on API endpoints"

API_ROUTES=$(find "$SRC_DIR" -path "*/api/*" -name "route.ts" -o -name "route.js" 2>/dev/null || true)

if [ -n "$API_ROUTES" ]; then
  UNPROTECTED=0
  while IFS= read -r route; do
    if ! grep -qE "(getServerSession|getSession|auth\(|getToken|verifyToken|authenticate|requireAuth|withAuth|getUser|currentUser|clerkClient|getAuth)" "$route" 2>/dev/null; then
      warn "No auth check detected: $route"
      UNPROTECTED=$((UNPROTECTED + 1))
    fi
  done <<< "$API_ROUTES"
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

PREMIUM_CLIENT=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "(isPremium|isSubscribed|isPro|planType|subscription)" "$file" 2>/dev/null; then
    if ! grep -qE "(fetch|api/|server|action)" "$file" 2>/dev/null; then
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
header "Principle 4: No secrets in NEXT_PUBLIC_* variables"

EXPOSED_SECRETS=$(grep -rnE "NEXT_PUBLIC_.*(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE)" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.env*" . 2>/dev/null | grep -vE "(node_modules|\.next|dist|build)" || true)

if [ -z "$EXPOSED_SECRETS" ]; then
  pass "No secrets detected in NEXT_PUBLIC_* variables"
else
  fail "Potential secrets exposed via NEXT_PUBLIC_*:"
  echo "$EXPOSED_SECRETS" | head -20 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 5. Client-side sensitive calculations
# =============================================================================
header "Principle 5: Sensitive calculations are server-side"

PRICE_CLIENT=$(grep -rn '"use client"' --include="*.ts" --include="*.tsx" -l "$SRC_DIR" 2>/dev/null | while read -r file; do
  if grep -qE "(calculatePrice|calculateScore|computeDiscount|finalPrice|totalAmount)" "$file" 2>/dev/null; then
    echo "$file"
  fi
done || true)

if [ -z "$PRICE_CLIENT" ]; then
  pass "No price/score calculations in client components"
else
  warn "Sensitive calculations found in client files (should be server-side):"
  echo "$PRICE_CLIENT" | while read -r file; do
    echo "    - $file"
  done
fi

# =============================================================================
# 6. Input validation
# =============================================================================
header "Principle 6: Input sanitization"

if [ -n "$API_ROUTES" ]; then
  UNVALIDATED=0
  while IFS= read -r route; do
    if ! grep -qE "(zod|yup|joi|validate|sanitize|ajv|superstruct|valibot|z\.object|z\.string)" "$route" 2>/dev/null; then
      warn "No input validation library detected: $route"
      UNVALIDATED=$((UNVALIDATED + 1))
    fi
  done <<< "$API_ROUTES"
  if [ "$UNVALIDATED" -eq 0 ]; then
    pass "All API routes appear to use input validation"
  fi
fi

# =============================================================================
# 7. Rate limiting on expensive endpoints
# =============================================================================
header "Principle 7: Rate limiting on expensive endpoints"

EXPENSIVE_PATTERNS="(openai|anthropic|stripe|sendgrid|resend|twilio|aws-sdk|generate|ai\/)"
EXPENSIVE_ROUTES=""
if [ -n "$API_ROUTES" ]; then
  while IFS= read -r route; do
    if grep -qE "$EXPENSIVE_PATTERNS" "$route" 2>/dev/null; then
      if ! grep -qE "(rateLimit|rateLimiter|upstash|@upstash\/ratelimit|limiter|throttle)" "$route" 2>/dev/null; then
        EXPENSIVE_ROUTES="$EXPENSIVE_ROUTES$route"$'\n'
      fi
    fi
  done <<< "$API_ROUTES"
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

SENSITIVE_LOGS=$(grep -rnE "console\.(log|info|debug|warn)\(.*\b(password|token|secret|apiKey|api_key|credential|authorization|bearer)\b" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" "$SRC_DIR" 2>/dev/null || true)

if [ -z "$SENSITIVE_LOGS" ]; then
  pass "No sensitive data found in console logs"
else
  fail "Potential sensitive data in logs:"
  echo "$SENSITIVE_LOGS" | head -20 | while read -r line; do
    echo "    $line"
  done
fi

# =============================================================================
# 9. Dependency audit
# =============================================================================
header "Dependency Audit (npm audit)"

if [ "$FIX_MODE" = true ]; then
  npm audit fix --force 2>/dev/null || true
fi

AUDIT_OUTPUT=$(npm audit --json 2>/dev/null || true)
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
  echo "    Run 'npm audit' for details"
fi

# =============================================================================
# 10. TypeScript type checking
# =============================================================================
header "TypeScript Type Check"

if command -v npx &>/dev/null && [ -f "tsconfig.json" ]; then
  if npx tsc --noEmit 2>/dev/null; then
    pass "TypeScript compilation successful"
  else
    fail "TypeScript compilation errors found"
    echo "    Run 'npx tsc --noEmit' for details"
  fi
else
  warn "TypeScript not configured, skipping"
fi

# =============================================================================
# 11. ESLint security rules
# =============================================================================
header "ESLint Security Check"

if command -v npx &>/dev/null; then
  if [ "$FIX_MODE" = true ]; then
    npx eslint "$SRC_DIR" --fix 2>/dev/null || true
  fi
  if npx eslint "$SRC_DIR" 2>/dev/null; then
    pass "No ESLint errors"
  else
    warn "ESLint reported issues"
    echo "    Run 'npx eslint $SRC_DIR' for details"
  fi
else
  warn "ESLint not available, skipping"
fi

# =============================================================================
# 12. Secret scanning (patterns)
# =============================================================================
header "Secret Scanning"

# Common secret patterns (regex)
SECRET_PATTERNS=(
  'sk-[a-zA-Z0-9]{20,}'           # OpenAI keys
  'sk_live_[a-zA-Z0-9]{20,}'      # Stripe live keys
  'ghp_[a-zA-Z0-9]{36}'           # GitHub PAT
  'github_pat_[a-zA-Z0-9_]{40,}'  # GitHub fine-grained PAT
  'glpat-[a-zA-Z0-9\-]{20,}'      # GitLab PAT
  'AKIA[A-Z0-9]{16}'              # AWS access keys
  'xoxb-[0-9]{10,}'               # Slack bot tokens
  'xoxp-[0-9]{10,}'               # Slack user tokens
  'SG\.[a-zA-Z0-9_-]{22}\.'       # SendGrid keys
  'key-[a-zA-Z0-9]{32,}'          # Generic API keys
)

SECRETS_FOUND=false
for pattern in "${SECRET_PATTERNS[@]}"; do
  MATCHES=$(grep -rnE "$pattern" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.env" "$SRC_DIR" 2>/dev/null | grep -v "node_modules" || true)
  if [ -n "$MATCHES" ]; then
    SECRETS_FOUND=true
    fail "Potential hardcoded secret found (pattern: $pattern):"
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
