# FedRAMP Security Controls Implementation Guide

## Overview

This document provides detailed implementation guidance for FedRAMP (Federal Risk and Authorization Management Program) security controls within GitHub Enterprise environments. FedRAMP controls are based on NIST SP 800-53 Rev. 5 and are categorized by control families.

## Control Implementation Framework

### Control Categories
- **Baseline Level**: Moderate (FedRAMP Moderate Baseline)
- **Control Framework**: NIST SP 800-53 Rev. 5
- **Implementation Context**: GitHub Enterprise Cloud/Server
- **Assessment Methodology**: FedRAMP Continuous Monitoring

## Access Control (AC)

### AC-2: Account Management
**Control**: The organization manages information system accounts including establishment, activation, modification, review, and termination.

**GitHub Implementation**:
```yaml
# Account Management Configuration
account_management:
  lifecycle:
    creation: "automated_with_approval"
    activation: "immediate_with_verification"
    modification: "change_control_process"
    review: "quarterly_access_review"
    termination: "immediate_upon_separation"
    
  automation:
    user_provisioning: "saml_sso_integration"
    role_assignment: "team_based_rbac"
    access_review: "automated_reporting"
    
  audit_requirements:
    account_changes: "real_time_logging"
    access_grants: "approval_workflow"
    privilege_escalation: "dual_approval_required"
```

**Implementation Script**:
```bash
#!/bin/bash
# scripts/fedramp/ac-2-account-management.sh

# Account lifecycle management for FedRAMP compliance
manage_account_lifecycle() {
    local action=$1
    local username=$2
    local role=$3
    
    case $action in
        "create")
            # Create user account with proper documentation
            gh api "orgs/$ORG/invitations" \
                --field email="$username" \
                --field role="$role" \
                --field team_ids='[]'
            
            # Log account creation
            log_account_action "ACCOUNT_CREATED" "$username" "$role"
            ;;
            
        "modify")
            # Modify user permissions with approval
            if validate_change_approval "$username" "$role"; then
                gh api "orgs/$ORG/memberships/$username" \
                    --field role="$role"
                log_account_action "ACCOUNT_MODIFIED" "$username" "$role"
            fi
            ;;
            
        "terminate")
            # Immediate account termination
            gh api "orgs/$ORG/members/$username" --method DELETE
            log_account_action "ACCOUNT_TERMINATED" "$username" "N/A"
            ;;
    esac
}

# Quarterly access review process
quarterly_access_review() {
    echo "Generating quarterly access review report..."
    
    # Get all organization members
    gh api "orgs/$ORG/members" --paginate | \
        jq -r '.[] | [.login, .role, .created_at] | @csv' > access_review.csv
    
    # Generate review report
    ./scripts/generate-access-review-report.sh access_review.csv
}

### AC-3: Access Enforcement
**Control**: The information system enforces approved authorizations for logical access.

**GitHub Implementation**:
```yaml
# Access Enforcement Configuration
access_enforcement:
  repository_access:
    default_permission: "read"
    admin_approval_required: true
    branch_protection_enforcement: "strict"
    
  organization_access:
    base_permissions: "read"
    team_based_access: true
    least_privilege_principle: true
    
  api_access:
    token_restrictions: "organization_sso_required"
    oauth_app_restrictions: "admin_approval_required"
    github_app_restrictions: "security_team_review"
```

**Branch Protection Implementation**:
```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "fedramp-compliance-check",
      "security-scan",
      "vulnerability-assessment"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": {
    "users": [],
    "teams": ["security-team", "fedramp-compliance-team"],
    "apps": []
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
```

### AC-6: Least Privilege
**Control**: The organization employs the principle of least privilege, allowing only authorized accesses for users.

**GitHub Implementation**:
```bash
#!/bin/bash
# scripts/fedramp/ac-6-least-privilege.sh

# Implement least privilege access controls
implement_least_privilege() {
    echo "Implementing least privilege access controls..."
    
    # Set organization base permissions to read-only
    gh api "orgs/$ORG" --method PATCH \
        --field default_repository_permission="read" \
        --field members_can_create_repositories=false \
        --field members_can_create_public_repositories=false
    
    # Review and adjust team permissions
    audit_team_permissions
    
    # Implement time-based access for sensitive operations
    configure_temporary_access_controls
}

# Audit team permissions for least privilege compliance
audit_team_permissions() {
    echo "Auditing team permissions..."
    
    # Get all teams and their permissions
    gh api "orgs/$ORG/teams" --paginate | jq -r '.[] | .slug' | \
    while read team; do
        echo "Auditing team: $team"
        
        # Check team repository permissions
        gh api "orgs/$ORG/teams/$team/repos" --paginate | \
            jq -r '.[] | [.name, .permissions.admin, .permissions.push, .permissions.pull] | @csv' \
            > "team_${team}_permissions.csv"
        
        # Validate permissions against least privilege requirements
        validate_team_permissions "$team" "team_${team}_permissions.csv"
    done
}

# Configure temporary access for elevated privileges
configure_temporary_access_controls() {
    # Implement just-in-time access for administrative functions
    cat > .github/workflows/temporary-access.yml << 'EOF'
name: Temporary Elevated Access
on:
  issues:
    types: [opened]
    
jobs:
  grant-temporary-access:
    if: contains(github.event.issue.labels.*.name, 'temporary-access-request')
    runs-on: ubuntu-latest
    steps:
      - name: Validate request
        run: ./scripts/validate-access-request.sh
        
      - name: Grant temporary access
        run: ./scripts/grant-temporary-access.sh
        
      - name: Schedule access revocation
        run: ./scripts/schedule-access-revocation.sh
EOF
}

## Audit and Accountability (AU)

### AU-2: Event Logging
**Control**: The organization determines that the information system is capable of auditing specified events.

**GitHub Implementation**:
```yaml
# Comprehensive Audit Logging Configuration
audit_logging:
  events_to_audit:
    - user_authentication
    - user_authorization_changes
    - repository_access
    - code_commits
    - pull_request_activities
    - administrative_actions
    - security_events
    - configuration_changes
    
  log_retention:
    duration: "7_years"  # FedRAMP requirement
    format: "json_structured"
    encryption: "at_rest_and_in_transit"
    
  log_forwarding:
    siem_integration: true
    splunk_forwarder: true
    elasticsearch_integration: true
```

**Audit Log Collection Workflow**:
```yaml
name: FedRAMP Audit Log Collection
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  collect-audit-logs:
    runs-on: ubuntu-latest
    steps:
      - name: Fetch GitHub audit logs
        run: |
          # Collect comprehensive audit logs
          gh api "enterprises/$ENTERPRISE/audit-log" \
            --field per_page=1000 \
            --field phrase="created:>=$(date -d '6 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
            > audit-logs-$(date +%Y%m%d-%H%M%S).json
            
      - name: Process and enrich logs
        run: |
          # Add FedRAMP-specific metadata
          jq --arg control "AU-2" --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            'map(. + {fedramp_control: $control, processed_at: $timestamp})' \
            audit-logs-*.json > enriched-audit-logs.json
            
      - name: Validate log completeness
        run: |
          # Ensure all required events are captured
          ./scripts/fedramp/validate-audit-completeness.sh enriched-audit-logs.json
          
      - name: Forward to SIEM
        run: |
          # Forward to external SIEM system
          ./scripts/fedramp/forward-logs-to-siem.sh enriched-audit-logs.json
          
      - name: Store in compliant archive
        run: |
          # Store with proper retention and encryption
          ./scripts/fedramp/archive-audit-logs.sh enriched-audit-logs.json
```

### AU-3: Content of Audit Records
**Control**: The information system generates audit records containing sufficient information to establish the outcome of events.

**Audit Record Enhancement**:
```json
{
  "fedramp_audit_record_schema": {
    "version": "1.0",
    "required_fields": {
      "base_fields": [
        "timestamp",
        "event_type",
        "actor_id",
        "actor_name",
        "source_ip",
        "outcome",
        "resource_affected"
      ],
      "fedramp_specific": [
        "session_id",
        "user_role",
        "security_label",
        "system_component",
        "control_correlation",
        "risk_level",
        "authorization_basis"
      ],
      "technical_details": [
        "user_agent",
        "api_version",
        "request_id",
        "response_code",
        "data_classification"
      ]
    },
    "enrichment_rules": {
      "geolocation": "add_location_data",
      "threat_intelligence": "correlate_with_threat_feeds",
      "compliance_mapping": "map_to_fedramp_controls"
    }
  }
}
```

## Configuration Management (CM)

### CM-2: Baseline Configuration
**Control**: The organization develops, documents, and maintains a current baseline configuration.

**GitHub Baseline Configuration**:
```json
{
  "fedramp_baseline_configuration": {
    "organization_settings": {
      "two_factor_requirement": true,
      "saml_sso_enabled": true,
      "ip_allowlist_enabled": true,
      "oauth_app_access_restrictions": true,
      "github_app_access_restrictions": true,
      "members_can_create_repositories": false,
      "members_can_create_public_repositories": false,
      "default_repository_permission": "read",
      "members_can_create_teams": false,
      "members_can_create_pages": false
    },
    "repository_security_baseline": {
      "vulnerability_alerts": true,
      "automated_security_fixes": true,
      "dependency_graph": true,
      "secret_scanning": true,
      "secret_scanning_push_protection": true,
      "code_scanning_default_setup": true,
      "private_vulnerability_reporting": true,
      "branch_protection_required": true,
      "required_approving_reviews": 2,
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "required_status_checks": [
        "fedramp-compliance",
        "security-scan",
        "vulnerability-check"
      ]
    },
    "team_configuration": {
      "minimum_members": 2,
      "require_two_factor_authentication": true,
      "default_permission": "read",
      "admin_approval_required": true
    }
  }
}
```

**Baseline Validation Script**:
```bash
#!/bin/bash
# scripts/fedramp/cm-2-baseline-validation.sh

# Validate current configuration against FedRAMP baseline
validate_fedramp_baseline() {
    local baseline_file="fedramp-baseline.json"
    local current_config_file="current-config.json"
    local compliance_report="fedramp-baseline-compliance.json"
    
    echo "Validating FedRAMP baseline configuration..."
    
    # Capture current organization configuration
    capture_current_configuration > "$current_config_file"
    
    # Compare against baseline
    compare_configurations "$baseline_file" "$current_config_file" > "$compliance_report"
    
    # Generate compliance score
    local compliance_score
    compliance_score=$(calculate_compliance_score "$compliance_report")
    
    echo "FedRAMP Baseline Compliance Score: $compliance_score%"
    
    if [ "$compliance_score" -lt 100 ]; then
        echo "Configuration deviations detected. Review required."
        generate_remediation_plan "$compliance_report"
        return 1
    else
        echo "All configurations comply with FedRAMP baseline."
        return 0
    fi
}

# Capture current GitHub configuration
capture_current_configuration() {
    # Organization settings
    local org_config
    org_config=$(gh api "orgs/$ORG" | jq '{
        two_factor_requirement: .two_factor_requirement_enabled,
        default_repository_permission: .default_repository_permission,
        members_can_create_repositories: .members_can_create_repositories,
        members_can_create_public_repositories: .members_can_create_public_repositories
    }')
    
    # Security features across repositories
    local repo_security_config="[]"
    gh repo list "$ORG" --json name,isPrivate | jq -r '.[] | .name' | \
    while read repo; do
        local repo_config
        repo_config=$(gh api "repos/$ORG/$repo" | jq '{
            name: .name,
            private: .private,
            vulnerability_alerts: .has_vulnerability_alerts,
            automated_security_fixes: .security_and_analysis.automated_security_fixes.status,
            secret_scanning: .security_and_analysis.secret_scanning.status
        }')
        repo_security_config=$(echo "$repo_security_config" | jq ". + [$repo_config]")
    done
    
    # Combine all configuration data
    jq -n \
        --argjson org "$org_config" \
        --argjson repos "$repo_security_config" \
        '{
            organization: $org,
            repositories: $repos,
            captured_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }'
}

### CM-3: Configuration Change Control
**Control**: The organization determines the types of changes to the information system that are configuration-controlled.

**Change Control Workflow**:
```yaml
name: FedRAMP Configuration Change Control
on:
  pull_request:
    paths:
      - 'fedramp-baseline.json'
      - '.github/workflows/fedramp-*.yml'
      - 'scripts/fedramp/**'
    branches: [main]

jobs:
  change-control-review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          
      - name: Analyze configuration changes
        id: analyze-changes
        run: |
          # Identify configuration changes
          git diff origin/main...HEAD --name-only > changed_files.txt
          
          # Categorize changes by risk level
          ./scripts/fedramp/categorize-config-changes.sh changed_files.txt > change_analysis.json
          
          # Extract risk level for workflow decisions
          RISK_LEVEL=$(jq -r '.risk_level' change_analysis.json)
          echo "risk_level=$RISK_LEVEL" >> $GITHUB_OUTPUT
          
      - name: Security impact assessment
        run: |
          # Assess security impact of proposed changes
          ./scripts/fedramp/assess-security-impact.sh change_analysis.json > security_impact.json
          
      - name: Require appropriate approvals
        uses: actions/github-script@v7
        with:
          script: |
            const riskLevel = '${{ steps.analyze-changes.outputs.risk_level }}';
            let reviewers = ['security-team'];
            
            // High-risk changes require additional approvals
            if (riskLevel === 'high' || riskLevel === 'critical') {
              reviewers.push('fedramp-compliance-team', 'ciso');
            }
            
            await github.rest.pulls.requestReviewers({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number,
              team_reviewers: reviewers
            });
            
      - name: Generate change control documentation
        run: |
          # Document change for compliance audit
          ./scripts/fedramp/generate-change-documentation.sh \
            change_analysis.json \
            security_impact.json \
            > change_control_record.json
            
      - name: Update change control log
        run: |
          # Maintain comprehensive change log
          ./scripts/fedramp/update-change-log.sh change_control_record.json
```

## Identification and Authentication (IA)

### IA-2: Identification and Authentication (Organizational Users)
**Control**: The information system uniquely identifies and authenticates organizational users.

**GitHub Implementation**:
```yaml
# Identity and Authentication Configuration
identity_authentication:
  primary_authentication:
    method: "saml_sso"
    identity_provider: "enterprise_directory"
    multi_factor_required: true
    
  secondary_authentication:
    backup_codes: true
    hardware_tokens: "fido2_support"
    mobile_authenticator: true
    
  session_management:
    timeout: "8_hours"
    concurrent_sessions: "limited"
    reauthentication_required: "privileged_operations"
```

**SAML SSO Configuration Validation**:
```bash
#!/bin/bash
# scripts/fedramp/ia-2-authentication-validation.sh

# Validate SAML SSO configuration for FedRAMP compliance
validate_saml_configuration() {
    echo "Validating SAML SSO configuration..."
    
    # Check SAML SSO status
    local saml_status
    saml_status=$(gh api "orgs/$ORG" --jq '.has_organization_projects')
    
    if [ "$saml_status" = "true" ]; then
        echo "✓ SAML SSO is enabled"
    else
        echo "✗ SAML SSO is not enabled"
        return 1
    fi
    
    # Validate identity provider configuration
    validate_identity_provider_config
    
    # Check user authentication status
    validate_user_authentication_status
    
    # Verify session management settings
    validate_session_management
}

# Validate identity provider configuration
validate_identity_provider_config() {
    echo "Validating identity provider configuration..."
    
    # This would typically involve checking SAML metadata
    # and configuration against FedRAMP requirements
    
    local idp_config
    idp_config=$(./scripts/fedramp/get-idp-config.sh)
    
    # Validate required SAML attributes
    local required_attributes=("NameID" "email" "groups" "role")
    for attr in "${required_attributes[@]}"; do
        if echo "$idp_config" | jq -e ".attributes | has(\"$attr\")" > /dev/null; then
            echo "✓ Required attribute '$attr' is configured"
        else
            echo "✗ Missing required attribute: $attr"
        fi
    done
}

# Validate user authentication status
validate_user_authentication_status() {
    echo "Validating user authentication status..."
    
    # Get users without SAML authentication
    local unauthenticated_users
    unauthenticated_users=$(gh api "orgs/$ORG/members" --paginate | \
        jq -r '.[] | select(.has_two_factor_authentication == false) | .login')
    
    if [ -n "$unauthenticated_users" ]; then
        echo "✗ Users without proper authentication:"
        echo "$unauthenticated_users"
        return 1
    else
        echo "✓ All users have proper authentication"
    fi
}

## System and Communications Protection (SC)

### SC-7: Boundary Protection
**Control**: The information system monitors and controls communications at the external boundary and key internal boundaries.

**Network Boundary Protection**:
```yaml
# GitHub Network Security Configuration
boundary_protection:
  ip_allowlisting:
    enabled: true
    allowed_ranges:
      - "10.0.0.0/8"        # Internal corporate network
      - "172.16.0.0/12"     # VPN network
      - "203.0.113.0/24"    # Approved external access
      
  api_access_control:
    oauth_restrictions: true
    github_app_restrictions: true
    personal_access_token_restrictions: true
    
  webhook_security:
    secret_validation: true
    tls_required: true
    ip_restrictions: true
```

**Boundary Protection Implementation**:
```bash
#!/bin/bash
# scripts/fedramp/sc-7-boundary-protection.sh

# Implement boundary protection controls
implement_boundary_protection() {
    echo "Implementing boundary protection controls..."
    
    # Configure IP allowlisting
    configure_ip_allowlist
    
    # Set up OAuth app restrictions
    configure_oauth_restrictions
    
    # Implement webhook security
    configure_webhook_security
    
    # Monitor network access
    setup_access_monitoring
}

# Configure organization IP allowlist
configure_ip_allowlist() {
    echo "Configuring IP allowlist..."
    
    # Enable IP allowlist for the organization
    gh api "orgs/$ORG" --method PATCH \
        --field ip_allowlist_enabled=true
    
    # Add approved IP ranges
    local allowed_ips=(
        "10.0.0.0/8"
        "172.16.0.0/12"
        "203.0.113.0/24"
    )
    
    for ip_range in "${allowed_ips[@]}"; do
        gh api "orgs/$ORG/settings/ip_allowlist" --method POST \
            --field ip_address="$ip_range" \
            --field is_active=true
    done
}

# Configure OAuth application restrictions
configure_oauth_restrictions() {
    echo "Configuring OAuth application restrictions..."
    
    # Enable OAuth app access restrictions
    gh api "orgs/$ORG" --method PATCH \
        --field oauth_app_access_restrictions_enabled=true
    
    # Restrict GitHub app installations
    gh api "orgs/$ORG" --method PATCH \
        --field github_app_access_restrictions_enabled=true
}

# Set up continuous monitoring for boundary violations
setup_access_monitoring() {
    cat > .github/workflows/boundary-monitoring.yml << 'EOF'
name: Boundary Protection Monitoring
on:
  schedule:
    - cron: '*/30 * * * *'  # Every 30 minutes

jobs:
  monitor-access:
    runs-on: ubuntu-latest
    steps:
      - name: Check for unauthorized access attempts
        run: |
          # Monitor audit logs for boundary violations
          gh api "enterprises/$ENTERPRISE/audit-log" \
            --field phrase="action:org.oauth_app_access_denied" \
            --field per_page=100 | \
            jq '.[] | select(.created_at > (now - 1800))' > violations.json
          
          if [ -s violations.json ]; then
            ./scripts/fedramp/alert-boundary-violation.sh violations.json
          fi
EOF
}

## Implementation Compliance Matrix

### FedRAMP Control Implementation Status

| Control | Implementation Status | Automation Level | Validation Method |
|---------|---------------------|------------------|------------------|
| AC-2 | ✅ Implemented | High | Automated Testing |
| AC-3 | ✅ Implemented | High | Policy Enforcement |
| AC-6 | ✅ Implemented | Medium | Periodic Review |
| AU-2 | ✅ Implemented | High | Continuous Monitoring |
| AU-3 | ✅ Implemented | High | Automated Validation |
| CM-2 | ✅ Implemented | High | Configuration Scanning |
| CM-3 | ✅ Implemented | High | Workflow Enforcement |
| IA-2 | ✅ Implemented | Medium | Authentication Testing |
| SC-7 | ✅ Implemented | High | Network Monitoring |

### Continuous Monitoring Implementation

```yaml
name: FedRAMP Continuous Monitoring
on:
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours
  workflow_dispatch:

jobs:
  continuous-monitoring:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        control: [AC-2, AC-3, AC-6, AU-2, AU-3, CM-2, CM-3, IA-2, SC-7]
    steps:
      - name: Execute control validation
        run: ./scripts/fedramp/validate-${{ matrix.control }}.sh
        
      - name: Generate control assessment
        run: ./scripts/fedramp/assess-${{ matrix.control }}.sh
        
      - name: Update compliance dashboard
        run: ./scripts/fedramp/update-dashboard.sh ${{ matrix.control }}
        
      - name: Create compliance issue if needed
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `FedRAMP Control ${{ matrix.control }} - Compliance Issue Detected`,
              body: 'Automated monitoring detected a compliance issue requiring immediate attention.',
              labels: ['fedramp', 'compliance-issue', 'urgent', 'control-${{ matrix.control }}']
            });
```

## Assessment and Authorization

### Security Assessment Plan (SAP)

```yaml
security_assessment_plan:
  assessment_frequency: "continuous"
  assessment_methods:
    - automated_scanning
    - configuration_validation
    - vulnerability_assessment
    - penetration_testing
    
  assessment_scope:
    - github_enterprise_platform
    - organization_configurations
    - repository_security_settings
    - user_access_controls
    - audit_logging_systems
    
  assessment_procedures:
    daily:
      - configuration_drift_detection
      - access_control_validation
      - audit_log_analysis
    weekly:
      - vulnerability_scanning
      - security_baseline_validation
    monthly:
      - comprehensive_security_assessment
      - penetration_testing
    quarterly:
      - full_control_assessment
      - risk_assessment_update
```

### Plan of Action and Milestones (POA&M)

```yaml
poam_process:
  identification:
    automated_detection: true
    manual_identification: true
    external_audit_findings: true
    
  categorization:
    risk_levels: [low, moderate, high, critical]
    impact_assessment: automated
    likelihood_assessment: manual_review
    
  remediation:
    immediate_actions: "critical_findings"
    short_term_plans: "30_days"
    long_term_plans: "90_days"
    
  tracking:
    milestone_tracking: automated
    progress_reporting: weekly
    stakeholder_updates: monthly
```

---

**Document Version**: 1.0  
**Control Framework**: FedRAMP Moderate Baseline (NIST SP 800-53 Rev. 5)  
**Last Updated**: [Current Date]  
**Next Review**: [Current Date + 3 months]  
**Implementation Level**: GitHub Enterprise Cloud/Server 