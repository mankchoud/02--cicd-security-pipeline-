# Escalation Process — What to Do When Blocked

## Your PR is blocked. Work through these steps in order.

---

## Step 1 — Read the finding

Go to: GitHub repo → Security → Code scanning → open the finding.

Note:
- **Tool** (Gitleaks / Semgrep / pip-audit / Checkov / Trivy)
- **Check ID** (CKV_AWS_8 / CVE-2024-XXXXX / rule-id)
- **Severity** (CRITICAL / HIGH / MEDIUM)
- **File and line number**

---

## Step 2 — Determine the type

### True positive — fix is available → Fix it
| Finding type | Fix |
|---|---|
| Hardcoded secret | Remove it, rotate the credential, use Secrets Manager |
| SQL injection | Use a parameterised query |
| S3 public access | Add `aws_s3_bucket_public_access_block` |
| Container runs as root | Add `USER nonroot` to Dockerfile |
| Missing encryption | Add `encrypted = true` to EBS / SSE to S3 |
| EC2 IMDSv2 | Add `metadata_options { http_tokens = "required" }` |

### False positive → Suppress and document
1. Verify it is genuinely a false positive
2. Create `policies/exceptions/EXC-YYYYMMDD-name.md` from `TEMPLATE.md`
3. Add inline suppression comment referencing the exception ID
4. Push — pipeline passes

### No fix available yet → Time-bound exception
1. Check the CVE: what is the actual attack vector?
2. Identify compensating controls (network isolation, auth requirements, etc.)
3. Create exception with max 90-day expiry
4. Monitor for upstream patch

### Free-tier deviation → Already handled
Intentional free-tier deviations (EBS encryption, IMDSv2, etc.) are already
in `policies/checkov-config/checkov.yaml`. If you hit a new one, add it there
with a documented reason.

---

## Decision Tree

```
Pipeline blocked
      │
      ▼
Is it a real vulnerability?
      │
   No (false positive) ─────────────────▶ Suppress + exception file → done
      │
     Yes
      │
      ▼
Can I fix it now?
      │
    Yes ──────────────────────────────────▶ Fix code → push → done
      │
      No
      │
      ▼
Is a fix available upstream?
      │
    Yes ──────────────────────────────────▶ Update package → push → done
      │
      No
      │
      ▼
Is the risk acceptable?
      │
     No ──────────────────────────────────▶ Escalate to security team now
      │
     Yes
      │
      ▼
Create time-bound exception → document controls → push → done
```

---

## Emergency Bypass

Use only when a deployment is urgent and risk has been accepted:

```bash
git commit --no-verify -m "Emergency: <reason> — exception EXC-YYYYMMDD"
```

Within 24 hours, you must:
1. Create a proper exception file
2. Open a ticket to address the finding
3. Notify the security team

---

## Getting Help

- Tool-specific configuration: `docs/tool-configuration.md`
- Exception format: `policies/exceptions/TEMPLATE.md`
- Exception register: `policies/exceptions/adding-exceptions.md`
