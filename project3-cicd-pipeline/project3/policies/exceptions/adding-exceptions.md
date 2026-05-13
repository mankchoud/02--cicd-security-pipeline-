# Adding Security Exceptions

## What Is an Exception?

A security exception is formal documentation that a known finding has been
reviewed, accepted, and will not be fixed immediately. It is not a way to
permanently ignore security issues — every exception has an expiry date.

---

## When Is an Exception Appropriate?

| Situation | Action |
|---|---|
| True positive — fix is available | Fix the code. No exception needed. |
| True positive — no upstream fix yet | Time-bound exception with compensating controls |
| False positive | Suppress with inline comment + exception file |
| Free-tier build deviation | Already in checkov.yaml skip list — no file needed |
| Emergency deployment | Exception + follow-up ticket within 24 hours |

---

## How to Request an Exception

**Step 1 — Copy the template**
```bash
cp policies/exceptions/TEMPLATE.md \
   policies/exceptions/EXC-$(date +%Y%m%d)-<short-name>.md
```

**Step 2 — Fill it in** (takes about 5 minutes)

**Step 3 — Add an inline suppression** to the affected file so the scanner
knows this finding is reviewed:

For Checkov (Terraform):
```hcl
resource "aws_instance" "nat" {
  # checkov:skip=CKV_AWS_8: IMDSv1 required by user_data script.
  # Exception: EXC-20250101-imdsv2. Expires: 2025-07-01.
  ...
}
```

For Semgrep (Python/JS):
```python
query = "SELECT * FROM t WHERE id = " + uid  # nosemgrep: sql-injection-string-concat
# Exception: EXC-20250101-legacy-query. Tracked in JIRA-1234.
```

For Gitleaks:
```
# gitleaks:allow
DUMMY_KEY = "AKIAIOSFODNN7EXAMPLE"  # test fixture only
```

**Step 4 — Open a PR** — the pipeline will pass with the suppression in place.

---

## Exception Register

| ID | Tool | Check | Resource | Severity | Reason | Expiry |
|---|---|---|---|---|---|---|
| EXC-20250101-imdsv2 | Checkov | CKV_AWS_8 | aws_instance.nat | MEDIUM | NAT user_data needs IMDSv1 | 2025-07-01 |
| EXC-20250101-imdsv2b | Checkov | CKV_AWS_79 | aws_instance.* | MEDIUM | Same as above | 2025-07-01 |
| EXC-20250101-ebs | Checkov | CKV_AWS_135 | aws_instance.* | MEDIUM | Free-tier — no KMS key | 2025-07-01 |
| EXC-20250101-s3log | Checkov | CKV_AWS_18 | aws_s3_bucket.flow_logs | LOW | Recursive logging avoided | 2025-07-01 |
| EXC-20250101-db-sg | Checkov | CKV2_AWS_5 | aws_security_group.db | LOW | No RDS in free-tier build | 2025-07-01 |

---

## Quarterly Review

Every 90 days, run through this checklist:

- [ ] Any exceptions expired?
- [ ] Has an upstream fix become available for any CVE-based exception?
- [ ] Are compensating controls still in place?
- [ ] Can any exception be closed because the underlying issue was fixed?
