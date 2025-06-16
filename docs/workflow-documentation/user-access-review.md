# Quarterly User Access Review Workflow Documentation

## Overview

The Quarterly User Access Review workflow provides comprehensive, automated assessment of user access patterns across GitHub Enterprise organizations. This workflow ensures compliance with access control requirements from HITRUST CSF, FedRAMP, and HIPAA by systematically reviewing user permissions, activity patterns, and access appropriateness.

## Business Context

### Purpose
Regular access reviews are fundamental to maintaining security posture and regulatory compliance. This workflow addresses critical business needs:
- **Regulatory Compliance**: Meets quarterly access review requirements for multiple standards
- **Risk Mitigation**: Identifies and addresses inappropriate or excessive access privileges
- **Operational Efficiency**: Automates time-intensive manual review processes
- **Audit Readiness**: Provides comprehensive documentation for compliance audits

### Regulatory Requirements

#### HITRUST CSF
- **AC.1.020**: Privileged Access Management
- **AC.2.002**: Account Management Controls
- **AC.1.002**: Access Control Policy and Procedures

#### FedRAMP
- **AC-2**: Account Management
- **AC-3**: Access Enforcement
- **AC-6**: Least Privilege
- **AU-9**: Protection of Audit Information

#### HIPAA
- **164.308(a)(3)**: Administrative Safeguards - Assigned Security Responsibility
- **164.308(a)(4)**: Administrative Safeguards - Information Access Management
- **164.312(a)(2)(i)**: Technical Safeguards - Unique User Identification

### Business Value Proposition
- **Compliance Assurance**: Demonstrates ongoing access control governance
- **Security Posture**: Reduces attack surface through access optimization
- **Operational Insights**: Provides visibility into access patterns and usage
- **Cost Optimization**: Identifies unnecessary licenses and access rights

## Technical Architecture

### Workflow Architecture
```
Quarterly User Access Review
├── Review Initialization
├── User Inventory Collection
│   ├── Organization Members
│   ├── External Collaborators
│   └── Team Memberships
├── Activity Analysis
│   ├── User Activity Patterns
│   ├── Access Pattern Analysis
│   └── Risk Assessment
├── Compliance Assessment
├── Review Task Generation
├── Automated Remediation (Optional)
└── Comprehensive Reporting
```

### Data Collection Strategy
- **Multi-Source Aggregation**: Combines user data, activity logs, and access patterns
- **Historical Analysis**: Examines activity over configurable review periods
- **Risk-Based Classification**: Categorizes users by risk level and review requirements
- **Scalable Processing**: Handles large organizations with thousands of users

## Implementation Guide

### Phase 1: Planning and Preparation

#### 1.1 Define Review Scope
```yaml
Review Configuration:
- Review Period: 1, 3, 6, or 12 months
- Review Type: comprehensive, privileged_only, inactive_only, external_collaborators
- Auto-Remediation: Enabled/disabled based on organizational policy
- Escalation Thresholds: Define risk levels requiring immediate attention
```

#### 1.2 Establish Baseline
```bash
# Conduct initial user inventory
gh api orgs/$ORG/members --paginate > baseline_members.json
gh api orgs/$ORG/outside_collaborators --paginate > baseline_collaborators.json

# Analyze current state
TOTAL_MEMBERS=$(jq 'length' baseline_members.json)
TOTAL_COLLABORATORS=$(jq 'length' baseline_collaborators.json)
echo "Baseline: $TOTAL_MEMBERS members, $TOTAL_COLLABORATORS external collaborators"
```

#### 1.3 Configure Review Teams
```bash
# Create review teams
gh api orgs/$ORG/teams \
  --method POST \
  --field name="access-review-committee" \
  --field description="Quarterly access review team"

# Assign review responsibilities
gh api orgs/$ORG/teams/access-review-committee/memberships/$REVIEWER \
  --method PUT \
  --field role=maintainer
```

### Phase 2: Workflow Deployment

#### 2.1 Deploy Workflow
```bash
# Copy workflow file
cp docs/workflows/user-access-review.yml .github/workflows/

# Set organization variables
gh variable set ACCESS_REVIEW_PERIOD --value "3" --org $ORG  # 3 months
gh variable set ACCESS_REVIEW_COMMITTEE --value "@access-review-committee" --org $ORG
gh variable set AUTO_REMEDIATION_ENABLED --value "false" --org $ORG  # Start with manual review
```

#### 2.2 Configure Scheduling
```yaml
# Workflow schedule configuration
schedule:
  # Quarterly: 1st day of Jan, Apr, Jul, Oct at 6 AM UTC
  - cron: '0 6 1 1,4,7,10 *'

# Manual trigger options
workflow_dispatch:
  inputs:
    review_type: [comprehensive, privileged_only, inactive_only, external_collaborators]
    review_period: [1, 3, 6, 12]  # months
    auto_remediate: [true, false]
```

### Phase 3: Configuration and Customization

#### 3.1 Define Activity Thresholds
```yaml
# Activity classification thresholds
activity_thresholds:
  active: 
    events_per_period: 10
    last_activity_days: 30
  low_activity:
    events_per_period: 1-9
    last_activity_days: 30-90
  inactive:
    events_per_period: 0
    last_activity_days: ">90"
```

#### 3.2 Risk Assessment Configuration
```yaml
# Risk level determination
risk_assessment:
  high_risk:
    - organization_owners with no recent activity
    - external_collaborators with admin access
    - users with excessive team memberships (>10)
  medium_risk:
    - inactive users with repository access
    - single-member team administrators
    - users without MFA enabled
  low_risk:
    - active users with appropriate access
    - read-only external collaborators
```

### Phase 4: Testing and Validation

#### 4.1 Test Review Process
```bash
# Execute test run with limited scope
gh workflow run user-access-review.yml \
  --field review_type=inactive_only \
  --field review_period=1 \
  --field auto_remediate=false
```

#### 4.2 Validate Outputs
```bash
# Check review execution
gh run list --workflow=user-access-review.yml
gh run view $RUN_ID --log

# Download review artifacts
gh run download $RUN_ID --name quarterly-access-review-final-UAR-$DATE
```

## Review Process Framework

### Stage 1: User Inventory Collection

#### Organization Members Analysis
```bash
# Collect comprehensive member data
gh api orgs/$ORG/members --paginate \
  --jq 'map({
    login: .login,
    id: .id,
    type: .type,
    site_admin: .site_admin,
    two_factor_authentication: .two_factor_authentication
  })' > organization_members.json
```

#### External Collaborators Assessment
```bash
# Analyze external access patterns
gh repo list $ORG --limit 1000 --json name | jq -r '.[].name' | \
while read repo; do
  gh api repos/$ORG/$repo/collaborators \
    --field affiliation=outside \
    --jq 'map({
      login: .login,
      repository: "'"$repo"'",
      permissions: .permissions,
      role_name: .role_name
    })'
done | jq -s 'add' > external_collaborators.json
```

#### Team Membership Analysis
```bash
# Collect team membership data
gh api orgs/$ORG/teams --paginate | jq -r '.[].slug' | \
while read team; do
  gh api orgs/$ORG/teams/$team/members \
    --jq 'map({
      login: .login,
      team: "'"$team"'",
      role: .role
    })'
done | jq -s 'add' > team_memberships.json
```

### Stage 2: Activity Pattern Analysis

#### User Activity Assessment
```yaml
Activity Metrics:
- Repository commits and contributions
- Pull request activity (created, reviewed, merged)
- Issue activity (created, commented, closed)
- Repository and organization events
- Authentication and access patterns

Analysis Period:
- Configurable: 1, 3, 6, or 12 months
- Default: 3 months (quarterly review)
- Historical comparison available
```

#### Risk Scoring Algorithm
```python
def calculate_user_risk_score(user_data):
    risk_score = 0
    
    # Inactivity risk
    if user_data['days_since_last_activity'] > 90:
        risk_score += 30
    elif user_data['days_since_last_activity'] > 30:
        risk_score += 15
    
    # Privilege risk
    if user_data['is_organization_owner']:
        risk_score += 25
    if user_data['admin_team_count'] > 0:
        risk_score += 15
    
    # Access pattern risk
    if user_data['external_collaborator_count'] > 5:
        risk_score += 20
    if user_data['team_membership_count'] > 10:
        risk_score += 10
    
    # Security posture risk
    if not user_data['two_factor_enabled']:
        risk_score += 20
    
    return min(risk_score, 100)  # Cap at 100
```

### Stage 3: Compliance Assessment

#### Access Appropriateness Review
```yaml
Review Criteria:
- Business justification for access levels
- Principle of least privilege adherence
- Segregation of duties compliance
- Time-bound access validation
- Role-based access control effectiveness

Validation Checkpoints:
- [ ] User access aligns with job responsibilities
- [ ] No excessive privileges identified
- [ ] Temporary access properly managed
- [ ] External access appropriately controlled
- [ ] Audit trail complete and accessible
```

#### Compliance Scoring
```yaml
Scoring Methodology:
Base Score: 100 points

Deductions:
- Inactive organization owners: -20 points each
- High-risk external collaborators: -10 points each
- Users without MFA: -5 points each
- Excessive team memberships: -3 points each
- Inactive users with admin access: -15 points each

Thresholds:
- Compliant: ≥90 points
- Mostly Compliant: 75-89 points
- Partially Compliant: 50-74 points
- Non-Compliant: <50 points
```

## Automated Review Tasks

### Review Task Generation

#### Individual User Reviews
```json
{
  "review_task_type": "user_access_review",
  "user": "john.doe",
  "risk_level": "medium",
  "review_items": [
    "Validate continued need for admin access to 'project-x' repository",
    "Review team memberships for business alignment",
    "Confirm user activity justifies current access level"
  ],
  "review_deadline": "2024-02-15",
  "assigned_reviewer": "manager@company.com"
}
```

#### External Collaborator Reviews
```json
{
  "review_task_type": "external_collaborator_review",
  "collaborator": "external.user@vendor.com",
  "repositories": ["repo-a", "repo-b"],
  "access_level": "admin",
  "risk_level": "high",
  "review_items": [
    "Validate ongoing business need for external access",
    "Confirm admin privileges are necessary",
    "Review and update access termination date"
  ],
  "business_justification_required": true
}
```

### Automated Remediation

#### Safe Auto-Remediation Criteria
```yaml
Automatic Actions (Low Risk):
- Remove access for users inactive >180 days (non-owners)
- Convert individual admin access to team-based access
- Remove external collaborators from archived repositories
- Disable access for users without MFA (after grace period)

Manual Review Required (High Risk):
- Organization owner access changes
- Admin access to production repositories
- External collaborator admin privileges
- Cross-functional team access patterns
```

#### Remediation Execution
```bash
#!/bin/bash
# Safe auto-remediation script

perform_safe_remediation() {
    local user=$1
    local action=$2
    local justification=$3
    
    case $action in
        "remove_inactive_user")
            if [[ $DAYS_INACTIVE -gt 180 && $IS_OWNER == "false" ]]; then
                gh api orgs/$ORG/members/$user --method DELETE
                log_remediation_action "$user" "$action" "$justification"
            fi
            ;;
        "convert_to_team_access")
            # Implementation for team-based access conversion
            ;;
        "remove_external_access")
            # Implementation for external collaborator removal
            ;;
    esac
}
```

## Monitoring and Reporting

### Real-Time Dashboards

#### Executive Dashboard
```yaml
Key Metrics:
- Total users under review
- Compliance percentage
- High-risk users identified
- Remediation actions completed
- Review completion rate

Visual Elements:
- Compliance score trending
- Risk level distribution
- Review progress tracking
- Exception approval status
```

#### Operational Dashboard
```yaml
Operational Metrics:
- Active review tasks
- Overdue reviews
- Escalated cases
- Auto-remediation statistics
- Reviewer workload distribution

Action Items:
- Review assignment queue
- Escalation notifications
- Remediation task tracking
- Compliance gap alerts
```

### Compliance Reporting

#### Quarterly Report Structure
```json
{
  "review_summary": {
    "review_id": "QAR-2024-Q1",
    "review_period": "2024-01-01 to 2024-03-31",
    "total_users_reviewed": 450,
    "compliance_score": 87,
    "high_risk_users": 12,
    "remediation_actions": 23
  },
  "detailed_findings": {
    "inactive_users": [...],
    "excessive_privileges": [...],
    "external_access_review": [...],
    "mfa_compliance": [...]
  },
  "compliance_attestation": {
    "standards_compliance": {
      "hitrust": "compliant",
      "fedramp": "mostly_compliant", 
      "hipaa": "compliant"
    },
    "sign_off": {
      "security_officer": "approved",
      "compliance_officer": "approved",
      "it_management": "pending"
    }
  }
}
```

## Integration Points

### HR System Integration

#### Employee Status Validation
```bash
# Integrate with HRIS for employment status
validate_employee_status() {
    local username=$1
    local hr_status=$(curl -s "$HR_API/employees/$username" | jq -r '.status')
    
    case $hr_status in
        "active")
            echo "Employment confirmed"
            ;;
        "terminated"|"inactive")
            echo "Employment ended - immediate access review required"
            trigger_immediate_review "$username"
            ;;
        "on_leave")
            echo "Employee on leave - access suspension recommended"
            ;;
    esac
}
```

#### Organizational Hierarchy
```bash
# Validate reporting relationships
validate_manager_approval() {
    local user=$1
    local manager=$(curl -s "$HR_API/employees/$user" | jq -r '.manager_email')
    
    # Cross-reference with GitHub access patterns
    if [[ "$manager" != "null" ]]; then
        echo "Manager approval required from: $manager"
        create_manager_review_task "$user" "$manager"
    fi
}
```

### Identity Provider Integration

#### SAML/SSO Validation
```bash
# Validate SSO group memberships
validate_sso_groups() {
    local username=$1
    local sso_groups=$(curl -s "$SSO_API/users/$username/groups" | jq -r '.groups[]')
    
    # Compare with GitHub team memberships
    local gh_teams=$(gh api orgs/$ORG/teams | jq -r --arg user "$username" '.[] | select(.members[] | .login == $user) | .name')
    
    # Identify discrepancies
    diff <(echo "$sso_groups" | sort) <(echo "$gh_teams" | sort)
}
```

### Compliance Platform Integration

#### Evidence Collection
```bash
# Export evidence for compliance platforms
export_compliance_evidence() {
    local review_id=$1
    
    # Package evidence
    zip -r "compliance_evidence_$review_id.zip" \
        access_review_report.json \
        user_inventory.json \
        remediation_log.json \
        sign_off_approvals.json
    
    # Upload to compliance platform
    curl -X POST "$COMPLIANCE_PLATFORM/evidence" \
        -H "Authorization: Bearer $COMPLIANCE_TOKEN" \
        -F "file=@compliance_evidence_$review_id.zip"
}
```

## Troubleshooting and Maintenance

### Common Issues

#### 1. Large Organization Performance
```yaml
Problem: Workflow timeouts with thousands of users
Solutions:
- Implement user batching (process in groups of 100)
- Use GraphQL for complex queries
- Cache frequently accessed data
- Implement progressive review (prioritize high-risk users)

Optimization Example:
# Process users in batches
split -l 100 user_list.txt user_batch_
for batch in user_batch_*; do
    process_user_batch "$batch" &
done
wait
```

#### 2. API Rate Limiting
```yaml
Problem: GitHub API rate limits exceeded
Solutions:
- Implement exponential backoff
- Use authenticated requests (higher limits)
- Cache API responses
- Prioritize critical API calls

Rate Limit Management:
# Check rate limit status
rate_limit=$(gh api rate_limit | jq '.rate.remaining')
if [[ $rate_limit -lt 100 ]]; then
    echo "Rate limit low, implementing delay"
    sleep 300  # Wait 5 minutes
fi
```

#### 3. Data Inconsistencies
```yaml
Problem: Mismatched data between sources
Solutions:
- Implement data validation checkpoints
- Cross-reference multiple data sources
- Maintain audit trails for data collection
- Regular reconciliation processes

Validation Example:
# Cross-validate user data
validate_user_data() {
    local user=$1
    local gh_data=$(gh api users/$user)
    local org_data=$(gh api orgs/$ORG/members/$user)
    
    # Check consistency
    if [[ "$(echo $gh_data | jq -r '.login')" != "$(echo $org_data | jq -r '.login')" ]]; then
        echo "Data inconsistency detected for user: $user"
        log_data_issue "$user" "login_mismatch"
    fi
}
```

### Debugging Commands

#### User Analysis
```bash
# Comprehensive user analysis
analyze_user() {
    local user=$1
    
    echo "=== User Analysis: $user ==="
    
    # Basic user info
    gh api users/$user | jq '{login, id, type, created_at}'
    
    # Organization membership
    gh api orgs/$ORG/members/$user | jq '{login, role}'
    
    # Team memberships
    gh api orgs/$ORG/teams | jq --arg user "$user" '.[] | select(.members[]?.login == $user) | {name, privacy, permission}'
    
    # Repository collaborations
    gh api user/repos | jq --arg user "$user" '.[] | select(.collaborators[]?.login == $user) | {name, permissions}'
    
    # Recent activity
    gh api users/$user/events | jq '.[0:10] | .[] | {type, created_at, repo: .repo.name}'
}
```

#### Review Process Debugging
```bash
# Debug review workflow
debug_review_process() {
    local review_id=$1
    
    echo "=== Review Process Debug: $review_id ==="
    
    # Check workflow status
    gh run list --workflow=user-access-review.yml | head -5
    
    # Analyze artifacts
    gh run download $LATEST_RUN_ID
    
    # Validate data integrity
    jq '.access_review_report.detailed_findings.organization_members[] | select(.risk_assessment.risk_level == "high")' \
        quarterly_access_review_report.json
    
    # Check remediation logs
    if [[ -f "auto_remediation_log.jsonl" ]]; then
        echo "Auto-remediation actions:"
        cat auto_remediation_log.jsonl | jq .
    fi
}
```

### Maintenance Schedule

#### Weekly Tasks
- Monitor review progress and completion rates
- Address escalated review cases
- Update reviewer assignments as needed
- Check system performance and logs

#### Monthly Tasks
- Analyze review trends and patterns
- Update risk assessment criteria
- Review and update automation rules
- Generate management reports

#### Quarterly Tasks
- Comprehensive process review
- Update compliance documentation
- Assess tool effectiveness
- Plan process improvements

#### Annual Tasks
- Complete compliance audit
- Update regulatory mappings
- Review and update policies
- Conduct training refreshers

## Security and Privacy Considerations

### Data Protection

#### Personal Information Handling
```yaml
Data Classification:
- User identities: Confidential
- Activity patterns: Confidential
- Access patterns: Confidential
- Review decisions: Confidential

Retention Policies:
- Active review data: 90 days
- Archived review data: 7 years (compliance requirement)
- Personal identifiers: Anonymized after 2 years
- Audit logs: 7 years with encryption
```

#### Access Controls
```yaml
Review Data Access:
- Security officers: Full access
- Compliance officers: Full access
- HR personnel: Limited to employment status
- Managers: Limited to direct reports
- IT administrators: Technical access only
```

### Audit Trail Requirements

#### Comprehensive Logging
```json
{
  "audit_event": {
    "event_id": "UAR-2024-001-ACTION-001",
    "timestamp": "2024-01-15T10:30:00Z",
    "event_type": "user_access_modification",
    "actor": "security-officer@company.com",
    "target_user": "john.doe@company.com",
    "action": "removed_admin_access",
    "justification": "User inactive for 120 days",
    "approval_chain": ["manager@company.com", "security-lead@company.com"],
    "compliance_impact": ["HITRUST", "FedRAMP"]
  }
}
```

---

## Appendix

### A. Risk Assessment Matrix

```yaml
Risk Factors and Scoring:
User Activity (30% weight):
- No activity >180 days: 30 points
- No activity >90 days: 20 points
- Low activity: 10 points
- Normal activity: 0 points

Access Level (25% weight):
- Organization owner: 25 points
- Admin access to >5 repos: 20 points
- Admin access to 1-5 repos: 15 points
- Write access only: 5 points
- Read access only: 0 points

Security Posture (20% weight):
- No MFA enabled: 20 points
- Weak authentication: 15 points
- Strong authentication: 0 points

External Access (15% weight):
- External collaborator with admin: 15 points
- External collaborator with write: 10 points
- External collaborator read-only: 5 points
- Internal user only: 0 points

Team Membership (10% weight):
- >10 team memberships: 10 points
- 5-10 team memberships: 5 points
- <5 team memberships: 0 points
```

### B. Compliance Evidence Templates

#### B.1 HITRUST Evidence Package
```yaml
Required Evidence:
- User access inventory (AC.1.020)
- Privileged user review (AC.1.020)
- Account management procedures (AC.2.002)
- Access review frequency documentation
- Remediation action logs
- Management sign-off records
```

#### B.2 FedRAMP Evidence Package
```yaml
Required Evidence:
- Account management implementation (AC-2)
- Access enforcement documentation (AC-3)
- Least privilege validation (AC-6)
- Audit information protection (AU-9)
- Regular review schedule compliance
- Risk assessment documentation
```

### C. Integration API Specifications

#### C.1 HR System Integration
```yaml
Required Endpoints:
- GET /api/employees/{id} - Employee details
- GET /api/employees/{id}/manager - Reporting relationship
- GET /api/employees/{id}/status - Employment status
- GET /api/organizational-chart - Hierarchy structure

Required Fields:
- employee_id, email, status, hire_date, termination_date
- manager_email, department, job_title, clearance_level
```

#### C.2 Identity Provider Integration
```yaml
Required Endpoints:
- GET /api/users/{id}/groups - Group memberships
- GET /api/groups/{id}/members - Group member list
- POST /api/users/{id}/access-review - Trigger review
- GET /api/audit-logs - Access audit trails

Authentication:
- OAuth 2.0 with PKCE
- SAML 2.0 for enterprise SSO
- JWT for API authentication
``` 