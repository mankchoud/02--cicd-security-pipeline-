# Tool Configuration

## 1. Gitleaks — Secret Scanning

**Type:** Open source  
**Free-tier substitute for:** GitHub Advanced Security secret scanning  
**Runs:** Pre-commit hook (laptop) + every push/PR in CI

### What it detects
AWS access keys, GitHub tokens, private keys (RSA/EC/PEM), generic API keys,
database connection strings containing passwords, JWT tokens, Stripe/Twilio/
SendGrid keys, and anything matching its built-in ruleset of 150+ patterns.

### Configuration
Default built-in ruleset is used. To customise, add `.gitleaks.toml`:

```toml
[extend]
useDefault = true

[[rules]]
id = "internal-api-key"
description = "Internal API key"
regex = '''MYAPP_KEY_[A-Za-z0-9]{32}'''
severity = "ERROR"

[allowlist]
paths = ["tests/fixtures/"]
commits = ["abc1234"]  # rotated credential, safe to ignore
```

---

## 2. Semgrep OSS — SAST

**Type:** Open source  
**Free-tier substitute for:** SonarQube Cloud, GitHub CodeQL  
**Runs:** Every PR (needs: secret-scan)

### Rule sets
| Rule set | Covers |
|---|---|
| `p/security-audit` | OWASP Top 10 — SQLi, XSS, RCE, SSRF |
| `p/python` | Python injection, unsafe deserialization |
| `p/javascript` | Node.js, prototype pollution |
| `p/terraform` | Terraform misconfigs — links to Project 2 |
| `p/secrets` | Second pass for secrets after Gitleaks |

### Custom rules
Add YAML files to `policies/semgrep-rules/`. See `no-hardcoded-credentials.yaml`
for the format.

### False positive suppression
```python
result = run(query)  # nosemgrep: sql-injection-string-concat
```
Always pair with an exception file in `policies/exceptions/`.

---

## 3. pip-audit — Python Dependency Scanning

**Type:** Open source (Google/PyPA)  
**Free-tier substitute for:** Snyk, OWASP Dependency-Check  
**Runs:** Every PR on `requirements.txt`

### Data sources
- PyPA Advisory Database
- OSV (Open Source Vulnerabilities) — Google

### Severity logic (scripts/scan-results-parser.sh)
| Condition | Action |
|---|---|
| CVE with no fix available | BLOCK (treated as CRITICAL) |
| CVE with fix available | WARN (update the package) |
| GHSA advisory | WARN |

### Production upgrade
```yaml
# OWASP Dependency-Check (production — gives real CVSS scores)
- name: OWASP Dependency-Check
  uses: dependency-check/Dependency-Check_Action@main
  with:
    path: '.'
    format: 'SARIF'
    args: --failOnCVSS 9
```

---

## 4. Checkov — IaC Scanning

**Type:** Open source (Bridgecrew/Palo Alto)  
**Free-tier substitute for:** Bridgecrew Cloud, Terraform Sentinel  
**Runs:** Every PR when `.tf` files change (via both workflows)

### Key checks on Project 2 Terraform
| Check | Validates |
|---|---|
| CKV_AWS_130 | VPC default security group closed |
| CKV_AWS_24 | VPC flow logs enabled |
| CKV2_AWS_12 | Default SG blocks all traffic |
| CKV_AWS_19 | S3 bucket has server-side encryption |
| CKV_AWS_53 | S3 bucket public access blocked |
| CKV_AWS_92 | S3 lifecycle configuration present |
| CKV_AWS_111 | IAM policies not overly permissive |

### Skip list
See `policies/checkov-config/checkov.yaml` — every skipped check has a
documented reason and production fix.

---

## 5. tfsec — IaC Scanning (Second Opinion)

**Type:** Open source (Aqua Security)  
**Runs:** Every PR when `.tf` files change (terraform-check.yml)  
**Purpose:** Different rule set from Checkov — running both improves coverage

---

## 6. Trivy — Container Scanning

**Type:** Open source (Aqua Security)  
**Free-tier substitute for:** AWS ECR enhanced scanning, Amazon Inspector  
**Runs:** When Dockerfile changes or push to main

### What it scans
- OS packages (Alpine, Ubuntu, Debian, Amazon Linux CVEs)
- Application dependencies (pip, npm, gem, cargo)
- Dockerfile misconfigurations (root user, no HEALTHCHECK)

### Thresholds
| Severity | Action |
|---|---|
| CRITICAL | Block |
| HIGH | Block |
| MEDIUM | Warn |
| LOW | Inform |

### Why images are never pushed to ECR in this build
The image is built inside the GitHub Actions runner and scanned there.
Trivy exits before any `docker push` command. This means:
- Zero ECR storage cost
- Zero ECR scan cost (~$0.09/image)
- Zero Inspector cost (~$0.002/instance/hour)

In production, run Trivy in CI (this file) AND enable ECR enhanced scanning
after push — defence in depth catches CVEs discovered after initial deployment.
