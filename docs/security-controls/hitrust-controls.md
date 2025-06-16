# HITRUST CSF Security Controls Implementation Guide

## Overview

This document provides detailed implementation guidance for HITRUST CSF security controls within GitHub Enterprise environments. Each control includes specific implementation steps, validation procedures, and GitHub-specific configurations.

## Access Control (AC)

### AC.1.007 - Multi-Factor Authentication
**Requirement**: The organization requires multi-factor authentication for all user access to information systems containing sensitive information.

**GitHub Implementation**:
```yaml
# Organization-level MFA enforcement
organization_settings:
  two_factor_requirement: enabled
  two_factor_grace_period: 0  # Immediate enforcement
  
# SAML SSO configuration with MFA
saml_configuration:
  require_saml_sso: true
  session_timeout: 8_hours
  require_mfa_in_idp: true
```

**Validation Script**:
```bash
#!/bin/bash
# scripts/validate-mfa-compliance.sh

# Check organization MFA requirement
MFA_REQUIRED=$(gh api orgs/$ORG --jq '.two_factor_requirement_enabled')

if [ "$MFA_REQUIRED" != "true" ]; then
    echo "FAIL: Organization MFA requirement not enabled"
    exit 1
fi

# Check user MFA status
USERS_WITHOUT_MFA=$(gh api orgs/$ORG/members --paginate | jq -r '.[] | select(.two_factor_authentication == false) | .login')

if [ -n "$USERS_WITHOUT_MFA" ]; then
    echo "FAIL: Users without MFA: $USERS_WITHOUT_MFA"
    exit 1
fi

echo "PASS: All users have MFA enabled"
```

### AC.1.020 - Privileged Access Management
**Requirement**: The organization implements privileged access management and monitoring for administrative accounts.

**GitHub Implementation**:
```yaml
# Privileged access configuration
privileged_access:
  admin_teams:
    - name: "enterprise-admins"
      members: ["admin1", "admin2"]
      session_timeout: 4_hours
      
  organization_owners:
    max_count: 3
    require_mfa: true
    require_saml_sso: true
    
  repository_admins:
    require_two_person_approval: true
    require_branch_protection_bypass_review: true
```

**Monitoring Workflow**:
```yaml
name: Privileged Access Monitoring
on:
  schedule:
    - cron: '0 */2 * * *'  # Every 2 hours

jobs:
  monitor-privileged-access:
    runs-on: ubuntu-latest
    steps:
      - name: Check admin account activity
        run: |
          # Monitor admin actions in audit log
          gh api enterprises/$ENTERPRISE/audit-log \
            --field phrase="action:org.add_member actor:admin*" \
            --field per_page=100 | \
            jq '.[] | select(.created_at > (now - 7200))' > admin_activity.json
            
      - name: Validate admin session durations
        run: ./scripts/validate-admin-sessions.sh
        
      - name: Generate privileged access report
        run: ./scripts/generate-privileged-access-report.sh
```

### AC.2.002 - Account Lifecycle Management
**Requirement**: The organization manages information system accounts including establishment, activation, modification, and termination.

**GitHub Implementation**:
```yaml
# Account lifecycle automation
name: Account Lifecycle Management
on:
  organization:
    types: [member_added, member_removed]
  team:
    types: [added_to_repository, removed_from_repository]

jobs:
  account-lifecycle:
    runs-on: ubuntu-latest
    steps:
      - name: Log account changes
        run: |
          echo "Account change detected: ${{ github.event.action }}"
          echo "Member: ${{ github.event.membership.user.login }}"
          echo "Organization: ${{ github.event.organization.login }}"
          
      - name: Validate account permissions
        run: ./scripts/validate-account-permissions.sh
        
      - name: Update access control matrix
        run: ./scripts/update-access-matrix.sh
        
      - name: Notify security team
        if: github.event.action == 'member_added'
        run: ./scripts/notify-new-member.sh
```

## Configuration Management (CM)

### CM.1.061 - Baseline Configuration Management
**Requirement**: The organization establishes and maintains baseline configurations for information technology systems.

**GitHub Configuration Baseline**:
```json
{
  "organization_security_baseline": {
    "two_factor_requirement": true,
    "dependency_graph": true,
    "dependency_security_updates": true,
    "dependabot_alerts": true,
    "secret_scanning": true,
    "secret_scanning_push_protection": true,
    "advanced_security_enabled": true,
    "private_vulnerability_reporting": true,
    "saml_sso_enabled": true,
    "ip_allowlist_enabled": true,
    "members_can_create_repositories": false,
    "members_can_create_public_repositories": false,
    "default_repository_permission": "read"
  },
  "repository_security_baseline": {
    "branch_protection": {
      "required_status_checks": {
        "strict": true,
        "contexts": ["security-scan", "compliance-check"]
      },
      "enforce_admins": true,
      "required_pull_request_reviews": {
        "required_approving_review_count": 2,
        "dismiss_stale_reviews": true,
        "require_code_owner_reviews": true
      },
      "restrictions": null,
      "required_linear_history": true,
      "allow_force_pushes": false,
      "allow_deletions": false
    },
    "security_features": {
      "vulnerability_alerts": true,
      "automated_security_fixes": true,
      "secret_scanning": true,
      "secret_scanning_push_protection": true
    }
  }
}
```

**Baseline Validation Script**:
```bash
#!/bin/bash
# scripts/validate-security-baseline.sh

CONFIG_FILE="security-baseline.json"
COMPLIANCE_REPORT="baseline-compliance-report.json"

# Validate organization settings against baseline
validate_org_settings() {
    echo "Validating organization security settings..."
    
    local org_settings=$(gh api orgs/$ORG)
    local baseline=$(jq '.organization_security_baseline' $CONFIG_FILE)
    
    # Check each baseline setting
    jq -r 'keys[]' <<< "$baseline" | while read setting; do
        expected=$(jq -r ".organization_security_baseline.$setting" $CONFIG_FILE)
        actual=$(jq -r ".$setting // false" <<< "$org_settings")
        
        if [ "$expected" != "$actual" ]; then
            echo "FAIL: $setting - Expected: $expected, Actual: $actual"
        else
            echo "PASS: $setting"
        fi
    done
}

# Validate repository settings against baseline
validate_repo_settings() {
    echo "Validating repository security settings..."
    
    # Get all repositories
    gh repo list $ORG --limit 1000 --json name | jq -r '.[].name' | while read repo; do
        echo "Checking repository: $repo"
        
        # Check branch protection
        local protection=$(gh api repos/$ORG/$repo/branches/main/protection 2>/dev/null || echo "{}")
        local baseline_protection=$(jq '.repository_security_baseline.branch_protection' $CONFIG_FILE)
        
        # Validate branch protection settings
        validate_branch_protection "$repo" "$protection" "$baseline_protection"
        
        # Check security features
        local repo_settings=$(gh api repos/$ORG/$repo)
        validate_security_features "$repo" "$repo_settings"
    done
}

validate_org_settings
validate_repo_settings
```

### CM.2.063 - Change Control Procedures
**Requirement**: The organization implements a change control process for information system configuration changes.

**Change Control Workflow**:
```yaml
name: Configuration Change Control
on:
  pull_request:
    paths:
      - 'security-baseline.json'
      - '.github/workflows/security-*.yml'
      - 'scripts/security-*.sh'
    branches: [main]

jobs:
  change-control-review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        
      - name: Analyze configuration changes
        run: |
          # Compare changes against current baseline
          git diff origin/main...HEAD -- security-baseline.json > config_changes.diff
          
          # Validate changes don't introduce security gaps
          ./scripts/validate-config-changes.sh config_changes.diff
          
      - name: Security impact assessment
        run: ./scripts/assess-security-impact.sh
        
      - name: Require security team approval
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.pulls.requestReviewers({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.issue.number,
              team_reviewers: ['security-team', 'compliance-team']
            });
            
      - name: Create change control ticket
        run: ./scripts/create-change-ticket.sh
```

## System and Information Integrity (SI)

### SI.1.210 - Malicious Code Protection
**Requirement**: The organization implements malicious code protection mechanisms.

**GitHub Implementation**:
```yaml
name: Malicious Code Protection
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  malware-scanning:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          
      - name: Scan for malicious patterns
        run: |
          # Custom malware patterns
          grep -r "eval(" --include="*.js" --include="*.py" . || true
          grep -r "exec(" --include="*.py" . || true
          grep -r "shell_exec" --include="*.php" . || true
          
      - name: Virus scanning with ClamAV
        run: |
          sudo apt-get update
          sudo apt-get install -y clamav clamav-daemon
          sudo freshclam
          clamscan -r . --exclude-dir=.git
          
      - name: Secret scanning
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: main
          head: HEAD
          
      - name: Generate security report
        run: ./scripts/generate-malware-scan-report.sh
```

### SI.2.214 - Software Integrity Verification
**Requirement**: The organization verifies the integrity of software and information.

**Software Integrity Workflow**:
```yaml
name: Software Integrity Verification
on:
  push:
    branches: [main]
  release:
    types: [published]

jobs:
  integrity-verification:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        
      - name: Verify commit signatures
        run: |
          # Check that all commits are signed
          UNSIGNED_COMMITS=$(git log --pretty=format:'%H %G?' | grep -v ' G$' | grep -v ' U$')
          if [ -n "$UNSIGNED_COMMITS" ]; then
            echo "Error: Unsigned commits found:"
            echo "$UNSIGNED_COMMITS"
            exit 1
          fi
          
      - name: Verify dependency checksums
        run: |
          # Verify package-lock.json integrity
          if [ -f package-lock.json ]; then
            npm ci --audit
          fi
          
          # Verify requirements.txt with hash checking
          if [ -f requirements.txt ]; then
            pip install --require-hashes -r requirements.txt
          fi
          
      - name: Generate software bill of materials
        uses: anchore/sbom-action@v0
        with:
          path: ./
          format: spdx-json
          
      - name: Sign artifacts
        run: |
          # Sign release artifacts with GPG
          if [ "${{ github.event_name }}" == "release" ]; then
            ./scripts/sign-release-artifacts.sh
          fi
```

## Incident Response (IR)

### IR.1.072 - Incident Response Plan
**Requirement**: The organization develops and implements an incident response plan.

**Incident Response Automation**:
```yaml
name: Security Incident Response
on:
  issues:
    types: [opened]
  security_advisory:
    types: [published]
  workflow_run:
    workflows: ["Security Scanning"]
    types: [completed]
    
jobs:
  incident-detection:
    if: contains(github.event.issue.labels.*.name, 'security-incident') || github.event_name == 'security_advisory'
    runs-on: ubuntu-latest
    steps:
      - name: Classify incident severity
        id: classify
        run: |
          # Automated incident classification
          SEVERITY=$(./scripts/classify-incident-severity.sh)
          echo "severity=$SEVERITY" >> $GITHUB_OUTPUT
          
      - name: Immediate response actions
        if: steps.classify.outputs.severity == 'critical'
        run: |
          # Immediate containment actions
          ./scripts/emergency-containment.sh
          
      - name: Notify incident response team
        run: |
          # Send notifications to appropriate teams
          ./scripts/notify-incident-team.sh ${{ steps.classify.outputs.severity }}
          
      - name: Create incident tracking issue
        uses: actions/github-script@v7
        with:
          script: |
            const issue = await github.rest.issues.create({
              owner: context.repo.owner,
              repo: 'security-incidents',
              title: `Security Incident - ${context.payload.issue?.title || 'Auto-detected'}`,
              body: `Automated incident response triggered.\nSeverity: ${{ steps.classify.outputs.severity }}`,
              labels: ['incident-response', 'severity-${{ steps.classify.outputs.severity }}']
            });
            
  incident-investigation:
    needs: incident-detection
    runs-on: ubuntu-latest
    steps:
      - name: Collect forensic data
        run: ./scripts/collect-forensic-data.sh
        
      - name: Analyze security logs
        run: ./scripts/analyze-security-logs.sh
        
      - name: Generate incident timeline
        run: ./scripts/generate-incident-timeline.sh
```

### IR.2.083 - Security Incident Monitoring
**Requirement**: The organization monitors and documents security incidents.

**Continuous Security Monitoring**:
```yaml
name: Continuous Security Monitoring
on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes

jobs:
  security-monitoring:
    runs-on: ubuntu-latest
    steps:
      - name: Monitor audit logs
        run: |
          # Check for suspicious activities in audit logs
          SUSPICIOUS_EVENTS=$(gh api enterprises/$ENTERPRISE/audit-log \
            --field phrase="action:repo.destroy OR action:org.remove_member OR action:repo.add_member" \
            --field per_page=100 | \
            jq '.[] | select(.created_at > (now - 900))')  # Last 15 minutes
            
          if [ -n "$SUSPICIOUS_EVENTS" ]; then
            echo "Suspicious events detected:"
            echo "$SUSPICIOUS_EVENTS" | jq '.'
            ./scripts/trigger-security-alert.sh
          fi
          
      - name: Monitor failed authentication attempts
        run: |
          # Check for authentication failures
          FAILED_AUTHS=$(gh api enterprises/$ENTERPRISE/audit-log \
            --field phrase="action:oauth_access.deny OR action:org.oauth_app_access_denied" \
            --field per_page=100 | \
            jq '.[] | select(.created_at > (now - 900))')
            
          if [ -n "$FAILED_AUTHS" ]; then
            ./scripts/analyze-auth-failures.sh
          fi
          
      - name: Check security alert trends
        run: |
          # Analyze security alert patterns
          ./scripts/analyze-security-trends.sh
          
      - name: Update security dashboard
        run: ./scripts/update-security-dashboard.sh
```

## Audit and Accountability (AU)

### AU.2.041 - Audit Record Generation
**Requirement**: The organization generates audit records for events defined in the audit policy.

**Comprehensive Audit Logging**:
```yaml
name: Comprehensive Audit Logging
on:
  workflow_run:
    workflows: ["*"]
    types: [completed]
  push:
  pull_request:
  issues:
  deployment:

jobs:
  audit-logging:
    runs-on: ubuntu-latest
    steps:
      - name: Generate detailed audit record
        run: |
          # Create comprehensive audit record
          cat > audit_record.json << EOF
          {
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "event_type": "${{ github.event_name }}",
            "actor": "${{ github.actor }}",
            "repository": "${{ github.repository }}",
            "ref": "${{ github.ref }}",
            "sha": "${{ github.sha }}",
            "workflow": "${{ github.workflow }}",
            "run_id": "${{ github.run_id }}",
            "event_payload": $(echo '${{ toJson(github.event) }}' | jq -c .)
          }
          EOF
          
      - name: Validate audit record completeness
        run: ./scripts/validate-audit-record.sh audit_record.json
        
      - name: Store audit record
        run: |
          # Store in tamper-evident audit log
          ./scripts/store-audit-record.sh audit_record.json
          
      - name: Forward to SIEM
        run: |
          # Forward to external SIEM system
          ./scripts/forward-to-siem.sh audit_record.json
```

### AU.3.042 - Audit Record Content
**Requirement**: The organization ensures audit records contain sufficient information to establish the outcome of events.

**Enhanced Audit Record Structure**:
```json
{
  "audit_record_schema": {
    "version": "1.0",
    "required_fields": [
      "timestamp",
      "event_type",
      "actor_id",
      "actor_name",
      "source_ip",
      "user_agent",
      "resource_accessed",
      "action_performed",
      "outcome",
      "session_id",
      "correlation_id"
    ],
    "compliance_fields": {
      "hitrust": [
        "data_classification",
        "access_method",
        "authentication_method"
      ],
      "fedramp": [
        "security_label",
        "system_component",
        "control_correlation"
      ],
      "hipaa": [
        "phi_accessed",
        "minimum_necessary",
        "authorization_basis"
      ]
    }
  }
}
```

## Implementation Validation

### Automated Compliance Testing
```bash
#!/bin/bash
# scripts/validate-hitrust-implementation.sh

echo "HITRUST CSF Compliance Validation Report"
echo "========================================"
echo "Generated: $(date)"
echo ""

# Test each control implementation
CONTROLS=(
    "AC.1.007:validate-mfa-compliance.sh"
    "AC.1.020:validate-privileged-access.sh"
    "AC.2.002:validate-account-lifecycle.sh"
    "CM.1.061:validate-security-baseline.sh"
    "CM.2.063:validate-change-control.sh"
    "SI.1.210:validate-malware-protection.sh"
    "SI.2.214:validate-software-integrity.sh"
    "IR.1.072:validate-incident-response.sh"
    "IR.2.083:validate-security-monitoring.sh"
    "AU.2.041:validate-audit-logging.sh"
    "AU.3.042:validate-audit-content.sh"
)

PASSED=0
FAILED=0

for control in "${CONTROLS[@]}"; do
    IFS=':' read -r control_id script <<< "$control"
    echo "Testing $control_id..."
    
    if ./scripts/controls/$script; then
        echo "✅ PASS: $control_id"
        ((PASSED++))
    else
        echo "❌ FAIL: $control_id"
        ((FAILED++))
    fi
    echo ""
done

echo "Summary:"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Total: $((PASSED + FAILED))"
echo "Compliance Rate: $(( PASSED * 100 / (PASSED + FAILED) ))%"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
```

### Continuous Compliance Monitoring
```yaml
name: HITRUST Continuous Compliance
on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM
  workflow_dispatch:

jobs:
  hitrust-compliance-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout compliance scripts
        uses: actions/checkout@v4
        
      - name: Run HITRUST validation suite
        run: ./scripts/validate-hitrust-implementation.sh
        
      - name: Generate compliance report
        run: |
          ./scripts/generate-hitrust-report.sh > hitrust-compliance-report.md
          
      - name: Update compliance dashboard
        run: ./scripts/update-compliance-dashboard.sh hitrust
        
      - name: Create compliance issue if failures
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: 'HITRUST Compliance Failures Detected',
              body: 'Automated compliance testing has detected failures. Please review the compliance report.',
              labels: ['compliance', 'hitrust', 'urgent']
            });
```

## Control Implementation Checklist

### Phase 1: Critical Controls (Week 1-2)
- [ ] **AC.1.007**: Multi-factor authentication enabled organization-wide
- [ ] **AC.1.020**: Privileged access management implemented
- [ ] **CM.1.061**: Security baseline configuration established
- [ ] **SI.1.210**: Malicious code protection deployed

### Phase 2: Monitoring and Logging (Week 3-4)
- [ ] **IR.2.083**: Security incident monitoring operational
- [ ] **AU.2.041**: Comprehensive audit logging implemented
- [ ] **AU.3.042**: Audit record content validation

### Phase 3: Process Controls (Week 5-6)
- [ ] **AC.2.002**: Account lifecycle management automated
- [ ] **CM.2.063**: Change control procedures implemented
- [ ] **IR.1.072**: Incident response plan and automation

### Phase 4: Integrity and Validation (Week 7-8)
- [ ] **SI.2.214**: Software integrity verification
- [ ] Continuous compliance monitoring
- [ ] Validation and testing procedures

---

**Document Version**: 1.0  
**Control Framework**: HITRUST CSF v11.2.0  
**Last Updated**: [Current Date]  
**Next Review**: [Current Date + 3 months] 