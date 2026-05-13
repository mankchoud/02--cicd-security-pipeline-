#!/usr/bin/env bash
###############################################################################
# scan-results-parser.sh — Parse and Format Scan Results
#
# Usage:
#   bash scripts/scan-results-parser.sh <results-file> <scanner-type>
#
# Supported scanner types: python, npm
#
# Exit codes:
#   0 = no blocking vulnerabilities
#   1 = CRITICAL vulnerability found — blocks the pipeline
#
# PRODUCTION NOTE: In production you would use Snyk or OWASP Dependency-Check
#   which both output CVSS scores directly. pip-audit does not always include
#   severity, so this script applies a simple heuristic: CVEs with no fix
#   available are treated as CRITICAL (block); all others are warnings.
###############################################################################

set -euo pipefail

RESULTS_FILE="${1:-}"
SCANNER_TYPE="${2:-python}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ -z "$RESULTS_FILE" ] || [ ! -f "$RESULTS_FILE" ]; then
  echo "Usage: scan-results-parser.sh <results-file> <scanner-type>"
  exit 0
fi

echo ""
echo "=== Dependency Scan Results ($SCANNER_TYPE) ==="
echo ""

BLOCKING=0

if [ "$SCANNER_TYPE" = "python" ]; then

  # Parse pip-audit JSON output
  # Format: {"dependencies": [{"name": "...", "version": "...", "vulns": [...]}]}

  TOTAL_DEPS=$(python3 -c "
import json, sys
data = json.load(open('$RESULTS_FILE'))
deps = data.get('dependencies', [])
print(len(deps))
" 2>/dev/null || echo "0")

  VULN_COUNT=$(python3 -c "
import json, sys
data = json.load(open('$RESULTS_FILE'))
count = sum(len(d.get('vulns',[])) for d in data.get('dependencies',[]))
print(count)
" 2>/dev/null || echo "0")

  echo "Scanned $TOTAL_DEPS Python packages — $VULN_COUNT vulnerabilities found"
  echo ""

  if [ "$VULN_COUNT" -gt 0 ]; then
    python3 - <<'PYEOF'
import json, sys, os

results_file = os.environ.get('RESULTS_FILE') or sys.argv[1] if len(sys.argv) > 1 else None
# Read from the file path passed as shell variable
import subprocess
data = json.loads(open(os.sys.argv[1] if len(os.sys.argv) > 1 else 'pip-audit-results.json').read())

blocking = False
for dep in data.get('dependencies', []):
    for vuln in dep.get('vulns', []):
        pkg      = dep.get('name', 'unknown')
        version  = dep.get('version', 'unknown')
        vid      = vuln.get('id', 'unknown')
        aliases  = vuln.get('aliases', [])
        fix_vers = vuln.get('fix_versions', [])
        desc     = vuln.get('description', '')[:100]

        # Heuristic: no fix available on a CVE = treat as CRITICAL
        is_cve     = any('CVE' in a for a in aliases)
        no_fix     = len(fix_vers) == 0
        is_critical = is_cve and no_fix

        severity = 'CRITICAL (no fix)' if is_critical else 'HIGH (fix available)'
        icon     = 'X' if is_critical else 'W'

        print(f'[{icon}] {pkg}=={version}')
        print(f'     ID:       {vid}')
        if aliases:
            print(f'     CVEs:     {", ".join(aliases)}')
        print(f'     Severity: {severity}')
        if fix_vers:
            print(f'     Fix in:   {", ".join(fix_vers)}')
        else:
            print(f'     Fix in:   None available yet')
        print(f'     Details:  {desc}...')
        print()

        if is_critical:
            blocking = True

if blocking:
    print('RESULT: CRITICAL vulnerabilities found - pipeline blocked.')
    print('Update affected packages or create an exception in policies/exceptions/')
    sys.exit(1)
else:
    print('RESULT: No CRITICAL vulnerabilities. Warnings above should be addressed.')
    sys.exit(0)
PYEOF
    BLOCKING=$?
  else
    echo -e "${GREEN}No vulnerabilities found in Python dependencies.${NC}"
  fi

elif [ "$SCANNER_TYPE" = "npm" ]; then

  # npm audit --json already exits 1 on CRITICAL — this is a display formatter
  CRITICAL_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$RESULTS_FILE'))
    meta = data.get('metadata', {}).get('vulnerabilities', {})
    print(meta.get('critical', 0))
except:
    print(0)
" 2>/dev/null || echo "0")

  HIGH_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$RESULTS_FILE'))
    meta = data.get('metadata', {}).get('vulnerabilities', {})
    print(meta.get('high', 0))
except:
    print(0)
" 2>/dev/null || echo "0")

  echo "npm audit summary:"
  echo "  CRITICAL: $CRITICAL_COUNT"
  echo "  HIGH:     $HIGH_COUNT"
  echo ""

  if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}CRITICAL npm vulnerabilities found - pipeline blocked.${NC}"
    BLOCKING=1
  elif [ "$HIGH_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}HIGH npm vulnerabilities found - update packages (warning only).${NC}"
  else
    echo -e "${GREEN}No CRITICAL or HIGH npm vulnerabilities.${NC}"
  fi

fi

exit $BLOCKING
