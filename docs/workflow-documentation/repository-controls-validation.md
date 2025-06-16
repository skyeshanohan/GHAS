# Repository Controls Validation Workflow Documentation

## Overview

The Repository Controls Validation workflow provides automated compliance validation across all repositories in a GitHub Enterprise organization, ensuring that required security controls are enabled and properly configured according to HITRUST CSF, FedRAMP, and HIPAA standards.

## Business Context

### Purpose
This workflow addresses the compliance requirement to continuously monitor and validate that all repositories maintain required security configurations. It supports audit requirements for demonstrating consistent application of security controls across the enterprise.

### Compliance Standards Addressed
- **HITRUST CSF**: Controls related to system configuration management and security baseline
- **FedRAMP**: Configuration management (CM-2, CM-3) and system security controls
- **HIPAA**: Technical safeguards for information systems containing PHI

### Business Value
- **Continuous Compliance**: Automated validation reduces manual audit overhead
- **Risk Reduction**: Early detection of configuration drift prevents security gaps
- **Audit Readiness**: Comprehensive reporting supports compliance audits
- **Operational Efficiency**: Automated remediation reduces manual intervention needs

## Technical Architecture

### Workflow Structure
```
Repository Controls Validation
├── Repository Inventory (Discovery Phase)
├── Parallel Validation (Batch Processing)
│   ├── Security Features Validation
│   ├── Branch Protection Validation
│   └── Repository Settings Validation
├── Results Consolidation
├── Remediation Actions (Optional)
└── Reporting & Dashboard Updates
```

### Key Components

#### 1. Repository Inventory Job
- **Purpose**: Discovers and categorizes all repositories for validation
- **Processing**: Generates matrix for parallel processing
- **Output**: Repository inventory artifact

#### 2. Validation Jobs (Parallel)
- **Strategy**: Matrix-based parallel execution (batches of 50 repositories)
- **Max Parallel**: 10 concurrent jobs
- **Timeout**: 30 minutes per batch

#### 3. Consolidation Job
- **Purpose**: Aggregates results from all parallel jobs
- **Processing**: Generates compliance scores and comprehensive reports
- **Dependencies**: Waits for all validation jobs to complete

## Implementation Guide

### Prerequisites

#### GitHub Permissions Required
```yaml
# Minimum permissions for service account/token
permissions:
  contents: read
  issues: write
  repository-projects: read
  metadata: read
  administration: read  # For security settings
```

#### Organization Settings
- GitHub Advanced Security enabled
- Secret scanning available
- Dependency review enabled
- Organization-level security policies configured

### Step 1: Deploy the Workflow

1. **Copy Workflow File**
   ```bash
   cp docs/workflows/repository-controls-validation.yml .github/workflows/
   ```

2. **Configure Organization Variables**
   ```bash
   # Set organization-level variables
   gh variable set COMPLIANCE_LEVEL --value "standard" --org $ORG_NAME
   gh variable set NOTIFICATION_WEBHOOK --value "$SLACK_WEBHOOK_URL" --org $ORG_NAME
   gh variable set COMPLIANCE_TEAM --value "@compliance-team" --org $ORG_NAME
   ```

3. **Configure Secrets**
   ```bash
   # If using external notifications
   gh secret set SLACK_WEBHOOK_URL --body "$WEBHOOK_URL" --org $ORG_NAME
   gh secret set TEAMS_WEBHOOK_URL --body "$TEAMS_URL" --org $ORG_NAME
   ```

### Step 2: Customize Configuration

#### Compliance Levels Configuration
```yaml
# In the workflow file, customize compliance levels
case "${{ env.COMPLIANCE_LEVEL }}" in
  "minimal")
    REQUIRED_FEATURES='["has_vulnerability_alerts"]'
    ;;
  "standard")
    REQUIRED_FEATURES='["has_vulnerability_alerts", "security_and_analysis.secret_scanning", "security_and_analysis.automated_security_fixes"]'
    ;;
  "strict")
    REQUIRED_FEATURES='["has_vulnerability_alerts", "security_and_analysis.secret_scanning", "security_and_analysis.secret_scanning_push_protection", "security_and_analysis.automated_security_fixes", "security_and_analysis.code_scanning_default_setup"]'
    ;;
  "maximum")
    REQUIRED_FEATURES='["has_vulnerability_alerts", "security_and_analysis.secret_scanning", "security_and_analysis.secret_scanning_push_protection", "security_and_analysis.automated_security_fixes", "security_and_analysis.code_scanning_default_setup", "security_and_analysis.private_vulnerability_reporting"]'
    ;;
esac
```

#### Branch Protection Requirements
```yaml
# Customize branch protection requirements
REQUIRED_PROTECTIONS='{
  "required_status_checks": true,
  "enforce_admins": true,
  "required_pull_request_reviews": true,
  "required_approving_review_count": 2,        # Adjust as needed
  "dismiss_stale_reviews": true,
  "require_code_owner_reviews": true           # Set to false if not using CODEOWNERS
}'
```

### Step 3: Configure Notifications

#### Slack Integration
```bash
# Create Slack webhook
# In Slack: Apps → Incoming Webhooks → Add to Slack
# Copy webhook URL to GitHub secrets

# Test notification
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Repository Controls Validation Test"}' \
  $SLACK_WEBHOOK_URL
```

#### Teams Integration
```bash
# Create Teams webhook
# In Teams: Channel → Connectors → Incoming Webhook
# Copy webhook URL to GitHub secrets
```

### Step 4: Testing and Validation

#### Initial Test Run
```bash
# Trigger manual workflow run
gh workflow run repository-controls-validation.yml \
  --field repository_filter=private \
  --field compliance_level=minimal \
  --field create_issues=false
```

#### Validate Outputs
1. Check workflow run logs
2. Download and review artifacts
3. Verify compliance dashboard issue creation
4. Test notification delivery

## Configuration Options

### Workflow Inputs

| Input | Description | Default | Options |
|-------|-------------|---------|---------|
| `repository_filter` | Filter repositories to validate | `all` | `all`, `private`, `public`, `archived` |
| `compliance_level` | Validation strictness level | `standard` | `minimal`, `standard`, `strict`, `maximum` |
| `create_issues` | Create GitHub issues for violations | `true` | `true`, `false` |

### Environment Variables

| Variable | Purpose | Required | Example |
|----------|---------|----------|---------|
| `REPO_FILTER` | Repository filtering logic | Yes | `all` |
| `COMPLIANCE_LEVEL` | Validation requirements | Yes | `standard` |
| `CREATE_ISSUES` | Issue creation flag | Yes | `true` |

### Organization Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `COMPLIANCE_LEVEL` | Default compliance level | `standard` |
| `NOTIFICATION_WEBHOOK` | Default notification URL | `https://hooks.slack.com/...` |
| `COMPLIANCE_TEAM` | Default assignee team | `@security-team` |

## Security Controls Validated

### Security Features (by Compliance Level)

#### Minimal Level
- Vulnerability alerts enabled

#### Standard Level
- Vulnerability alerts enabled
- Secret scanning enabled
- Automated security fixes enabled

#### Strict Level
- All standard features plus:
- Secret scanning push protection
- Code scanning default setup

#### Maximum Level
- All strict features plus:
- Private vulnerability reporting

### Branch Protection Rules
- Required status checks
- Admin enforcement
- Required pull request reviews
- Minimum approving review count
- Dismiss stale reviews
- Code owner reviews (if applicable)

### Repository Settings
- Repository visibility (private for sensitive data)
- Archive status with maintained security
- Fork restrictions

## Monitoring and Alerting

### Success Metrics
- **Compliance Percentage**: Target ≥95%
- **Violation Response Time**: <4 hours for critical
- **False Positive Rate**: <5%

### Alert Conditions
- **Critical**: Any repository without basic security features
- **High**: Branch protection violations
- **Medium**: Repository visibility concerns
- **Low**: Configuration recommendations

### Dashboard Metrics
```yaml
Key Performance Indicators:
- Total repositories validated
- Compliance percentage by standard
- Violations by severity
- Time to remediation
- Recurring violations
```

## Troubleshooting

### Common Issues

#### 1. Permission Errors
```bash
# Error: Resource not accessible by integration
# Solution: Verify token permissions
gh auth status
gh api user  # Test API access
```

#### 2. Rate Limiting
```bash
# Error: API rate limit exceeded
# Solution: Implement exponential backoff or reduce batch size
# Modify workflow: reduce matrix batch size from 50 to 25
```

#### 3. Large Organization Performance
```bash
# Issue: Workflow timeouts with 1000+ repositories
# Solution: Increase max-parallel and reduce batch size
strategy:
  matrix:
    batch: ${{ fromJson(needs.repository-inventory.outputs.repository-matrix) }}
  fail-fast: false
  max-parallel: 20  # Increase from 10
```

#### 4. False Positives
```bash
# Issue: Archived repositories flagged incorrectly
# Solution: Adjust filtering logic
REPO_FILTER='.[] | select(.archived == false or (.archived == true and .pushed_at > (now - 86400*30 | strftime("%Y-%m-%d"))))'
```

### Debugging Steps

1. **Check Workflow Logs**
   ```bash
   gh run list --workflow=repository-controls-validation.yml
   gh run view $RUN_ID --log
   ```

2. **Validate Repository Data**
   ```bash
   # Test repository API access
   gh api repos/$ORG/$REPO
   gh api repos/$ORG/$REPO/branches/main/protection
   ```

3. **Test Notification Endpoints**
   ```bash
   # Test Slack webhook
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test message"}' \
     $SLACK_WEBHOOK_URL
   ```

## Maintenance

### Regular Tasks

#### Weekly
- Review compliance dashboard
- Analyze violation trends
- Update exception lists if needed

#### Monthly
- Review and update compliance levels
- Analyze performance metrics
- Update documentation

#### Quarterly
- Review security control requirements
- Update compliance standards mapping
- Audit workflow permissions

### Updates and Changes

#### Adding New Security Controls
1. Update `REQUIRED_FEATURES` arrays
2. Add validation logic in appropriate job
3. Update compliance scoring
4. Test with representative repositories

#### Modifying Compliance Levels
1. Update switch statement in workflow
2. Document changes in this file
3. Communicate changes to compliance team
4. Run test validation

## Integration Points

### External Systems
- **SIEM Integration**: Forward violation logs
- **Ticketing Systems**: Create tickets for violations
- **Compliance Platforms**: Export reports
- **Monitoring Tools**: Send metrics

### GitHub Enterprise Features
- **GitHub Advanced Security**: Leverages security scanning
- **Organization Policies**: Enforces baseline configurations
- **Enterprise Audit Log**: Provides audit trail
- **GitHub Apps**: Can be triggered by app events

## Compliance Reporting

### Report Artifacts
- `repository_controls_compliance_report.json`: Comprehensive validation results
- `batch_summary.json`: Per-batch processing summaries
- `validation-results/`: Detailed violation data

### Report Structure
```json
{
  "validation_summary": {
    "total_repositories_validated": 150,
    "compliance_percentage": 94,
    "total_violations_found": 12
  },
  "violations_by_repository": [...],
  "violations_by_standard": {
    "hitrust": 8,
    "fedramp": 6,
    "hipaa": 4
  }
}
```

### Audit Trail
- All workflow runs logged with timestamps
- Violation details stored for 90 days
- Remediation actions tracked
- Access to reports controlled via GitHub permissions

## Support and Escalation

### Level 1 Support (Operations Team)
- Monitor dashboard for violations
- Execute standard remediation procedures
- Escalate persistent issues

### Level 2 Support (Security Team)
- Review complex violations
- Approve exception requests
- Update security policies

### Level 3 Support (Engineering Team)
- Modify workflow logic
- Integrate new security controls
- Performance optimization

### Escalation Contacts
- **Security Team**: security@company.com
- **Compliance Team**: compliance@company.com
- **Engineering Team**: engineering@company.com

## Change Management

### Workflow Changes
1. Create feature branch
2. Update workflow and documentation
3. Test in non-production environment
4. Security team review and approval
5. Deploy to production

### Emergency Changes
1. Immediate deployment with approval
2. Document changes within 24 hours
3. Post-incident review within 1 week

---

## Appendix

### A. Sample Configuration Files

#### A.1 Organization Variables
```yaml
# .github/organization-variables.yml
COMPLIANCE_LEVEL: "standard"
NOTIFICATION_WEBHOOK: "https://hooks.slack.com/services/..."
COMPLIANCE_TEAM: "@security-team"
REPOSITORY_FILTER_DEFAULT: "all"
```

#### A.2 Exception Repositories
```yaml
# exceptions.yml
repositories:
  - name: "legacy-system"
    reason: "End-of-life system, exception approved"
    expires: "2024-12-31"
  - name: "demo-repo"
    reason: "Demo repository, no sensitive data"
    expires: "2025-06-30"
```

### B. API Rate Limits

| API Endpoint | Rate Limit | Batch Size Impact |
|--------------|------------|-------------------|
| Repository List | 5000/hour | Use pagination |
| Repository Details | 5000/hour | Batch processing |
| Branch Protection | 5000/hour | Critical for validation |

### C. Performance Benchmarks

| Organization Size | Processing Time | Recommended Settings |
|-------------------|-----------------|---------------------|
| <100 repos | 2-5 minutes | Default settings |
| 100-500 repos | 5-15 minutes | max-parallel: 15 |
| 500-1000 repos | 15-30 minutes | max-parallel: 20, batch size: 25 |
| >1000 repos | 30+ minutes | max-parallel: 25, batch size: 20 | 