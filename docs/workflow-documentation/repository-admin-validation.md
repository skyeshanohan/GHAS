# Repository Admin Access Validation Workflow Documentation

## Overview

The Repository Admin Access Validation workflow ensures compliance with the principle of least privilege by validating that repositories use team-based admin access rather than granting admin permissions directly to individual users. This workflow supports HITRUST, FedRAMP, and HIPAA requirements for access control and segregation of duties.

## Business Context

### Purpose
This workflow addresses compliance requirements for:
- **Access Control**: Ensuring only authorized personnel have administrative access
- **Segregation of Duties**: Preventing single points of failure in access management
- **Audit Trail**: Maintaining records of who has administrative access and why
- **Risk Mitigation**: Reducing the risk of unauthorized or excessive privileges

### Compliance Standards Addressed

#### HITRUST CSF
- **AC.1.020**: Privileged Access Management
- **AC.2.002**: Account Management Controls

#### FedRAMP
- **AC-6**: Least Privilege
- **AC-2**: Account Management
- **AC-3**: Access Enforcement

#### HIPAA
- **164.308(a)(3)**: Administrative Safeguards - Assigned Security Responsibility
- **164.308(a)(4)**: Administrative Safeguards - Information Access Management

### Business Impact
- **Compliance Assurance**: Meets regulatory requirements for access controls
- **Security Posture**: Reduces attack surface through controlled access
- **Operational Efficiency**: Standardizes access management through teams
- **Audit Readiness**: Provides clear documentation of access patterns

## Technical Architecture

### Workflow Components
```
Repository Admin Access Validation
├── User & Repository Discovery
├── Individual Admin Access Detection
├── Team Admin Access Analysis
├── Organization-Level Admin Review
├── Compliance Report Generation
├── Remediation Actions (Optional)
└── Dashboard & Notification Updates
```

### Processing Flow
1. **Discovery Phase**: Inventory repositories and user access
2. **Violation Detection**: Identify individual user admin access
3. **Team Analysis**: Validate team-based access patterns
4. **Organization Review**: Analyze org-level admin patterns
5. **Risk Assessment**: Categorize findings by risk level
6. **Remediation**: Execute appropriate remediation actions
7. **Reporting**: Generate compliance reports and dashboards

## Implementation Guide

### Prerequisites

#### Required Permissions
```yaml
# GitHub Token/App Permissions
permissions:
  contents: read
  members: read
  administration: read
  repository-projects: read
  issues: write
  metadata: read
```

#### Organization Setup
- GitHub Teams configured for repository management
- Organization members properly classified
- Admin access policies defined

### Step 1: Pre-Implementation Planning

#### 1.1 Define Team Structure
```bash
# Create admin teams for repositories
gh api orgs/$ORG/teams \
  --method POST \
  --field name="repo-admins-core" \
  --field description="Core repository administrators" \
  --field privacy="closed"

# Example team naming convention:
# - repo-admins-{product}
# - security-admins
# - platform-admins
```

#### 1.2 Document Current State
```bash
# Audit current admin access
gh api graphql -f query='
query($org: String!) {
  organization(login: $org) {
    repositories(first: 100) {
      nodes {
        name
        collaborators(affiliation: DIRECT, first: 100) {
          nodes {
            login
            permission
          }
        }
      }
    }
  }
}' -f org=$ORG_NAME > current_admin_access.json
```

### Step 2: Deploy the Workflow

#### 2.1 Copy and Configure Workflow
```bash
# Deploy workflow file
cp docs/workflows/repository-admin-validation.yml .github/workflows/

# Set organization variables
gh variable set ADMIN_REMEDIATION_MODE --value "report_only" --org $ORG_NAME
gh variable set ADMIN_NOTIFICATION_TEAM --value "@security-team" --org $ORG_NAME
```

#### 2.2 Configure Remediation Options
```yaml
# In workflow file, configure remediation modes
env:
  REMEDIATION_MODE: ${{ github.event.inputs.remediation_mode || 'report_only' }}
  # Options: report_only, create_issues, auto_remediate, notify_teams
```

### Step 3: Testing and Validation

#### 3.1 Initial Test Run
```bash
# Run with safe settings first
gh workflow run repository-admin-validation.yml \
  --field remediation_mode=report_only \
  --field include_archived=false
```

#### 3.2 Validate Results
```bash
# Check workflow outputs
gh run list --workflow=repository-admin-validation.yml
gh run view $RUN_ID --log

# Download compliance report
gh run download $RUN_ID --name admin-access-compliance-report
```

## Configuration Options

### Workflow Inputs

| Input | Description | Default | Options |
|-------|-------------|---------|---------|
| `remediation_mode` | Action to take for violations | `report_only` | `report_only`, `create_issues`, `auto_remediate`, `notify_only` |
| `include_archived` | Include archived repositories | `false` | `true`, `false` |

### Remediation Modes

#### 1. Report Only (`report_only`)
- Generates compliance reports
- No corrective action taken
- Safe for initial assessment

#### 2. Create Issues (`create_issues`)
- Creates GitHub issues for violations
- Assigns to appropriate teams
- Includes remediation instructions

#### 3. Auto Remediate (`auto_remediate`)
- **⚠️ Use with caution**
- Automatically removes individual admin access
- Converts admin to push permissions
- Requires extensive testing before use

#### 4. Notify Only (`notify_teams`)
- Sends notifications without creating issues
- Uses Slack/Teams webhooks
- Lightweight notification approach

## Security Controls Validated

### Individual User Admin Access
```yaml
Violation Detection:
- Users with direct admin access to repositories
- Admin access without corresponding team membership
- External collaborators with admin permissions
- Service accounts with excessive privileges
```

### Team Admin Access Patterns
```yaml
Pattern Analysis:
- Repositories without admin teams
- Teams with single members (defeats purpose)
- Excessive number of admin teams per repository
- Teams with inappropriate access levels
```

### Organization-Level Admin Access
```yaml
Organization Review:
- Number of organization owners
- Owners without MFA enabled
- Inactive organization owners
- Service account owner access
```

## Monitoring and Alerting

### Key Metrics

#### Compliance Metrics
- **Individual Admin Violations**: Target = 0
- **Team Coverage**: Target = 100% of repositories
- **Response Time**: Target < 24 hours for high-risk violations

#### Operational Metrics
- **False Positive Rate**: Target < 5%
- **Remediation Success Rate**: Target > 95%
- **Time to Resolution**: Target < 48 hours

### Alert Thresholds

| Severity | Condition | Response Time |
|----------|-----------|---------------|
| **Critical** | Organization owner without MFA | Immediate |
| **High** | Individual user admin access | 4 hours |
| **Medium** | Single-member admin teams | 24 hours |
| **Low** | Excessive admin teams | 1 week |

## Remediation Procedures

### Manual Remediation Steps

#### 1. Remove Individual Admin Access
```bash
# Step 1: Create appropriate admin team
gh api orgs/$ORG/teams \
  --method POST \
  --field name="$REPO-admins" \
  --field description="Admin team for $REPO repository"

# Step 2: Add team to repository
gh api repos/$ORG/$REPO/teams/$TEAM \
  --method PUT \
  --field permission=admin

# Step 3: Add user to team
gh api orgs/$ORG/teams/$TEAM/memberships/$USER \
  --method PUT \
  --field role=member

# Step 4: Remove direct repository access
gh api repos/$ORG/$REPO/collaborators/$USER \
  --method DELETE
```

#### 2. Fix Team Access Issues
```bash
# Add additional members to single-member teams
gh api orgs/$ORG/teams/$TEAM/memberships/$ADDITIONAL_USER \
  --method PUT \
  --field role=member

# Consolidate excessive admin teams
# (Manual process - requires business logic)
```

### Automated Remediation

#### Safe Auto-Remediation
```yaml
# Conditions for safe auto-remediation:
criteria:
  - User is not organization owner
  - User has zero recent activity
  - Alternative team access exists
  - User explicitly marked for removal
```

#### Auto-Remediation Script
```bash
#!/bin/bash
# scripts/remediation/fix-repository-admin-access.sh

REPO=$1
VIOLATION_TYPE=$2

case $VIOLATION_TYPE in
  "individual_user_admin")
    # Implementation for safe removal
    ;;
  "excessive_teams")
    # Implementation for team consolidation
    ;;
esac
```

## Troubleshooting

### Common Issues

#### 1. Permission Errors
```bash
# Error: Cannot access team membership
# Cause: Insufficient permissions
# Solution: Verify token has 'read:org' scope

gh auth refresh --scopes read:org,repo,admin:org
```

#### 2. False Positives for Service Accounts
```bash
# Issue: Service accounts flagged as individual users
# Solution: Add exception list

SERVICE_ACCOUNTS=("github-actions[bot]" "dependabot[bot]" "security-scanner")
if [[ " ${SERVICE_ACCOUNTS[@]} " =~ " ${USERNAME} " ]]; then
  echo "Skipping service account: $USERNAME"
  continue
fi
```

#### 3. Team Membership Privacy Issues
```bash
# Issue: Cannot read private team memberships
# Solution: Use organization-level token or adjust team visibility

# Make team visible
gh api orgs/$ORG/teams/$TEAM \
  --method PATCH \
  --field privacy=closed  # 'closed' instead of 'secret'
```

### Debugging Commands

```bash
# Check user's repository permissions
gh api repos/$ORG/$REPO/collaborators/$USER

# List teams with access to repository
gh api repos/$ORG/$REPO/teams

# Check team membership
gh api orgs/$ORG/teams/$TEAM/members

# Verify organization membership
gh api orgs/$ORG/members/$USER
```

## Compliance Reporting

### Report Structure
```json
{
  "access_review_report": {
    "review_metadata": {
      "review_id": "UAR-202401-001",
      "generated_at": "2024-01-15T10:30:00Z"
    },
    "executive_summary": {
      "total_repositories": 150,
      "repositories_with_violations": 12,
      "compliance_percentage": 92
    },
    "detailed_findings": {
      "individual_user_violations": [...],
      "team_access_issues": [...],
      "organization_admin_analysis": [...]
    }
  }
}
```

### Audit Documentation
- **Violation Records**: Detailed logs of all violations
- **Remediation Actions**: Complete audit trail of fixes
- **Access Changes**: Log of all admin access modifications
- **Exception Approvals**: Documentation of approved exceptions

## Integration Points

### External Systems

#### SIEM Integration
```bash
# Forward admin access logs to SIEM
curl -X POST $SIEM_ENDPOINT \
  -H "Content-Type: application/json" \
  -d "@admin_violations.json"
```

#### Identity Provider Integration
```bash
# Sync with corporate directory
# Map GitHub teams to AD/LDAP groups
gh api orgs/$ORG/teams/$TEAM/members \
  --jq '.[] | .login' | \
  while read user; do
    # Validate against corporate directory
    ldapsearch -x -b "dc=company,dc=com" "(samAccountName=$user)"
  done
```

### GitHub Enterprise Features
- **SAML SSO**: Leverage for team membership
- **Enterprise Audit Log**: Central logging
- **Organization Policies**: Enforce baseline access
- **GitHub Apps**: Event-driven validation

## Maintenance Tasks

### Daily
- Review admin violation dashboard
- Process remediation requests
- Monitor notification channels

### Weekly
- Analyze admin access trends
- Review exception requests
- Update team membership as needed

### Monthly
- Audit organization owners
- Review team structure effectiveness
- Update access control policies

### Quarterly
- Comprehensive access review
- Policy effectiveness assessment
- Update compliance documentation

## Emergency Procedures

### Critical Access Violation
1. **Immediate Response** (< 1 hour)
   - Identify scope of violation
   - Assess security impact
   - Implement emergency access controls

2. **Investigation** (< 4 hours)
   - Determine root cause
   - Check for unauthorized changes
   - Document findings

3. **Remediation** (< 24 hours)
   - Remove inappropriate access
   - Implement proper controls
   - Verify compliance restoration

4. **Follow-up** (< 1 week)
   - Process improvement
   - Policy updates
   - Training if needed

## Performance Optimization

### Large Organization Tuning
```yaml
# For organizations with 1000+ repositories
strategy:
  matrix:
    batch: ${{ fromJson(needs.inventory.outputs.repository-matrix) }}
  fail-fast: false
  max-parallel: 15  # Increase from default 10

# Batch size optimization
BATCH_SIZE=25  # Reduce from 50 for better performance
```

### API Rate Limit Management
```bash
# Implement exponential backoff
for i in {1..3}; do
  if gh api repos/$ORG/$REPO/collaborators; then
    break
  else
    sleep $((2**i))
  fi
done
```

## Support and Escalation

### Support Tiers

#### Tier 1: Security Operations
- **Scope**: Standard violations, routine remediation
- **Response Time**: 4 hours
- **Contact**: security-ops@company.com

#### Tier 2: Security Engineering
- **Scope**: Complex violations, policy exceptions
- **Response Time**: 8 hours
- **Contact**: security-engineering@company.com

#### Tier 3: Architecture Team
- **Scope**: Workflow modifications, integration issues
- **Response Time**: 24 hours
- **Contact**: platform-architecture@company.com

### Escalation Matrix

| Violation Type | Severity | Initial Owner | Escalation Path |
|----------------|----------|---------------|-----------------|
| Individual Admin Access | High | Security Ops | → Security Engineering → CISO |
| Missing Admin Teams | Medium | Security Ops | → Security Engineering |
| Excessive Teams | Low | Repository Owner | → Security Ops |
| Org Owner Issues | Critical | CISO | → C-Suite |

---

## Appendix

### A. Team Naming Conventions
```yaml
Recommended Team Names:
- "{product}-admins": Product-specific admin team
- "security-admins": Security team with broad access
- "platform-admins": Infrastructure and platform team
- "compliance-admins": Compliance and audit team
```

### B. Exception Process
```yaml
Exception Request Process:
1. Submit request via GitHub issue
2. Business justification required
3. Security team review
4. Time-bound approval (max 90 days)
5. Regular review and revalidation
```

### C. API Rate Limits and Quotas
```yaml
GitHub API Limits:
- Authenticated requests: 5,000/hour
- Repository collaboration: 1,000/hour
- Team management: 1,000/hour
- Organization membership: 1,000/hour

Optimization Strategies:
- Use GraphQL for complex queries
- Implement caching for static data
- Batch operations where possible
- Use conditional requests (ETag)
``` 