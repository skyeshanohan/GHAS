# Personal Access Token Request Process Documentation

## Overview

The Personal Access Token (PAT) Request Process provides a structured, compliant workflow for requesting, reviewing, and approving Personal Access Tokens in GitHub Enterprise environments. This process ensures compliance with HITRUST CSF, FedRAMP, and HIPAA requirements for privileged access management and audit trails.

## Business Context

### Purpose
This process addresses critical compliance and security requirements:
- **Privileged Access Control**: Ensures PATs are only issued with appropriate business justification
- **Audit Trail**: Maintains comprehensive records of token requests and approvals
- **Risk Management**: Implements risk-based review processes for different token types
- **Compliance Validation**: Ensures token usage aligns with regulatory requirements

### Regulatory Requirements

#### HITRUST CSF
- **AC.1.020**: Privileged Access Management
- **IA.1.076**: Identification and Authentication Controls

#### FedRAMP
- **AC-6**: Least Privilege
- **IA-2**: Identification and Authentication (Organizational Users)
- **AU-2**: Event Logging

#### HIPAA
- **164.308(a)(3)**: Administrative Safeguards - Assigned Security Responsibility
- **164.308(a)(4)**: Administrative Safeguards - Information Access Management
- **164.312(a)(2)(i)**: Technical Safeguards - Unique User Identification

### Business Value
- **Compliance Assurance**: Demonstrates controlled access to auditors
- **Security Posture**: Reduces risk from uncontrolled token proliferation
- **Operational Efficiency**: Standardizes token request and approval process
- **Audit Readiness**: Provides comprehensive token usage documentation

## Technical Architecture

### Process Flow
```
PAT Request Process
├── Issue Creation (via Template)
├── Automated Validation
├── Risk Assessment
├── Security Team Review
├── Compliance Review (High Risk)
├── Manager Approval
├── Token Approval/Denial
├── Audit Logging
└── Periodic Review
```

### Component Overview

#### 1. Issue Template
- **File**: `.github/ISSUE_TEMPLATE/personal-access-token-request.yml`
- **Purpose**: Structured data collection for token requests
- **Features**: Form validation, compliance acknowledgments, risk assessment inputs

#### 2. Workflow Automation
- **File**: `docs/workflows/personal-access-token-request.yml`
- **Purpose**: Automated processing of token requests
- **Features**: Validation, routing, approval tracking, audit logging

#### 3. Review Process
- **Security Review**: Technical and security assessment
- **Compliance Review**: Regulatory requirement validation
- **Manager Approval**: Business justification validation

## Implementation Guide

### Phase 1: Pre-Implementation Setup

#### 1.1 Team Configuration
```bash
# Create required teams
gh api orgs/$ORG/teams \
  --method POST \
  --field name="security-team" \
  --field description="Security review team for PAT requests"

gh api orgs/$ORG/teams \
  --method POST \
  --field name="compliance-team" \
  --field description="Compliance review team"
```

#### 1.2 Repository Setup
```bash
# Ensure issue templates directory exists
mkdir -p .github/ISSUE_TEMPLATE

# Deploy issue template
cp .github/ISSUE_TEMPLATE/personal-access-token-request.yml .github/ISSUE_TEMPLATE/

# Deploy workflow
cp docs/workflows/personal-access-token-request.yml .github/workflows/
```

### Phase 2: Configuration

#### 2.1 Organization Variables
```bash
# Set default reviewers
gh variable set PAT_SECURITY_TEAM --value "@security-team" --org $ORG
gh variable set PAT_COMPLIANCE_TEAM --value "@compliance-team" --org $ORG

# Set notification preferences
gh variable set PAT_NOTIFICATIONS_ENABLED --value "true" --org $ORG
```

#### 2.2 Notification Setup
```bash
# Configure Slack integration (optional)
gh secret set SLACK_PAT_WEBHOOK --body "$SLACK_WEBHOOK_URL" --org $ORG

# Configure email notifications (optional)
gh secret set EMAIL_NOTIFICATION_ENDPOINT --body "$EMAIL_API_URL" --org $ORG
```

### Phase 3: Process Customization

#### 3.1 Risk Level Configuration
```yaml
# In workflow file, customize risk assessment
HIGH_RISK_SCOPES=("admin:org" "admin:repo_hook" "admin:org_hook" "admin:enterprise" "delete_repo")
MEDIUM_RISK_SCOPES=("repo" "workflow" "write:packages" "admin:public_key")

# Risk level determines review requirements:
# - High: Security + Compliance + Manager approval
# - Medium: Security + Manager approval  
# - Low: Security approval only
```

#### 3.2 Approval Authority Configuration
```yaml
# Define approval authority by risk level
approval_matrix:
  low_risk:
    required_approvers: ["security-team"]
    approval_count: 1
  medium_risk:
    required_approvers: ["security-team", "manager"]
    approval_count: 2
  high_risk:
    required_approvers: ["security-team", "compliance-team", "manager"]
    approval_count: 3
```

### Phase 4: Testing and Validation

#### 4.1 Test Request Flow
```bash
# Create test PAT request issue
gh issue create \
  --title "[PAT Request] Test Token for Development" \
  --template personal-access-token-request.yml \
  --assignee security-team-lead
```

#### 4.2 Validate Automation
```bash
# Monitor workflow execution
gh run list --workflow=personal-access-token-request.yml
gh run view $RUN_ID --log

# Check issue labels and assignments
gh issue view $ISSUE_NUMBER
```

## Request Form Fields

### Required Information

#### Requester Details
- **Full Name**: For identity verification
- **Email Address**: Corporate email for notifications
- **Manager Email**: For approval routing
- **Team/Department**: For context and validation

#### Token Specifications
- **Token Type**: Classic, Fine-grained, or GitHub App alternative
- **Scopes Requested**: Specific permissions needed (principle of least privilege)
- **Duration**: Time-bound access requirement
- **Storage Method**: How token will be securely stored

#### Business Justification
- **Use Case**: Specific business need for the token
- **Data Access**: Description of data the token will access
- **Alternatives Considered**: Why other authentication methods are insufficient
- **Security Measures**: Planned security implementations

#### Compliance Acknowledgments
- Understanding of audit requirements
- Agreement to security policies
- Commitment to proper token management
- Incident reporting obligations

## Review Process

### Stage 1: Automated Validation

#### Validation Checks
```yaml
Required Field Validation:
- Business justification completeness
- Scope selection appropriateness
- Duration reasonableness
- Storage method security
- Compliance acknowledgments

Risk Assessment:
- Scope-based risk scoring
- Data access sensitivity evaluation
- Duration-based risk factors
- User role and history consideration
```

#### Automated Responses
- **Valid Request**: Proceed to security review
- **Invalid Request**: Request corrections with specific feedback
- **High Risk**: Additional compliance review triggered

### Stage 2: Security Team Review

#### Review Criteria
```yaml
Security Assessment:
- Principle of least privilege application
- Business justification adequacy
- Technical necessity validation
- Alternative solution evaluation
- Security controls sufficiency

Security Checklist:
- [ ] Business need clearly articulated
- [ ] Requested scopes minimal and necessary
- [ ] Duration appropriate for use case
- [ ] Storage method secure and compliant
- [ ] Requester has legitimate need
- [ ] Alternatives properly considered
```

#### Security Team Actions
- **Approve**: Move to next review stage
- **Deny**: Provide reason and alternative recommendations
- **Request Changes**: Specify required modifications

### Stage 3: Compliance Review (High Risk Only)

#### Compliance Assessment
```yaml
Regulatory Review:
- HITRUST CSF compliance validation
- FedRAMP requirement verification
- HIPAA safeguard assessment
- Industry-specific regulation check

Compliance Checklist:
- [ ] Token usage aligns with regulatory requirements
- [ ] Audit trail requirements met
- [ ] Data classification compliance verified
- [ ] Access control requirements satisfied
```

### Stage 4: Manager Approval

#### Management Review
```yaml
Business Validation:
- Resource allocation justification
- Project priority validation
- Team capability assessment
- Timeline reasonableness

Manager Checklist:
- [ ] Business need validated
- [ ] Resource allocation appropriate
- [ ] Team member authorization confirmed
- [ ] Project timeline supports request
```

## Risk Assessment Framework

### Risk Levels

#### Low Risk
```yaml
Characteristics:
- Read-only access scopes
- Limited duration (≤30 days)
- Non-sensitive data access
- Development/testing environments

Review Requirements:
- Security team approval only
- Standard turnaround time: 1-2 business days
```

#### Medium Risk
```yaml
Characteristics:
- Write access scopes
- Moderate duration (30-90 days)
- Production environment access
- Package or workflow management

Review Requirements:
- Security team + Manager approval
- Standard turnaround time: 2-3 business days
```

#### High Risk
```yaml
Characteristics:
- Administrative scopes
- Extended duration (>90 days)
- Organization-level permissions
- Sensitive data access potential

Review Requirements:
- Security + Compliance + Manager approval
- Standard turnaround time: 3-5 business days
```

## Monitoring and Compliance

### Audit Trail Components

#### Request Tracking
```json
{
  "request_id": "PAT-2024-001",
  "requester": "john.doe@company.com",
  "submitted_at": "2024-01-15T10:30:00Z",
  "request_details": {
    "scopes": ["repo", "workflow"],
    "duration": "30 days",
    "business_justification": "CI/CD automation for Project X"
  }
}
```

#### Review History
```json
{
  "reviews": [
    {
      "stage": "security_review",
      "reviewer": "security-team",
      "decision": "approved",
      "timestamp": "2024-01-16T09:15:00Z",
      "comments": "Request meets security requirements"
    }
  ]
}
```

#### Decision Record
```json
{
  "final_decision": "approved",
  "decision_date": "2024-01-17T14:20:00Z",
  "approved_by": "security-team",
  "conditions": ["30-day expiration", "quarterly review required"]
}
```

### Compliance Metrics

#### Key Performance Indicators
- **Request Volume**: Monthly PAT request count
- **Approval Rate**: Percentage of requests approved
- **Processing Time**: Average time from request to decision
- **Risk Distribution**: Breakdown by risk level

#### Compliance Dashboard
```yaml
Metrics Tracked:
- Total requests by month
- Approval/denial rates
- Average processing time
- Risk level distribution
- Compliance standard impact
```

## Token Lifecycle Management

### Post-Approval Process

#### Token Generation Guidelines
```yaml
Token Configuration:
- Use approved scopes only
- Set expiration to requested duration
- Configure for specific repositories when possible
- Enable audit logging where available
```

#### Token Distribution
- Secure delivery to requester
- Documentation of token details
- Instructions for secure storage
- Usage guidelines and restrictions

### Ongoing Management

#### Regular Reviews
```yaml
Review Schedule:
- Monthly: Active token inventory
- Quarterly: Token usage assessment
- Semi-annually: Access pattern analysis
- Annually: Process effectiveness review
```

#### Token Rotation
- Automated expiration enforcement
- Renewal process for long-term tokens
- Emergency revocation procedures
- Key rotation best practices

### Incident Response

#### Token Compromise Response
1. **Immediate Actions** (< 1 hour)
   - Revoke compromised token
   - Assess potential impact
   - Notify security team

2. **Investigation** (< 24 hours)
   - Determine scope of access
   - Review audit logs
   - Identify any unauthorized activity

3. **Recovery** (< 48 hours)
   - Issue replacement token if needed
   - Implement additional controls
   - Update security procedures

## Integration Points

### External Systems

#### Identity Management
```bash
# LDAP/Active Directory integration
# Validate requester against corporate directory
ldapsearch -x -b "dc=company,dc=com" \
  "(mail=$REQUESTER_EMAIL)" \
  cn mail manager
```

#### ITSM Integration
```bash
# ServiceNow ticket creation
curl -X POST "$SERVICENOW_API/table/incident" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "short_description": "PAT Request Approved: $REQUEST_ID",
    "description": "Personal Access Token approved for $REQUESTER"
  }'
```

#### SIEM Integration
```bash
# Forward audit events to SIEM
curl -X POST "$SIEM_ENDPOINT/events" \
  -H "Content-Type: application/json" \
  -d '@pat_approval_event.json'
```

## Troubleshooting

### Common Issues

#### 1. Issue Template Not Working
```yaml
Problem: Template not appearing in issue creation
Causes:
- File in wrong location
- YAML syntax errors
- Missing required fields

Solution:
# Validate YAML syntax
yamllint .github/ISSUE_TEMPLATE/personal-access-token-request.yml

# Check file placement
ls -la .github/ISSUE_TEMPLATE/
```

#### 2. Workflow Not Triggering
```yaml
Problem: Automation not starting on issue creation
Causes:
- Workflow syntax errors
- Missing permissions
- Label mismatch

Solution:
# Check workflow syntax
gh workflow view personal-access-token-request.yml

# Verify issue labels
gh issue view $ISSUE_NUMBER --json labels
```

#### 3. Notification Failures
```yaml
Problem: Reviewers not receiving notifications
Causes:
- Incorrect team mentions
- Webhook configuration issues
- Permission problems

Solution:
# Test team mention
gh api orgs/$ORG/teams/security-team/members

# Validate webhook
curl -X POST $SLACK_WEBHOOK -d '{"text":"Test"}'
```

### Debugging Commands

```bash
# Check workflow run status
gh run list --workflow=personal-access-token-request.yml

# View specific run details
gh run view $RUN_ID --log

# Check issue events
gh api repos/$ORG/$REPO/issues/$ISSUE_NUMBER/events

# Validate team membership
gh api orgs/$ORG/teams/security-team/members
```

## Maintenance and Updates

### Regular Maintenance Tasks

#### Weekly
- Review pending requests
- Monitor approval times
- Check automation health

#### Monthly
- Analyze request patterns
- Review approval rates
- Update team assignments

#### Quarterly
- Assess process effectiveness
- Update risk criteria
- Review compliance alignment

#### Annually
- Complete process audit
- Update compliance mappings
- Refresh training materials

### Process Updates

#### Adding New Risk Criteria
1. Update risk assessment logic in workflow
2. Modify issue template if needed
3. Update documentation
4. Train review teams
5. Communicate changes to users

#### Changing Approval Requirements
1. Update approval matrix
2. Modify workflow logic
3. Update team assignments
4. Test with representative requests
5. Deploy and monitor

## Support and Training

### User Training

#### Requester Training
- PAT request process overview
- Form completion guidance
- Security best practices
- Token management responsibilities

#### Reviewer Training
- Review criteria and procedures
- Risk assessment guidelines
- Compliance requirements
- Escalation procedures

### Support Resources

#### Documentation
- Process overview (this document)
- Request form user guide
- Security best practices guide
- Troubleshooting knowledge base

#### Contacts
- **Process Questions**: security@company.com
- **Technical Issues**: platform-team@company.com
- **Compliance Questions**: compliance@company.com

---

## Appendix

### A. Scope Risk Matrix
```yaml
High Risk Scopes:
- admin:org: Full organizational control
- admin:enterprise: Enterprise-level administration
- delete_repo: Repository deletion capability
- admin:repo_hook: Repository webhook management
- admin:org_hook: Organization webhook management

Medium Risk Scopes:
- repo: Full repository access
- workflow: GitHub Actions workflow access
- write:packages: Package publishing capability
- admin:public_key: SSH key management

Low Risk Scopes:
- read:org: Organization read access
- read:user: User profile read access
- public_repo: Public repository access
- read:packages: Package read access
```

### B. Sample Request Templates

#### B.1 CI/CD Automation Request
```yaml
Business Justification: "Automated deployment pipeline for Project X requires repository access to clone code, run tests, and deploy artifacts."

Scopes: ["repo", "workflow"]
Duration: "90 days"
Storage: "GitHub Secrets (Organization)"
Environment: "Production CI/CD pipeline"
```

#### B.2 Security Scanning Request
```yaml
Business Justification: "Security scanning tool integration requires access to scan repositories for vulnerabilities and compliance issues."

Scopes: ["security_events", "repo:status"]
Duration: "1 year"
Storage: "AWS Secrets Manager"
Environment: "Security scanning infrastructure"
```

### C. Compliance Mapping
```yaml
HITRUST CSF Mappings:
- AC.1.020: Privileged Access Management
  - Controls: PAT approval process, audit trail
- IA.1.076: Identification and Authentication
  - Controls: User validation, token attribution

FedRAMP Mappings:
- AC-6: Least Privilege
  - Controls: Scope limitation, risk assessment
- IA-2: Identification and Authentication
  - Controls: User identity verification
- AU-2: Event Logging
  - Controls: Request and approval logging

HIPAA Mappings:
- 164.308(a)(3): Assigned Security Responsibility
  - Controls: Security team review process
- 164.308(a)(4): Information Access Management
  - Controls: Access justification and approval
``` 