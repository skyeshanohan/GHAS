# Web Application Firewall (WAF) Strategy – Product Discovery  
*Version 1.0 – DRAFT*

**Initiative Statement** 
Our organization currently lacks a unified Web Application Firewall protecting all internet-facing assets. We are actively decommissioning legacy F5 WAF appliances, and utilization of AWS WAF remains minimal. We therefore need to identify a platform-agnostic WAF solution that is easily configurable and scalable, integrates seamlessly with our Cloud Security Posture Management (CSPM) tooling, and supports Infrastructure-as-Code provisioning through Terraform.

---

## 1 🧱 Operational Model

### 1.1 Approach Options

| Model | Pros | Cons | Operational Implications |
|-------|------|------|--------------------------|
| **Team Ownership**<br/>Engineering teams implement and manage their own WAF instances using baseline rulesets provided by Security. | • Faster application-specific tuning<br/>• Empowers teams closest to the traffic<br/>• Scales organically with org growth | • Risk of rule-disable sprawl without guard-rails<br/>• Potential posture drift across teams | • Requires self-service Terraform module, baseline rulesets, automated validation, and centralized visibility |
| **Central Ownership (NOT RECOMMENDED)**<br/>Security Platform team deploys & maintains all WAF rulesets. | • Consistent rule quality & rapid global tuning<br/>• Centralized expertise & visibility<br/>• Simplified vendor relationship | • 24 × 365 on-call burden<br/>• Scaling delays for product-team–specific changes<br/>• Risk of becoming bottleneck | • Requires dedicated WAF SRE rotation and runbooks<br/>• Central budget ownership |

### 1.2 Key Controls for Decentralized Model

### Key Controls for Team Ownership
1. **Immutable Baseline Ruleset**  
   • Baseline managed rule sets are centrally maintained by Security and automatically enforced by the module.  
   • Product teams **cannot delete or modify** baseline rules; they can only layer additional rules or create scoped exceptions (default expiry **24 h** if not specified).

2. **Prevent Over-use of Rule Disabling**  
   • Mandatory peer-review (e.g., +1) for any `allow` / `disable` change  
   • Time-boxed exceptions with auto-revert (default 24 h)  
   • Change-reason tagging for audit

3. **Validate Effectiveness**  
   • Central observability dashboard (blocked vs. allowed events)  
   • Synthetic attack testing in CI pipeline  
   • Quarterly rule efficacy review with Wiz findings

### 1.3 Recommendation
Adopt a **team-owned WAF model**:  
* Engineering teams implement and manage their own WAF instances via the centrally maintained Terraform module and baseline rulesets.  
* Security Platform team maintains the Terraform module, curates baseline rulesets, and provides continuous validation, monitoring, and reporting of deviations.  
This approach empowers teams while ensuring a consistent, organization-wide security posture without placing day-to-day operational burden on the Security Platform team.

---

## 2 🔍 Vendor Strategy & RFP Evaluation

### Why an RFP?
A single cross-environment provider (on-prem, AWS, GCP, Azure) simplifies:  
* Policy consistency  
* Unified logging & analytics  
* Volume-based pricing

### MoSCoW Prioritization

| Statement | Priority |
|-----------|----------|
| Coverage for L3–L7 OWASP Top 10 & Bot mitigation | **Must have** |
| Multi-cloud & on-prem deployment options (SaaS / hybrid) | **Must have** |
| Terraform & API-first configuration management | **Must have** |
| Native telemetry / event-stream APIs for log and analytics export | **Must have** |
| Native integration with SIEM (Splunk) & Wiz | **Must have** |
| ML-based anomaly detection | **Should have** |
| Built-in DDoS protection up to *X Gbps* | **Should have** |
| 99.99 % global SLA | **Should have** |
| Managed rules marketplace | **Should have** |
| Out-of-the-box dashboards in Looker | **Could have** |
| Simplified licensing model | **Could have** |
| CSP-native billing integration | **Could have** |
| On-prem hardware appliances | **Won't have** |
| Manual UI-only rule management | **Won't have** |

### Next Steps
1. Issue RFP to short-listed vendors (Cloudflare, Akamai, Fastly, AWS WAF).  
2. Run a 30-day PoC in a non-prod account measuring latency (< 10 ms added) & false-positive rate (< 0.01 %).  
3. Select provider by **Q3-FY24**.

---

## 3 🧰 Terraform Module Proposal

### Design Principles
* **WAF-agnostic**: abstract common rule constructs; vendor-specific adapters.  
* **Composable**: teams can layer custom rules on top of baseline.  
* **Guard-rails**: module enforces policy controls (e.g., cannot delete baseline rules).  
* **Observability**: auto-create log sinks and CloudWatch/Stackdriver dashboards.

### Module Interfaces

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `provider` | string | `aws`, `gcp`, `azure`, `cloudflare`, etc. | n/a |
| `baseline_rule_set_version` | string | **Security-owned** version of baseline rules applied to all WAFs | `"v2024-01"` |
| `managed_rule_sets` | list(string) | Vendor-provided rule sets to enable (e.g., `"owasp_core"`, `"bot_protection"`) | `["owasp_core"]` |
| `custom_rules` | list(object) | Team-owned additional rules (priority, action, match) applied **after** baseline | `[]` |
| `exception_rules` | list(object) | Temporary overrides (rule_id, action, reason, ttl_hours) | `[]` |
| `exception_default_ttl_hours` | number | Default TTL (hours) applied to an exception when `ttl_hours` is omitted | `24` |
| `rate_limit` | object({ limit = number, window = number }) | Global rate-limit settings (requests per `window` seconds) | `{ limit = 1000, window = 60 }` |
| `allowed_ip_cidrs` | list(string) | IP allow lists applied before other rules | `[]` |
| `block_override` | bool | Emergency switch to allow traffic if baseline blocks critical path | `false` |
| `enable_logging` | bool | Toggle detailed request logging | `true` |
| `logging_endpoint` | string | Destination for WAF logs | `"${module.observability.log_sink}"` |
| `metrics_namespace` | string | Cloud provider metrics namespace | `"waf"` |
| `tags` | map(string) | Resource tags for cost allocation / ownership | `{}` |

### Outputs

| Output | Description |
|--------|-------------|
| `waf_id` | Identifier of the created WAF (ARN, resource ID, etc.) |
| `log_destination` | Final log destination (S3/GCS/Bucket, etc.) |
| `baseline_rule_set_version` | Effective baseline version deployed |

### Reference Implementation

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "waf" {
  source  = "git::ssh://git@github.com/org/terraform-modules.git//waf"
  provider = var.provider

  baseline_rule_set_version = var.baseline_rule_set_version
  managed_rule_sets         = var.managed_rule_sets
  custom_rules              = var.custom_rules
  exception_rules           = var.exception_rules
  exception_default_ttl_hours = var.exception_default_ttl_hours

  rate_limit   = var.rate_limit
  allowed_ip_cidrs = var.allowed_ip_cidrs

  logging_endpoint   = var.logging_endpoint
  enable_logging     = var.enable_logging
  metrics_namespace  = var.metrics_namespace

  block_override   = var.block_override
  tags             = var.tags
}

# Example exception rule (time-boxed to 48 hours)
locals {
  emergency_exceptions = [
    {
      rule_id    = "SQLi-TeamService-123"
      action     = "count"   # switch from block to count
      reason     = "false positives on search endpoint"
      ttl_hours  = 48
    }
  ]
}

module "service_waf" {
  source = module.waf.source

  exception_rules = local.emergency_exceptions
  # other variables omitted for brevity
}
```

---

## 4 ❗ Ownership Boundaries & Policy

| Area | Security Platform Team | Product Teams |
|------|------------------------|---------------|
| Module development & versioning | ✅ | ⬜ |
| Baseline rules (OWASP, managed bots) | ✅ | ⬜ |
| Rule tuning / custom overrides | 🔶 Review only | ✅ Implement |
| CI/CD integration & tests | ✅ Template | ✅ Consume |
| Monitoring & alerting | ✅ Central dashboards | 🔶 Respond to service-specific alerts |
| Incident response (WAF bypass) | ✅ Facilitate | ✅ Execute with approval |

*Legend: ✅ = Primary ownership, 🔶 = Shared*

**Policy Statements**  
1. Security Platform **owns and maintains** the baseline WAF rulesets.  
2. Product teams may **add or modify** application-specific rules via `custom_rules` or `exception_rules`, but baseline rules cannot be altered without Security approval.  
3. Security Platform **will not** directly deploy application-level WAF rules.  
4. All rule changes **must** go through Git-based workflow with mandatory peer review.  
5. Automated scanners validate rules against:  
   * Baseline coverage  
   * No wildcard disables  
   * Proper tagging (`owner`, `jira-ticket`, `expiry`)

---

## 5 🔐 CSPM (Wiz) Alignment

| Integration Point | Benefit |
|-------------------|---------|
| **Asset Inventory Sync** | Map Wiz-discovered public endpoints to WAF coverage gaps. |
| **Policy Correlation** | Alert when high-risk CVEs are exploitable *and* WAF rule is missing/disabled. |
| **IaC Drift Detection** | Compare deployed WAF state against Terraform plan; trigger drift alerts. |
| **Unified Dashboard** | Consolidated risk view: Wiz misconfigurations + WAF attack telemetry. |

---

## 6 📈 Success Metrics & KPIs

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| Internet-facing services protected by the new WAF | 100 % by end of Pilot Roll-out (Q4) | Asset inventory vs. WAF coverage report |
| Mean time for a team to deploy baseline WAF via Terraform | < 2 hours | CI pipeline timestamps |
| False-positive rate in production | < 0.01 % of total requests | WAF log analysis & customer tickets |
| Latency introduced by WAF | < 10 ms P95 | Synthetic monitoring |
| Rule change lead time (code merge ➜ deploy) | < 1 business day | Git & pipeline metrics |
| Critical Wiz findings without corresponding WAF rule | 0 | Automated correlation job |

---

## 7 ⚠️ Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Vendor lock-in limits future flexibility | Medium | Medium | Favor standards-based APIs & exportable configs; 1-year renewal clause |
| High latency or availability issues | High | Low | Include stringent SLA & PoC latency tests |
| False positives block legitimate traffic | High | Medium | Canary mode, staged roll-outs, automated regression tests |
| Incomplete team adoption | Medium | Medium | Provide self-service templates, office hours, and executive mandate |
| Cost overrun due to unoptimized rules | Medium | Low | Enable request-based cost dashboards and budget alerts |

---

## 8 🔗 Assumptions & Dependencies

1. F5 WAF appliances fully decommissioned by **Q2**.
2. Centralized log pipeline (Splunk) can ingest WAF logs at required volume.
3. Network ingress architecture allows insertion of SaaS or cloud-native WAF without additional hardware.
4. Budget approved in **FY24** security roadmap.
5. Engineering teams already use Terraform ≥ 1.5 and GitHub Actions for deployments.
6. Wiz API access tokens available for automated correlation jobs.


