# Security Exception — TEMPLATE

**Exception ID:**   EXC-YYYYMMDD-short-name
**Date created:**   YYYY-MM-DD
**Created by:**     Your Name
**Expiry date:**    YYYY-MM-DD  (maximum 6 months)
**Status:**         Active

---

## Finding

| Field | Value |
|---|---|
| Tool | Checkov / Semgrep / Gitleaks / Trivy / pip-audit |
| Check ID | CKV_AWS_XXX / CVE-XXXX / GHSA-XXXX / rule-id |
| Severity | CRITICAL / HIGH / MEDIUM / LOW |
| Affected resource | e.g. aws_instance.nat in nat.tf line 42 |
| What the tool flagged | Description |

---

## Why It Is Not Being Fixed Now

- [ ] No upstream fix available yet
- [ ] Free-tier / learning build constraint (would be fixed in production)
- [ ] False positive (tool flagged something that is not a real risk)
- [ ] Compensating control exists (describe below)

**Compensating controls:**

**Justification:**

---

## Production Plan

How would this be handled in production?

---

## Approval

| Role | Name | Date |
|---|---|---|
| Requestor | | |
| Reviewer | | |
