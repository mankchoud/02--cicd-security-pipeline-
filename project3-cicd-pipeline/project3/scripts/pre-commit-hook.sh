#!/usr/bin/env bash
###############################################################################
# pre-commit-hook.sh — Local Pre-Commit Security Checks
#
# INSTALL:
#   cp scripts/pre-commit-hook.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or with the pre-commit framework:
#   pip install pre-commit
#   pre-commit install
#
# PURPOSE:
#   Catches secrets and formatting issues on your LAPTOP before the commit
#   is made. Much faster feedback than waiting for CI to run.
#   "Shift left" — the earlier you catch it, the cheaper it is to fix.
#
# CHECKS:
#   1. Gitleaks   — secret detection on staged files only (fast)
#   2. tf fmt     — auto-formats .tf files and re-stages them
#   3. File size  — blocks files > 5MB (prevent binary/dataset commits)
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "Running pre-commit security checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FAILURES=0

###############################################################################
# CHECK 1: Secret Scanning with Gitleaks
# Scans only staged files so it is fast (not the entire history).
# The CI pipeline scans the full history — this is the fast local layer.
###############################################################################
echo ""
echo "Check 1/3: Secret scanning (Gitleaks)"

if command -v gitleaks &>/dev/null; then
  if gitleaks protect --staged --verbose 2>/dev/null; then
    echo -e "  ${GREEN}PASS - No secrets in staged files${NC}"
  else
    echo -e "  ${RED}FAIL - Secrets detected in staged files${NC}"
    echo "  Remove the secret, then commit."
    echo "  If this is a false positive:"
    echo "    1. Add path to .gitleaks.toml allowlist"
    echo "    2. Document in policies/exceptions/"
    echo "    3. git commit --no-verify (last resort, requires justification)"
    ((FAILURES++))
  fi
else
  echo -e "  ${YELLOW}SKIP - Gitleaks not installed${NC}"
  echo "  Install: brew install gitleaks  (Mac)"
  echo "           choco install gitleaks (Windows)"
  echo "           https://github.com/gitleaks/gitleaks#installing"
fi

###############################################################################
# CHECK 2: Terraform Formatting
# Auto-fixes .tf files and re-stages them so the commit always has
# correctly-formatted code without the developer needing to run fmt manually.
###############################################################################
echo ""
echo "Check 2/3: Terraform formatting"

if git diff --cached --name-only | grep -q '\.tf$'; then
  if terraform fmt -check -recursive . &>/dev/null; then
    echo -e "  ${GREEN}PASS - All .tf files correctly formatted${NC}"
  else
    echo -e "  ${YELLOW}INFO - Auto-fixing Terraform formatting${NC}"
    terraform fmt -recursive .
    # Re-stage the reformatted files
    git diff --cached --name-only | grep '\.tf$' | xargs git add
    echo -e "  ${GREEN}PASS - Files reformatted and re-staged${NC}"
  fi
else
  echo -e "  ${GREEN}PASS - No .tf files staged${NC}"
fi

###############################################################################
# CHECK 3: Large File Detection
# Prevents accidentally committing datasets, compiled binaries, or
# .terraform provider zips (should be in .gitignore).
###############################################################################
echo ""
echo "Check 3/3: Large file check (> 5MB)"

LARGE=""
while IFS= read -r f; do
  if [ -f "$f" ]; then
    SIZE=$(du -k "$f" | cut -f1)
    if [ "$SIZE" -gt 5120 ]; then
      LARGE="$LARGE\n  $f (${SIZE} KB)"
    fi
  fi
done < <(git diff --cached --name-only)

if [ -z "$LARGE" ]; then
  echo -e "  ${GREEN}PASS - No large files staged${NC}"
else
  echo -e "  ${YELLOW}WARN - Large files staged:${NC}"
  printf "%b\n" "$LARGE"
  echo "  Store large files in S3 or Git LFS, not the repo."
  echo "  If intentional: git commit --no-verify"
  ((FAILURES++))
fi

###############################################################################
# Result
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAILURES" -gt 0 ]; then
  echo -e "${RED}BLOCKED - $FAILURES check(s) failed. Commit not made.${NC}"
  echo ""
  echo "To bypass (document your reason first):"
  echo "  git commit --no-verify -m 'your message'"
  echo ""
  exit 1
else
  echo -e "${GREEN}PASSED - All checks passed. Committing...${NC}"
  echo ""
  exit 0
fi
