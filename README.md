# Project 2: CI/CD Pipeline With Security Built In

A complete DevSecOps pipeline using GitHub Actions. Security checks run automatically on every push and pull request — catching secrets, vulnerabilities, misconfigurations, and dependency issues before they reach production. The pipeline directly scans the Terraform code from Project 2, connecting both projects into an end-to-end DevSecOps workflow.

> **$0 cost build.** The entire pipeline runs on GitHub Actions. No AWS CodePipeline, no CodeBuild, no ECR scanning, no Inspector. Every tool is open source. GitHub Actions provides 2,000 minutes/month free on private repos and unlimited minutes on public repos.

---

## Pipeline Flow

```
Developer
    │
    ▼ git commit
Pre-commit hook (scripts/pre-commit-hook.sh)
    ├── Gitleaks — staged files only (fast, before push)
    ├── terraform fmt — auto-fixes and re-stages .tf files
    └── File size check — blocks files > 5MB
    │
    ▼ push / pull_request
─────────────────────────────────────────────────────
GitHub Actions — security-scan.yml
─────────────────────────────────────────────────────
    │
    ▼
Step 2: Gitleaks (full git history)
    │  Any secret found → BLOCK PR
    │
    ├──────────────────┬──────────────────┐
    ▼                  ▼                  ▼
Step 3: Semgrep    Step 4: pip-audit  Step 5: Checkov
(SAST)             + npm audit        (IaC scan)
ERROR → BLOCK      CRITICAL → BLOCK   MEDIUM+ → BLOCK
WARN → continue    HIGH → warn
    │                  │                  │
    └──────────────────┴──────────────────┘
                        │
                        ▼
              Security Summary (if: always())
              Posts pass/fail table to PR
                        │
              ┌─────────┴──────────┐
              │                   │
         All pass             Any fail
              │                   │
        Merge allowed        PR blocked
```

Terraform-specific changes also trigger a separate workflow:

```
terraform-check.yml (triggers on .tf / .tfvars changes only)
    ├── Checkov — full IaC scan + SARIF upload
    ├── tfsec — second-opinion scan with different rule set
    ├── terraform fmt -check — formatting validation
    └── terraform validate — syntax + type check (-backend=false)
```

Container changes trigger:

```
container-scan.yml (triggers when Dockerfile changes)
    ├── Build image locally — never pushed to ECR ($0 scan cost)
    ├── Trivy — OS + app vulnerability scan (CRITICAL/HIGH → block)
    └── Trivy — Dockerfile config scan (root USER → block)
```

---

## Security Checks

### 1. Secret Scanning — Gitleaks OSS

Runs twice: on the pre-commit hook (staged files only, fast) and in CI (full git history on every push and PR).

- Detects: AWS access keys, GitHub tokens, RSA/EC private keys, passwords, generic API keys, database connection strings, JWT tokens
- Blocks: any detected secret — exit code 1 = PR blocked
- Configure allowlist in `.gitleaks.toml` for known false positives
- **Production equivalent:** GitHub Advanced Security push protection (~$19/user/mo)

### 2. SAST — Semgrep OSS

Runs on every PR. Results are uploaded as SARIF and appear inline on the PR diff in the GitHub Security tab.

| Rule set | Covers |
|---|---|
| `p/security-audit` | OWASP Top 10 — SQLi, XSS, RCE, SSRF |
| `p/python` | Python injection, unsafe deserialization |
| `p/javascript` | Node.js, prototype pollution |
| `p/terraform` | Terraform misconfigs — directly scans Project 2 |
| `p/secrets` | Second pass for secrets after Gitleaks |

Custom rules live in `policies/semgrep-rules/` covering hardcoded credentials, SQL injection patterns, Flask debug mode, and subprocess shell injection.

- Blocks: ERROR severity (HIGH/CRITICAL findings)
- Warns: WARNING severity — pipeline continues, finding is reported
- **Production equivalent:** SonarQube Cloud, GitHub CodeQL (GHAS)

### 3. Dependency Scanning — pip-audit + npm audit

- pip-audit queries the PyPA Advisory Database and OSV (Google Open Source Vulnerabilities)
- Custom parser `scripts/scan-results-parser.sh` applies blocking logic
- npm audit uses `--audit-level=critical` so only CRITICAL findings block

| Condition | Action |
|---|---|
| CRITICAL CVE with no available fix | BLOCK |
| HIGH CVE where a fix exists | WARN — update the package |
| MEDIUM CVE | WARN — pipeline continues |

- **Production equivalent:** Snyk team tier (~$25/user/mo), OWASP Dependency-Check

### 4. IaC Scanning — Checkov OSS + tfsec OSS

Scans all Terraform files from Project 2. This is the direct connection between both projects — the VPC infrastructure gets security-reviewed on every change.

Key checks that run against Project 2 Terraform:

| Check | Validates |
|---|---|
| CKV_AWS_130 | VPC default security group is closed |
| CKV_AWS_24 | VPC flow logs enabled |
| CKV2_AWS_12 | Default SG blocks all traffic |
| CKV_AWS_19 | S3 bucket server-side encryption |
| CKV_AWS_53 | S3 bucket public access blocked |
| CKV_AWS_92 | S3 lifecycle configuration present |

Every skipped check in `policies/checkov-config/checkov.yaml` has a documented reason and the production fix. tfsec runs alongside Checkov with a different rule set for better coverage.

- Blocks: MEDIUM/HIGH/CRITICAL failed checks
- **Production equivalent:** Checkov + Terraform Sentinel, Terraform Cloud run tasks

### 5. Container Scanning — Trivy OSS

The Docker image is built inside the GitHub Actions runner and scanned locally. It is **never pushed to ECR** — zero ECR storage cost, zero ECR scan cost.

- Scans OS packages (Alpine, Ubuntu, Amazon Linux CVEs)
- Scans application dependencies (pip, npm, gem, cargo)
- Scans Dockerfile misconfigurations (root USER, no HEALTHCHECK, sudo usage)
- Blocks: CRITICAL and HIGH vulnerabilities, container running as root
- **Production equivalent:** AWS ECR enhanced scanning (~$0.09/image), Amazon Inspector (~$0.002/hr)

---

## Block vs Warn Logic

| Finding | Tool | Action |
|---|---|---|
| Any secret detected | Gitleaks | **BLOCK** |
| SQL / command injection | Semgrep ERROR | **BLOCK** |
| S3 public access | Checkov | **BLOCK** |
| Missing VPC flow logs | Checkov | **BLOCK** |
| CRITICAL CVE with no fix | pip-audit | **BLOCK** |
| Container running as root | Trivy | **BLOCK** |
| MEDIUM dependency CVE | pip-audit | Warn — continue |
| Code quality findings | Semgrep WARN | Warn — continue |
| Informational findings | All tools | Warn — continue |
| Documented false positive | Suppressed | Passes — exception on file |

---

## Free-Tier Substitutions

| Production Tool | Substitute Used | Cost Saved |
|---|---|---|
| GitHub Advanced Security | Gitleaks + Semgrep OSS | ~$19/user/mo |
| SonarQube Cloud | Semgrep OSS | ~$15/mo+ |
| Snyk team tier | pip-audit + npm audit | ~$25/user/mo |
| AWS ECR enhanced scanning | Trivy (local, never pushed) | ~$0.09/image |
| Amazon Inspector | Trivy (local in runner) | ~$0.002/hr |
| AWS CodePipeline | GitHub Actions workflows | ~$1/pipeline/mo |
| AWS CodeBuild | GitHub-hosted runners | $0.005/build-min |

**Total monthly cost: $0**

---

## File Map

| File | Purpose |
|---|---|
| `.github/workflows/security-scan.yml` | Main pipeline — secrets, SAST, dependencies, IaC, summary |
| `.github/workflows/terraform-check.yml` | IaC-only — Checkov, tfsec, fmt, validate (triggers on .tf changes) |
| `.github/workflows/container-scan.yml` | Container — Trivy CVE + Dockerfile scan (image never pushed) |
| `policies/checkov-config/checkov.yaml` | Checkov skip list — every skip has reason + production fix |
| `policies/checkov-config/tfsec.yaml` | tfsec exclude list for deliberate free-tier deviations |
| `policies/semgrep-rules/no-hardcoded-credentials.yaml` | Custom SAST rules (AWS key patterns, SQLi, shell injection) |
| `policies/exceptions/adding-exceptions.md` | Exception process + the full exception register |
| `policies/exceptions/TEMPLATE.md` | Exception file template — 5 minutes to fill out |
| `scripts/pre-commit-hook.sh` | Local hook: Gitleaks (staged) + terraform fmt + file size |
| `scripts/scan-results-parser.sh` | pip-audit JSON parser — exits 1 on CRITICAL CVE with no fix |
| `docs/tool-configuration.md` | How each tool is configured, tuned, and what the production upgrade looks like |
| `docs/escalation-process.md` | Step-by-step: what to do when a check blocks your PR |

---

## Quick Start

```bash
# 1. Push this project to a GitHub repository

# 2. Install the pre-commit hook locally
cp scripts/pre-commit-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 3. Install Gitleaks locally (needed for the pre-commit hook)
#    Mac:     brew install gitleaks
#    Windows: choco install gitleaks
#    Linux:   https://github.com/gitleaks/gitleaks#installing

# 4. GitHub Actions workflows run automatically — no configuration needed
#    Push a commit or open a PR to trigger the pipeline

# 5. View results:
#    GitHub repo → Actions tab → select the workflow run
#    GitHub repo → Security → Code scanning (SARIF findings inline on PR)
```

---

## Exception Process

When a scan blocks a PR and the finding is a false positive or a deliberate deviation:

1. Copy `policies/exceptions/TEMPLATE.md` → fill in the finding, reason, and expiry date
2. Add an inline suppression comment to the affected file referencing the exception ID
3. Push — the pipeline passes with the suppression in place
4. Exceptions are reviewed quarterly and expired entries are closed

All current exceptions are registered in `policies/exceptions/adding-exceptions.md`.

---

## Questions Answered

**When should a pipeline block vs warn?**
Block on high-confidence, high-impact findings: secrets, injection vulnerabilities, public S3 buckets, CRITICAL CVEs with no fix, containers running as root. Warn on everything else. An overtuned pipeline that blocks on MEDIUM findings causes developers to use `git commit --no-verify` — which is worse than a lenient check.

**How do you handle false positives?**
Inline suppression comments (`# checkov:skip=CHECK_ID: reason`, `# nosemgrep: rule-id`) paired with an exception file in `policies/exceptions/`. Every suppression has a documented reason and an expiry date. The exception register is reviewed quarterly.

**How would this change in a regulated environment?**
Stricter thresholds (block on MEDIUM), SARIF evidence retained to S3 for auditors, mandatory security team sign-off for exceptions (not self-approval), 90-day maximum exception lifetime, compliance-specific rule sets (PCI-DSS, HIPAA profiles in both Semgrep and Checkov).

**How do you balance security with developer productivity?**
Results in under 5 minutes. Every finding includes the check ID, file, line number, and a link to `docs/escalation-process.md`. MEDIUM findings warn but don't block. The exception path is documented and fast. Security is the enabler, not the gatekeeper.
