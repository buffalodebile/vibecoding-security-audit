#!/usr/bin/env bash
# =============================================================================
# Web Security Audit - Installer
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/buffalodebile/web-security-audit/main/install.sh | bash
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Installing Web Security Audit...${NC}"

# Download the script
curl -fsSL -o security-audit.sh https://raw.githubusercontent.com/buffalodebile/web-security-audit/main/security-audit.sh
chmod +x security-audit.sh

# Download the GitHub Action workflow
mkdir -p .github/workflows
curl -fsSL -o .github/workflows/security-audit.yml https://raw.githubusercontent.com/buffalodebile/web-security-audit/main/.github/workflows/security-audit.yml

echo -e "${GREEN}Done!${NC} Installed:"
echo "  - security-audit.sh (run locally with ./security-audit.sh)"
echo "  - .github/workflows/security-audit.yml (runs on every push)"
echo ""
echo "Try it now: ./security-audit.sh"
