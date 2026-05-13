# Project 3: CI/CD Pipelines With Security Built In

## Overview

Modern cloud security lives inside pipelines, not after deployment. This project demonstrates how to build a CI/CD pipeline that embeds security checks early in the development process—catching issues before they reach production.

This implementation targets the **AWS Free Tier**. All pipeline execution happens on GitHub Actions — no AWS CodePipeline, no CodeBuild, no ECR scanning, no Inspector. Every tool is open source and free.

**Free-Tier Substitutions:**

| Original | Free-Tier Substitute | Cost Saved |
|---|---|---|
| GitHub Advanced Security | Gitleaks + Semgrep OSS + GitHub Actions | ~$19/user/mo |
| SonarQube Cloud | Semgrep OSS | ~$15/mo+ |
| Snyk (team tier) | pip-audit + npm audit | ~$25/user/mo |
| AWS ECR scanning | Trivy (local in runner, never pushed) | ~$0.09/image |
| Amazon Inspector | Trivy (local in runner) | ~$0.002/instance/hr |
| AWS CodePipeline | GitHub Actions workflows | ~$1/pipeline/mo |
| AWS CodeBuild | GitHub-hosted runners | $0.005/build-min |

**Net cost: $0.** GitHub Actions provides 2,000 min/month free on private repos
and unlimited minutes on public repos.

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SECURE CI/CD PIPELINE                                   │
└─────────────────────────────────────────────────────────────────────────────────┘

 Developer                                                              Production
    │                                                                       │
    ▼                                                                       │
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐│
│  Code  │──▶│  Build │──▶│Security│──▶│  Test  │──▶│ Deploy │──▶│  Prod  ││
│ Commit │   │        │   │ Checks │   │        │   │Staging │   │        ││
└────────┘   └────────┘   └────────┘   └────────┘   └────────┘   └────────┘│
    │            │            │            │            │            │      │
    │            │            │            │            │            │      │
    ▼            ▼            ▼            ▼            ▼            ▼      │
┌────────────────────────────────────────────────────────────────────────────┐
│                        SECURITY GATES AT EACH STAGE                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  Pre-Commit    Build         Security       Test          Deploy    Prod  │
│  ──────────    ─────         ────────       ────          ──────    ────  │
│  • Secrets     • SAST        • IaC Scan     • DAST        • Approval • WAF│
│    scanning    • Dep scan    • Policy       • Pen test    • Canary   • IDS│
│  • Linting     • Container   • Compliance   • Fuzzing     • Rollback │    │
│  • Hooks         scan        • Threat                                │    │
│                                model                                 │    │
│                                                                      │    │
│  FREE-TIER (implemented):                                            │    │
│  Gitleaks      Semgrep OSS   Checkov OSS   [future]     [future] [future]│
│  pre-commit    pip-audit     tfsec OSS                              │    │
│  hook          npm audit     Trivy OSS                              │    │
│                                                                      │    │
└──────────────────────────────────────────────────────────────────────┴────┘
```

## Shift-Left Security Model

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      COST OF FIXING SECURITY ISSUES                             │
└─────────────────────────────────────────────────────────────────────────────────┘

                                                                           ┌───┐
                                                                           │   │
                                                                     ┌───┐ │   │
                                                               ┌───┐ │   │ │   │
                                                         ┌───┐ │   │ │   │ │   │
  Cost to                                          ┌───┐ │   │ │   │ │   │ │   │
   Fix ($)                                   ┌───┐ │   │ │   │ │   │ │   │ │   │
                                       ┌───┐ │   │ │   │ │   │ │   │ │   │ │   │
                                 ┌───┐ │   │ │   │ │   │ │   │ │   │ │   │ │   │
                           ┌───┐ │   │ │   │ │   │ │   │ │   │ │   │ │   │ │   │
                     ┌───┐ │   │ │   │ │   │ │   │ │   │ │   │ │   │ │   │ │   │
    ─────────────────┴───┴─┴───┴─┴───┴─┴───┴─┴───┴─┴───┴─┴───┴─┴───┴─┴───┴─┴───┴────▶
                     Code   Build  Test  Deploy  Staging  Prod  Incident  Breach
                    ◀───────────────────────────────────────────────────────────▶
                              Time in Development Lifecycle

    ═══════════════════════════════════════════════════════════════════════════
    │                                                                         │
    │   Catching issues HERE (left)         vs    HERE (right)                │
    │   $100 to fix                               $1,000,000+ to fix          │
    │                                                                         │
    ═══════════════════════════════════════════════════════════════════════════
```

## What You'll Build

### Security Checks to Implement

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY CHECK TYPES                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  1. SECRET SCANNING                                                             │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │  Tool: Gitleaks OSS                                                 │    │
│     │  [Free-tier substitute for: GitHub Advanced Security, truffleHog]   │    │
│     │  When: Pre-commit hook (laptop) + every push/PR in CI              │    │
│     │  Block: Yes - any detected secret blocks commit and PR             │    │
│     │  Production equivalent: GitHub Advanced Security push protection    │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  2. STATIC ANALYSIS (SAST)                                                      │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │  Tool: Semgrep OSS                                                  │    │
│     │  [Free-tier substitute for: SonarQube Cloud, GitHub CodeQL]        │    │
│     │  When: On every PR (needs: secret-scan)                            │    │
│     │  Block: ERROR severity (High/Critical findings)                    │    │
│     │  Warn: WARNING severity (pipeline continues)                       │    │
│     │  Production equivalent: SonarQube, GitHub CodeQL (GHAS)            │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  3. DEPENDENCY SCANNING                                                         │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │  Tool: pip-audit (Python) + npm audit (Node.js)                    │    │
│     │  [Free-tier substitute for: Snyk, OWASP Dependency-Check]          │    │
│     │  When: On every PR + push to main                                  │    │
│     │  Block: Critical CVEs with no available fix                        │    │
│     │  Warn: High CVEs where a fix exists                                │    │
│     │  Production equivalent: Snyk, Dependabot security updates          │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  4. INFRASTRUCTURE AS CODE SCANNING                                             │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │  Tool: Checkov OSS + tfsec OSS                                     │    │
│     │  [Free-tier substitute for: Checkov Cloud, Terraform Sentinel]     │    │
│     │  When: On PR when any .tf or .tfvars file changes                  │    │
│     │  Block: MEDIUM/HIGH/CRITICAL failed checks                         │    │
│     │  Scans: Project 2 Terraform directly (connects both projects)      │    │
│     │  Production equivalent: Checkov + Sentinel + Terraform Cloud tasks │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  5. CONTAINER SCANNING                                                          │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │  Tool: Trivy OSS                                                    │    │
│     │  [Free-tier substitute for: AWS ECR scanning, Amazon Inspector]    │    │
│     │  When: When Dockerfile changes or on push to main                  │    │
│     │  Block: Critical/High OS vulnerabilities, container running as root │    │
│     │  Note: Image built locally in runner - never pushed = $0 ECR cost  │    │
│     │  Production equivalent: ECR enhanced scanning + Amazon Inspector   │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         GITHUB ACTIONS PIPELINE FLOW                            │
│                              (security-scan.yml)                                │
└─────────────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────────────┐
                    │         on: [push, pull_request]     │
                    │         branches: [main, develop]    │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────▼───────────────────┐
                    │    Step 2: Secret Scanning           │
                    │    Tool: Gitleaks OSS                │
                    ├──────────────────────────────────────┤
                    │  ┌────────────────────────────────┐  │
                    │  │ Checkout code (full history)   │  │
                    │  └────────────────────────────────┘  │
                    │  ┌────────────────────────────────┐  │
                    │  │ gitleaks-action scan           │──┼──▶ Secret = BLOCK PR
                    │  └────────────────────────────────┘  │
                    └──────────────────┬───────────────────┘
                                       │
                         needs: secret-scan
                    (steps 3-5 only run if no secrets found)
                              ┌─────────┴──────────┐
                              │                    │
          ┌───────────────────▼──────┐  ┌──────────▼──────────────┐
          │  Step 3: SAST            │  │  Step 4: Dependencies   │
          │  Tool: Semgrep OSS       │  │  pip-audit + npm audit  │
          ├──────────────────────────┤  ├─────────────────────────┤
          │ p/security-audit         │  │ requirements.txt scan   │
          │ p/python / p/javascript  │  │ package.json scan       │
          │ p/terraform / p/secrets  │  │ scan-results-parser.sh  │
          │ SARIF -> Security tab    │  │                         │
          │                          │  │ Critical no-fix = BLOCK │
          │ ERROR = BLOCK PR         │  │ High w/fix = WARN       │
          │ WARNING = warn, continue │  │                         │
          └──────────────────────────┘  └─────────────────────────┘
                              │                    │
                              └─────────┬──────────┘
                                        │
                    ┌───────────────────▼──────────────────┐
                    │  Step 5: IaC Scan                    │
                    │  Tool: Checkov OSS                   │
                    ├──────────────────────────────────────┤
                    │  ┌────────────────────────────────┐  │
                    │  │ Scan all .tf files             │  │
                    │  │ (Project 2 Terraform)          │  │
                    │  └────────────────────────────────┘  │
                    │  ┌────────────────────────────────┐  │
                    │  │ Upload SARIF to Security tab   │  │
                    │  └────────────────────────────────┘  │
                    │  ┌────────────────────────────────┐  │
                    │  │ Enforce result (block if fail) │──┼──▶ Failed = Block PR
                    │  └────────────────────────────────┘  │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────▼───────────────────┐
                    │    Security Summary (if: always())   │
                    │    Posts pass/fail table to PR       │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────▼───────────────────┐
                    │    All Checks Pass?                  │
                    └──────────────────┬───────────────────┘
                              ┌────────┴────────┐
                              │                 │
                         ┌────▼────┐       ┌────▼────┐
                         │   YES   │       │   NO    │
                         └────┬────┘       └────┬────┘
                              │                 │
                    ┌─────────▼─────────┐  ┌────▼─────────────────┐
                    │ Continue to       │  │ Block merge          │
                    │ Build & Deploy    │  │ Show findings in PR  │
                    └───────────────────┘  │ docs/escalation-     │
                                           │ process.md           │
                                           └──────────────────────┘

SEPARATE WORKFLOW: terraform-check.yml
Triggers only when .tf or .tfvars files change:

    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Checkov    │  │   tfsec     │  │  terraform  │  │  terraform  │
    │  (full IaC  │  │  (2nd scan, │  │   fmt       │  │   validate  │
    │   scan)     │  │  diff rules)│  │  -check     │  │  -backend=f │
    └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
```

## Block vs Warn Decision Matrix

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    WHEN TO BLOCK vs WARN                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                        BLOCK (Pipeline Fails)                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Secrets in code (API keys, passwords, tokens)       → Gitleaks      │   │
│  │  • SQL injection vulnerabilities                       → Semgrep ERROR │   │
│  │  • Command injection vulnerabilities                   → Semgrep ERROR │   │
│  │  • S3 bucket public access                            → Checkov        │   │
│  │  • Security group open to 0.0.0.0/0 on sensitive ports → Checkov      │   │
│  │  • Critical CVE with no available fix                  → pip-audit     │   │
│  │  • Container running as root with sensitive mounts     → Trivy         │   │
│  │  • Missing encryption on data stores                   → Checkov       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│                        WARN (Let Pipeline Continue)                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Medium-severity dependency vulnerabilities          → pip-audit     │   │
│  │  • Code quality issues (complexity, duplication)       → Semgrep WARN │   │
│  │  • Missing security headers (can be added at Nginx)    → Semgrep INFO │   │
│  │  • Informational findings                              → all tools     │   │
│  │  • Known false positives (with documented exception)   → suppressed    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│                        CONTEXT MATTERS                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Internal tool vs customer-facing: different thresholds               │   │
│  │  • Regulated industry: stricter controls (see Compliance section)       │   │
│  │  • Emergency fix: exception process (docs/escalation-process.md)       │   │
│  │  • New repo vs established: different baseline expectations             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
03-cicd-security-pipeline/
├── README.md
├── .github/
│   └── workflows/
│       ├── security-scan.yml       # Main pipeline: secrets, SAST, deps, IaC
│       ├── terraform-check.yml     # IaC-specific: Checkov, tfsec, fmt, validate
│       └── container-scan.yml      # Container: Trivy image + Dockerfile scan
├── policies/
│   ├── semgrep-rules/
│   │   └── no-hardcoded-credentials.yaml  # Custom SAST rules
│   ├── checkov-config/
│   │   ├── checkov.yaml            # Skip list with documented reasons
│   │   └── tfsec.yaml              # tfsec exclude list
│   └── exceptions/
│       ├── adding-exceptions.md    # How to add security exceptions
│       └── TEMPLATE.md             # Exception file template
├── scripts/
│   ├── pre-commit-hook.sh          # Local pre-commit: Gitleaks + tf fmt + size
│   └── scan-results-parser.sh      # Parse pip-audit JSON, fail on CRITICAL
└── docs/
    ├── tool-configuration.md       # How each tool is configured and tuned
    └── escalation-process.md       # What to do when blocked
```

## Trade-off Discussions

### What happens if a security check is too strict?

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    STRICTNESS TRADE-OFF ANALYSIS                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  TOO STRICT                              TOO LENIENT                            │
│  ══════════                              ════════════                           │
│                                                                                 │
│  ┌────────────────────────┐              ┌────────────────────────┐             │
│  │ • Developers bypass    │              │ • Real vulnerabilities │             │
│  │   the process          │              │   reach production     │             │
│  │ • False positives      │              │ • Security debt grows  │             │
│  │   cause alert fatigue  │              │ • Trust in tools       │             │
│  │ • Productivity drops   │              │   diminishes           │             │
│  │ • Security becomes     │              │ • Incidents more       │             │
│  │   "the enemy"          │              │   likely               │             │
│  └────────────────────────┘              └────────────────────────┘             │
│                                                                                 │
│                          BALANCED APPROACH                                      │
│                          ═════════════════                                      │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │  1. Start with high-confidence rules only (p/security-audit not all)    │  │
│  │  2. Track false positive rate - if > 10%, tune the rule                  │  │
│  │  3. Make exceptions easy to request (TEMPLATE.md - 5 min to fill)       │  │
│  │  4. Review exceptions quarterly (register in adding-exceptions.md)      │  │
│  │  5. Gradually increase coverage as developers trust the system           │  │
│  │  6. Warn on MEDIUM, block on HIGH/CRITICAL - not everything blocks       │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Regulated Environment Considerations

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    COMPLIANCE REQUIREMENTS BY INDUSTRY                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  FINANCE (PCI-DSS)                HEALTHCARE (HIPAA)                            │
│  ─────────────────                ──────────────────                            │
│  • Code review required           • Audit logging mandatory                     │
│  • Vulnerability scan             • Access control review                       │
│    before deployment              • Encryption verification                     │
│  • Change management              • PHI data handling checks                    │
│    approval                       • SARIF evidence retained to S3               │
│  • Checkov: CKV_AWS_53 (S3)                                                    │
│                                                                                 │
│  GOVERNMENT (FedRAMP)             GENERAL (SOC 2)                               │
│  ────────────────────             ───────────────                               │
│  • Approved tool list             • Change management                           │
│  • Continuous monitoring          • Evidence of security                        │
│  • Boundary protection              testing (pipeline logs)                     │
│  • Supply chain controls          • Vulnerability management                    │
│                                                                                 │
│  ════════════════════════════════════════════════════════════════════════════  │
│  │  In regulated environments:                                               │  │
│  │  • Every exception needs documented justification  -> TEMPLATE.md        │  │
│  │  • Audit trails are mandatory                      -> pipeline SARIF      │  │
│  │  • Time-bound exceptions only (max 90 days)        -> expiry dates        │  │
│  │  • Regular compliance reporting from pipeline      -> summary + S3        │  │
│  ════════════════════════════════════════════════════════════════════════════  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Deliverables Checklist

- [x] GitHub Actions workflow for security scanning (`.github/workflows/security-scan.yml`)
- [x] Secret scanning with pre-commit hooks (`scripts/pre-commit-hook.sh`)
- [x] SAST integration — Semgrep OSS (security-scan.yml Step 3)
- [x] Dependency scanning configuration (security-scan.yml Step 4 + `scripts/scan-results-parser.sh`)
- [x] IaC scanning for Terraform — Checkov + tfsec (`.github/workflows/terraform-check.yml`)
- [x] Container scanning — Trivy OSS (`.github/workflows/container-scan.yml`)
- [x] Exception/override process documentation (`policies/exceptions/`)
- [x] Block vs warn threshold documentation (Decision Matrix above + `checkov.yaml`)
- [x] Sample PR showing blocked deployment — trigger by pushing a `.tf` file with a public S3 bucket; Checkov will block the PR with CKV_AWS_53

## Questions to Answer in Your Documentation

**1. What checks are included in your pipeline?**
Five check types across three workflow files: secret scanning (Gitleaks), SAST (Semgrep OSS), dependency scanning (pip-audit + npm audit), IaC scanning (Checkov + tfsec), and container scanning (Trivy). All five run automatically on push and pull request. A pre-commit hook runs Gitleaks and `terraform fmt` locally before commits reach GitHub.

**2. When should a pipeline block vs warn?**
Block on: any detected secret, HIGH/CRITICAL SAST findings, CRITICAL CVEs with no fix, MEDIUM+ failed Checkov checks, CRITICAL/HIGH container vulnerabilities. Warn on: MEDIUM dependency CVEs, LOW SAST findings, informational scan output, false positives that have a documented suppression. The goal is low false-positive rate — blocking on everything causes developers to route around the system entirely.

**3. What happens if a security check is too strict?**
Developers use `git commit --no-verify` and eventually disable workflows — which is worse than a slightly lenient check. The balanced approach: start with high-confidence rules only, track false-positive rate quarterly, make exceptions easy to request, and warn on MEDIUM rather than block.

**4. How would you handle false positives?**
Verify it is genuinely a false positive. Create an exception file from `policies/exceptions/TEMPLATE.md`. Add an inline suppression comment referencing the exception ID (`# checkov:skip=CKV_AWS_8: reason — exception EXC-YYYYMMDD`). Push. The exception register is reviewed quarterly and expired entries are closed.

**5. How would this change in a regulated environment?**
Stricter thresholds (block on MEDIUM), mandatory SARIF evidence retained to S3 for auditors, security team sign-off required for exceptions (not self-approval), 90-day max exception lifetime, compliance-specific rule sets (PCI-DSS and HIPAA profiles in both Semgrep and Checkov), and integration with a GRC tool for audit evidence.

**6. How do you balance security with developer productivity?**
Speed: results in under 5 minutes on GitHub-hosted runners. Clarity: every finding includes the check ID, affected resource, description, and a link to remediation in `docs/escalation-process.md`. Low noise: only high-confidence rules run by default; MEDIUM warns but does not block. Easy exception path: `TEMPLATE.md` takes 5 minutes to fill out. No gatekeeping: every blocked state has a documented resolution path.

## The Developer Experience Matters

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    DEVELOPER-FRIENDLY SECURITY                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  WHAT DEVELOPERS HATE:              WHAT DEVELOPERS APPRECIATE:                 │
│  ─────────────────────              ────────────────────────────                │
│                                                                                 │
│  ✗ Vague error messages             ✓ Clear, actionable findings                │
│    "Security check failed"            "Line 42: SQL injection - use            │
│                                        parameterized query instead"            │
│                                                                                 │
│  ✗ False positives                  ✓ High signal-to-noise ratio               │
│    with no way to override            with easy exception process              │
│    -> git commit --no-verify          policies/exceptions/TEMPLATE.md          │
│                                                                                 │
│  ✗ Slow feedback loop               ✓ Results in < 5 minutes                   │
│    (hour-long scans)                  (parallel GitHub Actions jobs)           │
│                                                                                 │
│  ✗ Security as gatekeeper           ✓ Security as enabler                      │
│    "You can't deploy"                 "Here's how to fix it"                   │
│                                       (docs/escalation-process.md)            │
│                                                                                 │
│  ✗ No context                       ✓ Links to remediation docs                │
│                                       + SARIF findings inline on PR diff      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Further Reading

- [GitHub Actions free tier](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions)
- [Semgrep Rules Registry](https://semgrep.dev/r)
- [Checkov Policies](https://www.checkov.io/5.Policy%20Index/all.html)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [Trivy](https://github.com/aquasecurity/trivy)
- [pip-audit](https://github.com/pypa/pip-audit)
- [OWASP DevSecOps Guidelines](https://owasp.org/www-project-devsecops-guideline/)
- [GitHub Advanced Security](https://docs.github.com/en/code-security) — production upgrade path

---

**Remember:** The important part is not the tool you use, but the mindset you demonstrate. You are showing that security is something engineers encounter early, automatically, and repeatedly.
