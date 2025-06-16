#!/bin/bash

# Configuration Drift Detection Script
# Monitors GitHub Enterprise security configurations for unauthorized changes
# Supports HITRUST, FedRAMP, and HIPAA compliance requirements
# Usage: ./detect-configuration-drift.sh [options]

set -euo pipefail

# Script metadata
SCRIPT_NAME="Configuration Drift Detection"
VERSION="1.2.0"
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Configuration
BASELINE_DIR="${BASELINE_DIR:-./baselines}"
CURRENT_CONFIG_DIR="${CURRENT_CONFIG_DIR:-./current-configs}"
REPORTS_DIR="${REPORTS_DIR:-./drift-reports}"
ORG_NAME="${ORG_NAME:-}"
ENTERPRISE_NAME="${ENTERPRISE_NAME:-}"

# Compliance standards to check
COMPLIANCE_STANDARDS=("hitrust" "fedramp" "hipaa")

# Drift detection thresholds
CRITICAL_DRIFT_THRESHOLD=5
HIGH_DRIFT_THRESHOLD=10
MEDIUM_DRIFT_THRESHOLD=20

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_critical() { echo -e "${RED}[CRITICAL]${NC} $1" >&2; }

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Detects configuration drift in GitHub Enterprise security settings

OPTIONS:
    -o, --org ORG              GitHub organization name
    -e, --enterprise ENT       GitHub enterprise name
    -b, --baseline-dir DIR     Directory containing baseline configurations
    -c, --current-dir DIR      Directory for current configuration capture
    -r, --reports-dir DIR      Directory for drift reports
    -s, --standard STANDARD    Compliance standard (hitrust|fedramp|hipaa|all)
    -t, --threshold LEVEL      Alert threshold (critical|high|medium|low)
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    $0 --org myorg --standard all
    $0 --enterprise myenterprise --threshold critical
    $0 --baseline-dir ./security-baselines --reports-dir ./compliance-reports

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN               GitHub authentication token
    ORG_NAME                   GitHub organization name
    ENTERPRISE_NAME            GitHub enterprise name
    BASELINE_DIR               Baseline configurations directory
    SLACK_WEBHOOK_URL          Slack notification webhook (optional)
    TEAMS_WEBHOOK_URL          Microsoft Teams webhook (optional)
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--org)
                ORG_NAME="$2"
                shift 2
                ;;
            -e|--enterprise)
                ENTERPRISE_NAME="$2"
                shift 2
                ;;
            -b|--baseline-dir)
                BASELINE_DIR="$2"
                shift 2
                ;;
            -c|--current-dir)
                CURRENT_CONFIG_DIR="$2"
                shift 2
                ;;
            -r|--reports-dir)
                REPORTS_DIR="$2"
                shift 2
                ;;
            -s|--standard)
                if [[ "$2" == "all" ]]; then
                    COMPLIANCE_STANDARDS=("hitrust" "fedramp" "hipaa")
                else
                    COMPLIANCE_STANDARDS=("$2")
                fi
                shift 2
                ;;
            -t|--threshold)
                case "$2" in
                    critical) CRITICAL_DRIFT_THRESHOLD=1 ;;
                    high) HIGH_DRIFT_THRESHOLD=5 ;;
                    medium) MEDIUM_DRIFT_THRESHOLD=10 ;;
                    low) MEDIUM_DRIFT_THRESHOLD=50 ;;
                esac
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check GitHub CLI
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI not found. Install from https://cli.github.com/"
        exit 1
    fi
    
    # Check authentication
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI not authenticated. Run 'gh auth login'"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install jq for JSON processing"
        exit 1
    fi
    
    # Validate organization or enterprise
    if [[ -z "$ORG_NAME" && -z "$ENTERPRISE_NAME" ]]; then
        log_error "Either organization name or enterprise name must be provided"
        exit 1
    fi
    
    # Create necessary directories
    mkdir -p "$BASELINE_DIR" "$CURRENT_CONFIG_DIR" "$REPORTS_DIR"
    
    log_success "Prerequisites validated"
}

# Capture current organization configuration
capture_organization_config() {
    local target="${ORG_NAME:-$ENTERPRISE_NAME}"
    local api_path
    
    if [[ -n "$ORG_NAME" ]]; then
        api_path="orgs/$ORG_NAME"
    else
        api_path="enterprises/$ENTERPRISE_NAME"
    fi
    
    log_info "Capturing current organization configuration..."
    
    # Base organization settings
    gh api "$api_path" > "$CURRENT_CONFIG_DIR/org_settings.json"
    
    # Security and analysis settings
    if [[ -n "$ORG_NAME" ]]; then
        gh api "orgs/$ORG_NAME/settings/security_and_analysis" 2>/dev/null > "$CURRENT_CONFIG_DIR/security_analysis.json" || echo "{}" > "$CURRENT_CONFIG_DIR/security_analysis.json"
    fi
    
    # IP allowlist
    gh api "$api_path/settings/ip_allowlist" 2>/dev/null > "$CURRENT_CONFIG_DIR/ip_allowlist.json" || echo "[]" > "$CURRENT_CONFIG_DIR/ip_allowlist.json"
    
    # OAuth app restrictions
    gh api "$api_path/settings/oauth_app_access_restrictions" 2>/dev/null > "$CURRENT_CONFIG_DIR/oauth_restrictions.json" || echo "{}" > "$CURRENT_CONFIG_DIR/oauth_restrictions.json"
}

# Capture current repository configurations
capture_repository_configs() {
    log_info "Capturing current repository configurations..."
    
    local repos_file="$CURRENT_CONFIG_DIR/repositories.json"
    echo "[]" > "$repos_file"
    
    # Get all repositories
    local repos
    if [[ -n "$ORG_NAME" ]]; then
        repos=$(gh repo list "$ORG_NAME" --limit 1000 --json name,isPrivate,defaultBranchRef)
    else
        # For enterprises, we need to iterate through organizations
        repos=$(gh api "enterprises/$ENTERPRISE_NAME/organizations" --paginate | jq -r '.[].login' | while read org; do
            gh repo list "$org" --limit 1000 --json name,isPrivate,defaultBranchRef | jq --arg org "$org" 'map(. + {organization: $org})'
        done | jq -s 'add // []')
    fi
    
    echo "$repos" > "$repos_file"
    
    # Capture detailed configuration for each repository
    echo "$repos" | jq -r '.[] | "\(.organization // "'"$ORG_NAME"'")|\(.name)"' | while IFS='|' read org repo; do
        log_info "Capturing config for $org/$repo..."
        
        local repo_dir="$CURRENT_CONFIG_DIR/repositories/$org"
        mkdir -p "$repo_dir"
        
        # Repository settings
        gh api "repos/$org/$repo" > "$repo_dir/${repo}_settings.json"
        
        # Branch protection
        local default_branch
        default_branch=$(jq -r '.defaultBranchRef.name // "main"' "$repos_file" | head -1)
        gh api "repos/$org/$repo/branches/$default_branch/protection" 2>/dev/null > "$repo_dir/${repo}_branch_protection.json" || echo "{}" > "$repo_dir/${repo}_branch_protection.json"
        
        # Security and analysis
        gh api "repos/$org/$repo" | jq '.security_and_analysis // {}' > "$repo_dir/${repo}_security_analysis.json"
        
        # Collaborators and teams
        gh api "repos/$org/$repo/collaborators" --paginate 2>/dev/null > "$repo_dir/${repo}_collaborators.json" || echo "[]" > "$repo_dir/${repo}_collaborators.json"
        gh api "repos/$org/$repo/teams" --paginate 2>/dev/null > "$repo_dir/${repo}_teams.json" || echo "[]" > "$repo_dir/${repo}_teams.json"
    done
}

# Capture team configurations
capture_team_configs() {
    log_info "Capturing current team configurations..."
    
    local teams_file="$CURRENT_CONFIG_DIR/teams.json"
    
    if [[ -n "$ORG_NAME" ]]; then
        gh api "orgs/$ORG_NAME/teams" --paginate > "$teams_file"
    else
        # For enterprises, iterate through organizations
        gh api "enterprises/$ENTERPRISE_NAME/organizations" --paginate | jq -r '.[].login' | while read org; do
            gh api "orgs/$org/teams" --paginate | jq --arg org "$org" 'map(. + {organization: $org})'
        done | jq -s 'add // []' > "$teams_file"
    fi
    
    # Detailed team configurations
    jq -r '.[] | "\(.organization // "'"$ORG_NAME"'")|\(.slug)"' "$teams_file" | while IFS='|' read org team; do
        local team_dir="$CURRENT_CONFIG_DIR/teams/$org"
        mkdir -p "$team_dir"
        
        # Team details
        gh api "orgs/$org/teams/$team" > "$team_dir/${team}_details.json"
        
        # Team members
        gh api "orgs/$org/teams/$team/members" --paginate > "$team_dir/${team}_members.json"
        
        # Team repositories
        gh api "orgs/$org/teams/$team/repos" --paginate > "$team_dir/${team}_repos.json"
    done
}

# Compare configurations and detect drift
detect_configuration_drift() {
    log_info "Detecting configuration drift..."
    
    local drift_detected=false
    local drift_summary="{}"
    
    # Organization-level drift detection
    if detect_organization_drift; then
        drift_detected=true
    fi
    
    # Repository-level drift detection
    if detect_repository_drift; then
        drift_detected=true
    fi
    
    # Team-level drift detection
    if detect_team_drift; then
        drift_detected=true
    fi
    
    # Generate comprehensive drift report
    generate_drift_report "$drift_detected"
    
    return $([ "$drift_detected" = true ] && echo 1 || echo 0)
}

# Detect organization-level drift
detect_organization_drift() {
    log_info "Detecting organization-level configuration drift..."
    
    local baseline_file="$BASELINE_DIR/org_settings.json"
    local current_file="$CURRENT_CONFIG_DIR/org_settings.json"
    local drift_file="$REPORTS_DIR/org_drift.json"
    
    if [[ ! -f "$baseline_file" ]]; then
        log_warn "No organization baseline found. Creating baseline from current config."
        cp "$current_file" "$baseline_file"
        return 1
    fi
    
    # Compare configurations
    local drift_items="[]"
    local critical_settings=(
        "two_factor_requirement_enabled"
        "members_can_create_repositories"
        "members_can_create_public_repositories"
        "default_repository_permission"
    )
    
    for setting in "${critical_settings[@]}"; do
        local baseline_value current_value
        baseline_value=$(jq -r ".$setting // null" "$baseline_file")
        current_value=$(jq -r ".$setting // null" "$current_file")
        
        if [[ "$baseline_value" != "$current_value" ]]; then
            log_warn "Drift detected in $setting: $baseline_value -> $current_value"
            
            local drift_item
            drift_item=$(jq -n \
                --arg setting "$setting" \
                --arg baseline "$baseline_value" \
                --arg current "$current_value" \
                --arg severity "$(determine_drift_severity "$setting")" \
                '{
                    setting: $setting,
                    baseline_value: $baseline,
                    current_value: $current,
                    severity: $severity,
                    detected_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
                }')
            
            drift_items=$(echo "$drift_items" | jq ". + [$drift_item]")
        fi
    done
    
    # Save drift report
    echo "$drift_items" > "$drift_file"
    
    local drift_count
    drift_count=$(echo "$drift_items" | jq 'length')
    
    return $([ "$drift_count" -gt 0 ] && echo 0 || echo 1)
}

# Detect repository-level drift
detect_repository_drift() {
    log_info "Detecting repository-level configuration drift..."
    
    local repo_drift_detected=false
    local repos_drift_file="$REPORTS_DIR/repositories_drift.json"
    echo "[]" > "$repos_drift_file"
    
    # Check each repository for drift
    find "$CURRENT_CONFIG_DIR/repositories" -name "*_settings.json" | while read current_repo_file; do
        local repo_name
        repo_name=$(basename "$current_repo_file" "_settings.json")
        
        local org_name
        org_name=$(dirname "$current_repo_file" | xargs basename)
        
        local baseline_repo_file="$BASELINE_DIR/repositories/$org_name/${repo_name}_settings.json"
        
        if [[ ! -f "$baseline_repo_file" ]]; then
            log_info "No baseline for $org_name/$repo_name. Creating baseline."
            mkdir -p "$(dirname "$baseline_repo_file")"
            cp "$current_repo_file" "$baseline_repo_file"
            continue
        fi
        
        # Compare repository security settings
        local security_drift
        security_drift=$(compare_repository_security "$baseline_repo_file" "$current_repo_file" "$org_name/$repo_name")
        
        if [[ "$security_drift" != "[]" ]]; then
            repo_drift_detected=true
            # Append to repositories drift report
            local current_drift
            current_drift=$(cat "$repos_drift_file")
            echo "$current_drift" | jq ". + $security_drift" > "$repos_drift_file"
        fi
    done
    
    return $([ "$repo_drift_detected" = true ] && echo 0 || echo 1)
}

# Compare repository security settings
compare_repository_security() {
    local baseline_file="$1"
    local current_file="$2"
    local repo_name="$3"
    
    local drift_items="[]"
    local security_settings=(
        "has_vulnerability_alerts"
        "security_and_analysis.secret_scanning.status"
        "security_and_analysis.secret_scanning_push_protection.status"
        "security_and_analysis.automated_security_fixes.status"
        "private"
    )
    
    for setting in "${security_settings[@]}"; do
        local baseline_value current_value
        baseline_value=$(jq -r ".$setting // null" "$baseline_file")
        current_value=$(jq -r ".$setting // null" "$current_file")
        
        if [[ "$baseline_value" != "$current_value" ]]; then
            local drift_item
            drift_item=$(jq -n \
                --arg repo "$repo_name" \
                --arg setting "$setting" \
                --arg baseline "$baseline_value" \
                --arg current "$current_value" \
                --arg severity "$(determine_drift_severity "$setting")" \
                '{
                    repository: $repo,
                    setting: $setting,
                    baseline_value: $baseline,
                    current_value: $current,
                    severity: $severity,
                    detected_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
                }')
            
            drift_items=$(echo "$drift_items" | jq ". + [$drift_item]")
        fi
    done
    
    echo "$drift_items"
}

# Detect team-level drift
detect_team_drift() {
    log_info "Detecting team-level configuration drift..."
    
    # Compare team configurations
    local teams_baseline="$BASELINE_DIR/teams.json"
    local teams_current="$CURRENT_CONFIG_DIR/teams.json"
    local teams_drift_file="$REPORTS_DIR/teams_drift.json"
    
    if [[ ! -f "$teams_baseline" ]]; then
        log_warn "No teams baseline found. Creating baseline."
        cp "$teams_current" "$teams_baseline"
        echo "[]" > "$teams_drift_file"
        return 1
    fi
    
    # Compare team membership and permissions
    local drift_items="[]"
    
    # Check for new teams
    local new_teams
    new_teams=$(jq --slurpfile baseline "$teams_baseline" '
        .[] | select(.slug as $slug | $baseline[0] | map(.slug) | index($slug) | not)
    ' "$teams_current")
    
    if [[ "$new_teams" != "" ]]; then
        echo "$new_teams" | jq -s '.[] | {
            team: .slug,
            change_type: "team_added",
            severity: "medium",
            detected_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }' | while read -r drift_item; do
            drift_items=$(echo "$drift_items" | jq ". + [$drift_item]")
        done
    fi
    
    # Check for removed teams
    local removed_teams
    removed_teams=$(jq --slurpfile current "$teams_current" '
        .[] | select(.slug as $slug | $current[0] | map(.slug) | index($slug) | not)
    ' "$teams_baseline")
    
    if [[ "$removed_teams" != "" ]]; then
        echo "$removed_teams" | jq -s '.[] | {
            team: .slug,
            change_type: "team_removed",
            severity: "high",
            detected_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }' | while read -r drift_item; do
            drift_items=$(echo "$drift_items" | jq ". + [$drift_item]")
        done
    fi
    
    echo "$drift_items" > "$teams_drift_file"
    
    local drift_count
    drift_count=$(echo "$drift_items" | jq 'length')
    
    return $([ "$drift_count" -gt 0 ] && echo 0 || echo 1)
}

# Determine drift severity based on setting
determine_drift_severity() {
    local setting="$1"
    
    case "$setting" in
        "two_factor_requirement_enabled"|"private"|"secret_scanning"|"security_and_analysis"*)
            echo "critical"
            ;;
        "members_can_create_public_repositories"|"has_vulnerability_alerts")
            echo "high"
            ;;
        "default_repository_permission"|"members_can_create_repositories")
            echo "medium"
            ;;
        *)
            echo "low"
            ;;
    esac
}

# Generate comprehensive drift report
generate_drift_report() {
    local drift_detected="$1"
    
    log_info "Generating comprehensive drift report..."
    
    local report_file="$REPORTS_DIR/configuration_drift_report.json"
    local summary_file="$REPORTS_DIR/drift_summary.json"
    
    # Collect all drift data
    local org_drift="[]"
    local repo_drift="[]"
    local team_drift="[]"
    
    [[ -f "$REPORTS_DIR/org_drift.json" ]] && org_drift=$(cat "$REPORTS_DIR/org_drift.json")
    [[ -f "$REPORTS_DIR/repositories_drift.json" ]] && repo_drift=$(cat "$REPORTS_DIR/repositories_drift.json")
    [[ -f "$REPORTS_DIR/teams_drift.json" ]] && team_drift=$(cat "$REPORTS_DIR/teams_drift.json")
    
    # Calculate severity counts
    local total_drift
    total_drift=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | length')
    
    local critical_count high_count medium_count low_count
    critical_count=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | map(select(.severity == "critical")) | length')
    high_count=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | map(select(.severity == "high")) | length')
    medium_count=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | map(select(.severity == "medium")) | length')
    low_count=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | map(select(.severity == "low")) | length')
    
    # Generate compliance impact assessment
    local compliance_impact
    compliance_impact=$(assess_compliance_impact "$org_drift" "$repo_drift" "$team_drift")
    
    # Create comprehensive report
    jq -n \
        --arg detected "$drift_detected" \
        --arg total "$total_drift" \
        --arg critical "$critical_count" \
        --arg high "$high_count" \
        --arg medium "$medium_count" \
        --arg low "$low_count" \
        --argjson org_drift "$org_drift" \
        --argjson repo_drift "$repo_drift" \
        --argjson team_drift "$team_drift" \
        --argjson compliance_impact "$compliance_impact" \
        '{
            report_metadata: {
                generated_at: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
                script_version: "'"$VERSION"'",
                organization: "'"${ORG_NAME:-$ENTERPRISE_NAME}"'",
                drift_detected: ($detected == "true")
            },
            summary: {
                total_drift_items: ($total | tonumber),
                severity_breakdown: {
                    critical: ($critical | tonumber),
                    high: ($high | tonumber),
                    medium: ($medium | tonumber),
                    low: ($low | tonumber)
                }
            },
            drift_details: {
                organization_drift: $org_drift,
                repository_drift: $repo_drift,
                team_drift: $team_drift
            },
            compliance_impact: $compliance_impact,
            recommendations: [
                "Review and approve all configuration changes",
                "Update security baselines if changes are authorized",
                "Implement stronger change controls for critical settings",
                "Increase monitoring frequency for high-risk configurations"
            ]
        }' > "$report_file"
    
    # Generate executive summary
    jq '.summary + {generated_at: .report_metadata.generated_at}' "$report_file" > "$summary_file"
    
    # Display summary
    display_drift_summary "$report_file"
    
    # Send notifications if drift detected
    if [[ "$drift_detected" = "true" ]]; then
        send_drift_notifications "$report_file"
    fi
}

# Assess compliance impact
assess_compliance_impact() {
    local org_drift="$1"
    local repo_drift="$2"
    local team_drift="$3"
    
    local hitrust_impact="low"
    local fedramp_impact="low"
    local hipaa_impact="low"
    
    # Assess impact based on critical configuration changes
    local critical_changes
    critical_changes=$(echo "$org_drift $repo_drift $team_drift" | jq -s 'add | map(select(.severity == "critical")) | length')
    
    if [[ "$critical_changes" -gt 0 ]]; then
        hitrust_impact="high"
        fedramp_impact="high"
        hipaa_impact="high"
    fi
    
    jq -n \
        --arg hitrust "$hitrust_impact" \
        --arg fedramp "$fedramp_impact" \
        --arg hipaa "$hipaa_impact" \
        --arg critical "$critical_changes" \
        '{
            hitrust_csf: {
                impact_level: $hitrust,
                affected_controls: ["AC.1.007", "CM.1.061", "SI.1.210"]
            },
            fedramp: {
                impact_level: $fedramp,
                affected_controls: ["AC-2", "CM-2", "CM-3"]
            },
            hipaa: {
                impact_level: $hipaa,
                affected_controls: ["164.308(a)(1)", "164.312(a)(1)"]
            },
            critical_changes_detected: ($critical | tonumber)
        }'
}

# Display drift summary
display_drift_summary() {
    local report_file="$1"
    
    local total_drift critical_count high_count
    total_drift=$(jq -r '.summary.total_drift_items' "$report_file")
    critical_count=$(jq -r '.summary.severity_breakdown.critical' "$report_file")
    high_count=$(jq -r '.summary.severity_breakdown.high' "$report_file")
    
    echo
    echo "=== Configuration Drift Detection Summary ==="
    echo "Total Drift Items: $total_drift"
    echo "Critical: $critical_count"
    echo "High: $high_count"
    echo
    
    if [[ "$total_drift" -gt 0 ]]; then
        if [[ "$critical_count" -gt 0 ]]; then
            log_critical "Critical configuration drift detected! Immediate attention required."
        elif [[ "$high_count" -gt 0 ]]; then
            log_error "High severity configuration drift detected."
        else
            log_warn "Configuration drift detected."
        fi
        
        echo "Detailed report: $report_file"
        echo "Executive summary: $REPORTS_DIR/drift_summary.json"
    else
        log_success "No configuration drift detected."
    fi
}

# Send drift notifications
send_drift_notifications() {
    local report_file="$1"
    
    log_info "Sending drift notifications..."
    
    # Create GitHub issue if in a repository context
    if [[ -n "$GITHUB_REPOSITORY" ]]; then
        create_drift_issue "$report_file"
    fi
    
    # Send Slack notification if webhook configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        send_slack_notification "$report_file"
    fi
    
    # Send Teams notification if webhook configured
    if [[ -n "${TEAMS_WEBHOOK_URL:-}" ]]; then
        send_teams_notification "$report_file"
    fi
    
    # Send email notification if configured
    if [[ -n "${EMAIL_NOTIFICATION_LIST:-}" ]]; then
        send_email_notification "$report_file"
    fi
}

# Create GitHub issue for drift
create_drift_issue() {
    local report_file="$1"
    
    local total_drift critical_count
    total_drift=$(jq -r '.summary.total_drift_items' "$report_file")
    critical_count=$(jq -r '.summary.severity_breakdown.critical' "$report_file")
    
    local severity_label
    if [[ "$critical_count" -gt 0 ]]; then
        severity_label="critical"
    elif [[ "$(jq -r '.summary.severity_breakdown.high' "$report_file")" -gt 0 ]]; then
        severity_label="high"
    else
        severity_label="medium"
    fi
    
    local issue_body
    issue_body=$(cat << EOF
## Configuration Drift Detected

**Total Drift Items**: $total_drift  
**Critical Issues**: $critical_count  
**Detection Time**: $(date)

### Summary
Configuration drift has been detected in the GitHub Enterprise security settings. This may indicate unauthorized changes or configuration inconsistencies that require immediate review.

### Severity Breakdown
$(jq -r '.summary.severity_breakdown | to_entries | map("- **\(.key | ascii_upcase)**: \(.value)") | join("\n")' "$report_file")

### Compliance Impact
$(jq -r '.compliance_impact | to_entries | map("- **\(.key | ascii_upcase)**: \(.value.impact_level)") | join("\n")' "$report_file")

### Next Steps
1. Review the detailed drift report
2. Validate if changes were authorized
3. Update security baselines if changes are approved
4. Remediate unauthorized changes immediately

### Report Location
Full report available in workflow artifacts or at: \`$report_file\`
EOF
)
    
    # Create issue using GitHub CLI
    gh issue create \
        --title "🚨 Configuration Drift Detected - $severity_label Severity" \
        --body "$issue_body" \
        --label "security,compliance,configuration-drift,$severity_label" \
        --assignee "@me" || log_warn "Failed to create GitHub issue"
}

# Send Slack notification
send_slack_notification() {
    local report_file="$1"
    
    local total_drift critical_count
    total_drift=$(jq -r '.summary.total_drift_items' "$report_file")
    critical_count=$(jq -r '.summary.severity_breakdown.critical' "$report_file")
    
    local color="warning"
    [[ "$critical_count" -gt 0 ]] && color="danger"
    
    local payload
    payload=$(jq -n \
        --arg text "Configuration Drift Detected" \
        --arg color "$color" \
        --arg total "$total_drift" \
        --arg critical "$critical_count" \
        --arg org "${ORG_NAME:-$ENTERPRISE_NAME}" \
        '{
            text: $text,
            attachments: [{
                color: $color,
                title: "GitHub Enterprise Configuration Drift Alert",
                fields: [
                    {title: "Organization", value: $org, short: true},
                    {title: "Total Drift Items", value: $total, short: true},
                    {title: "Critical Issues", value: $critical, short: true},
                    {title: "Detection Time", value: now | strftime("%Y-%m-%d %H:%M:%S UTC"), short: true}
                ],
                footer: "Configuration Drift Monitor"
            }]
        }')
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" || log_warn "Failed to send Slack notification"
}

# Main execution function
main() {
    echo "Starting Configuration Drift Detection v$VERSION"
    echo "Timestamp: $DATE"
    echo
    
    parse_arguments "$@"
    validate_prerequisites
    
    # Capture current configurations
    capture_organization_config
    capture_repository_configs
    capture_team_configs
    
    # Detect drift and generate reports
    if detect_configuration_drift; then
        log_error "Configuration drift detected!"
        exit 1
    else
        log_success "No configuration drift detected."
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 