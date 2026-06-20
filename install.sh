#!/usr/bin/env bash
# =============================================================================
# Vibecoding Web Security Audit - Installer (local, offline)
# =============================================================================
# Copies the audit script + GitHub Action into a target project. It does NOT
# download anything and is NOT meant to be piped into a shell: clone the repo,
# read the code, then run this from the clone.
#
#   git clone https://github.com/buffalodebile/vibecoding-security-audit.git
#   cd vibecoding-security-audit
#   ./install.sh /path/to/your/project      # omit the path to use the current dir
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RAW_TARGET="${1:-$PWD}"

# Resolve to an absolute path so it is always clear where files will land (#6).
TARGET_DIR="$(cd "$RAW_TARGET" 2>/dev/null && pwd || true)"
if [ -z "$TARGET_DIR" ]; then
  echo "Target directory does not exist: $RAW_TARGET" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/security-audit.sh" ]; then
  echo "security-audit.sh not found next to this installer." >&2
  echo "Run install.sh from a clone of the repo, not via curl | bash." >&2
  exit 1
fi

echo -e "${BLUE}Vibecoding Web Security Audit - installer${NC}"
echo "  Source : $SCRIPT_DIR"
echo "  Target : $TARGET_DIR"

if [ ! -f "$TARGET_DIR/package.json" ]; then
  echo -e "  ${YELLOW}Note:${NC} no package.json found here - this may not be a JS/TS project root."
fi
if [ -f "$TARGET_DIR/security-audit.sh" ]; then
  echo -e "  ${YELLOW}Note:${NC} an existing security-audit.sh will be overwritten."
fi

cp "$SCRIPT_DIR/security-audit.sh" "$TARGET_DIR/security-audit.sh"
chmod +x "$TARGET_DIR/security-audit.sh"

mkdir -p "$TARGET_DIR/.github/workflows"
cp "$SCRIPT_DIR/.github/workflows/security-audit.yml" "$TARGET_DIR/.github/workflows/security-audit.yml"

echo -e "${GREEN}Done.${NC} Installed into $TARGET_DIR:"
echo "  - security-audit.sh                      (run: ./security-audit.sh)"
echo "  - .github/workflows/security-audit.yml   (runs on every push / PR)"
echo ""
echo "Next: cd \"$TARGET_DIR\" && ./security-audit.sh"
