#!/bin/bash

# Multi-Factor Authentication Compliance Validation Script
# Validates MFA requirements across HITRUST, FedRAMP, and HIPAA standards
# Usage: ./validate-mfa-compliance.sh --standard [hitrust|fedramp|hipaa|all] --output [file]

set -euo pipefail

# Script configuration
SCRIPT_NAME="MFA Compliance Validator"
VERSION="1.0.0"
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Default values
STANDARD="all"
OUTPUT_FILE=""
ORG_NAME="${ORG_NAME:-}"
VERBOSE=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Compliance requirements by standard
declare -A MFA_REQUIREMENTS=(
    ["hitrust"]="AC.1.007 - Multi-factor authentication required for all users"
    ["fedramp"]="IA-2(1) - Identification and Authentication (Organizational Users) | Network Access to Privileged Accounts"
    ["hipaa"]="164.312(d) - Person or Entity Authentication"
)

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Validates multi-factor authentication compliance across security standards"
    echo ""
    echo "OPTIONS:"
    echo "  -s, --standard STANDARD    Compliance standard to validate (hitrust|fedramp|hipaa|all)"
    echo "  -o, --output FILE         Output file for compliance report (JSON format)"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -d, --dry-run             Perform validation without making changes"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  ORG_NAME                  GitHub organization name (required)"
    echo "  GITHUB_TOKEN              GitHub personal access token (required)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 --standard hitrust --output hitrust-mfa-report.json"
    echo "  $0 --standard all --verbose"
    echo "  ORG_NAME=myorg $0 --standard fedramp"
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1" >&2
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--standard)
                STANDARD="$2"
                if [[ ! "$STANDARD" =~ ^(hitrust|fedramp|hipaa|all)$ ]]; then
                    log_error "Invalid standard: $STANDARD. Must be one of: hitrust, fedramp, hipaa, all"
                    exit 1
                fi
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
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
    
    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com/"
        exit 1
    fi
    
    # Check if logged in to GitHub CLI
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub CLI. Please run 'gh auth login'"
        exit 1
    fi
    
    # Check organization name
    if [ -z "$ORG_NAME" ]; then
        log_error "Organization name not provided. Set ORG_NAME environment variable or use GitHub repository context"
        exit 1
    fi
    
    # Validate organization exists and user has access
    if ! gh api "orgs/$ORG_NAME" &> /dev/null; then
        log_error "Cannot access organization '$ORG_NAME'. Check permissions and organization name."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Check organization MFA requirement
check_org_mfa_requirement() {
    log_info "Checking organization MFA requirement..."
    
    local org_info
    org_info=$(gh api "orgs/$ORG_NAME" --jq '{
        two_factor_requirement_enabled: .two_factor_requirement_enabled,
        saml_enabled: .has_organization_projects,
        created_at: .created_at,
        updated_at: .updated_at
    }')
    
    local mfa_required
    mfa_required=$(echo "$org_info" | jq -r '.two_factor_requirement_enabled')
    
    if [ "$mfa_required" = "true" ]; then
        log_success "Organization MFA requirement is enabled"
        echo "$org_info" | jq '. + {status: "compliant", message: "Organization MFA requirement enabled"}'
    else
        log_error "Organization MFA requirement is NOT enabled"
        echo "$org_info" | jq '. + {status: "non-compliant", message: "Organization MFA requirement disabled"}'
    fi
}

# Check individual user MFA status
check_user_mfa_status() {
    log_info "Checking individual user MFA status..."
    
    local users_data="[]"
    local page=1
    local per_page=100
    
    while true; do
        log_verbose "Fetching users page $page..."
        
        local page_data
        page_data=$(gh api "orgs/$ORG_NAME/members" \
            --field per_page=$per_page \
            --field page=$page \
            --jq 'map({
                login: .login,
                id: .id,
                site_admin: .site_admin,
                type: .type,
                two_factor_authentication: (.two_factor_authentication // false)
            })')
        
        # Break if no more data
        if [ "$(echo "$page_data" | jq 'length')" -eq 0 ]; then
            break
        fi
        
        # Append to users data
        users_data=$(echo "$users_data $page_data" | jq -s 'add')
        
        ((page++))
    done
    
    local total_users
    total_users=$(echo "$users_data" | jq 'length')
    
    local users_with_mfa
    users_with_mfa=$(echo "$users_data" | jq '[.[] | select(.two_factor_authentication == true)] | length')
    
    local users_without_mfa
    users_without_mfa=$(echo "$users_data" | jq '[.[] | select(.two_factor_authentication == false)]')
    
    local mfa_compliance_rate
    if [ "$total_users" -gt 0 ]; then
        mfa_compliance_rate=$(echo "scale=2; $users_with_mfa * 100 / $total_users" | bc)
    else
        mfa_compliance_rate="0"
    fi
    
    log_info "MFA Status Summary:"
    log_info "  Total users: $total_users"
    log_info "  Users with MFA: $users_with_mfa"
    log_info "  Users without MFA: $(echo "$users_without_mfa" | jq 'length')"
    log_info "  MFA compliance rate: ${mfa_compliance_rate}%"
    
    if [ "$(echo "$users_without_mfa" | jq 'length')" -gt 0 ]; then
        log_warn "Users without MFA:"
        echo "$users_without_mfa" | jq -r '.[] | "  - " + .login + " (" + .type + ")"' >&2
    fi
    
    # Return comprehensive user data with compliance assessment
    echo "$users_data" | jq --arg rate "$mfa_compliance_rate" '{
        total_users: length,
        users_with_mfa: [.[] | select(.two_factor_authentication == true)] | length,
        users_without_mfa: [.[] | select(.two_factor_authentication == false)],
        compliance_rate: ($rate | tonumber),
        status: (if ($rate | tonumber) == 100 then "compliant" else "non-compliant" end),
        users: .
    }'
}

# Check SAML SSO configuration for enhanced security
check_saml_sso_config() {
    log_info "Checking SAML SSO configuration..."
    
    # Note: SAML SSO information is limited via API
    local saml_info
    saml_info=$(gh api "orgs/$ORG_NAME" --jq '{
        saml_enabled: .has_organization_projects,
        name: .name,
        login: .login
    }')
    
    # Try to get more detailed SAML information (requires additional permissions)
    local saml_details="{}"
    if gh api "orgs/$ORG_NAME/credential-authorizations" &> /dev/null; then
        saml_details=$(gh api "orgs/$ORG_NAME/credential-authorizations" --jq 'length')
    fi
    
    echo "$saml_info" | jq --argjson details "$saml_details" '. + {
        saml_authorizations: $details,
        status: "info",
        message: "SAML SSO status requires manual verification"
    }'
}

# Check team-based access controls
check_team_access_controls() {
    log_info "Checking team-based access controls..."
    
    local teams_data
    teams_data=$(gh api "orgs/$ORG_NAME/teams" --paginate --jq 'map({
        name: .name,
        slug: .slug,
        privacy: .privacy,
        members_count: .members_count,
        repos_count: .repos_count,
        created_at: .created_at
    })')
    
    local total_teams
    total_teams=$(echo "$teams_data" | jq 'length')
    
    local private_teams
    private_teams=$(echo "$teams_data" | jq '[.[] | select(.privacy == "closed")] | length')
    
    log_info "Team access summary:"
    log_info "  Total teams: $total_teams"
    log_info "  Private teams: $private_teams"
    
    echo "$teams_data" | jq --arg total "$total_teams" --arg private "$private_teams" '{
        total_teams: ($total | tonumber),
        private_teams: ($private | tonumber),
        teams: .,
        status: "info",
        message: "Team access controls configured"
    }'
}

# Generate compliance assessment based on standard
generate_compliance_assessment() {
    local standard="$1"
    local org_mfa="$2"
    local user_mfa="$3"
    local saml_config="$4"
    local team_access="$5"
    
    log_info "Generating compliance assessment for $standard..."
    
    local org_compliant
    org_compliant=$(echo "$org_mfa" | jq -r '.status == "compliant"')
    
    local user_compliance_rate
    user_compliance_rate=$(echo "$user_mfa" | jq -r '.compliance_rate')
    
    local overall_status="non-compliant"
    local recommendations=()
    local score=0
    
    # Calculate compliance score
    if [ "$org_compliant" = "true" ]; then
        score=$((score + 50))
    else
        recommendations+=("Enable organization-wide MFA requirement")
    fi
    
    if (( $(echo "$user_compliance_rate == 100" | bc -l) )); then
        score=$((score + 50))
    else
        recommendations+=("Ensure all users enable MFA")
    fi
    
    # Determine overall status
    if [ "$score" -eq 100 ]; then
        overall_status="compliant"
    elif [ "$score" -ge 75 ]; then
        overall_status="mostly-compliant"
    elif [ "$score" -ge 50 ]; then
        overall_status="partially-compliant"
    fi
    
    # Standard-specific requirements
    case "$standard" in
        "hitrust")
            # HITRUST requires comprehensive MFA for all access
            if [ "$overall_status" != "compliant" ]; then
                recommendations+=("HITRUST AC.1.007 requires MFA for all users accessing sensitive data")
            fi
            ;;
        "fedramp")
            # FedRAMP requires MFA for privileged accounts
            recommendations+=("Verify privileged accounts have MFA enabled")
            recommendations+=("Configure session timeout for enhanced security")
            ;;
        "hipaa")
            # HIPAA requires person/entity authentication
            if [ "$overall_status" != "compliant" ]; then
                recommendations+=("HIPAA 164.312(d) requires unique user identification and authentication")
            fi
            ;;
    esac
    
    # Generate recommendations JSON array
    local recommendations_json
    recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R . | jq -s .)
    
    jq -n \
        --arg standard "$standard" \
        --arg requirement "${MFA_REQUIREMENTS[$standard]}" \
        --arg status "$overall_status" \
        --arg score "$score" \
        --argjson recommendations "$recommendations_json" \
        --argjson org_mfa "$org_mfa" \
        --argjson user_mfa "$user_mfa" \
        --argjson saml_config "$saml_config" \
        --argjson team_access "$team_access" \
        '{
            standard: $standard,
            requirement: $requirement,
            assessment: {
                overall_status: $status,
                compliance_score: ($score | tonumber),
                recommendations: $recommendations
            },
            findings: {
                organization_mfa: $org_mfa,
                user_mfa_status: $user_mfa,
                saml_configuration: $saml_config,
                team_access_controls: $team_access
            },
            metadata: {
                generated_at: "'"$DATE"'",
                script_version: "'"$VERSION"'",
                organization: "'"$ORG_NAME"'"
            }
        }'
}

# Main validation function
validate_mfa_compliance() {
    log_info "Starting MFA compliance validation for organization: $ORG_NAME"
    log_info "Standard(s): $STANDARD"
    
    # Collect compliance data
    local org_mfa_result
    org_mfa_result=$(check_org_mfa_requirement)
    
    local user_mfa_result
    user_mfa_result=$(check_user_mfa_status)
    
    local saml_config_result
    saml_config_result=$(check_saml_sso_config)
    
    local team_access_result
    team_access_result=$(check_team_access_controls)
    
    # Generate compliance reports
    local compliance_reports="[]"
    
    if [ "$STANDARD" = "all" ]; then
        for std in hitrust fedramp hipaa; do
            local assessment
            assessment=$(generate_compliance_assessment "$std" "$org_mfa_result" "$user_mfa_result" "$saml_config_result" "$team_access_result")
            compliance_reports=$(echo "$compliance_reports" | jq ". + [$assessment]")
        done
    else
        local assessment
        assessment=$(generate_compliance_assessment "$STANDARD" "$org_mfa_result" "$user_mfa_result" "$saml_config_result" "$team_access_result")
        compliance_reports=$(echo "$compliance_reports" | jq ". + [$assessment]")
    fi
    
    # Generate final report
    local final_report
    final_report=$(jq -n \
        --argjson reports "$compliance_reports" \
        '{
            report_type: "mfa_compliance_validation",
            generated_at: "'"$DATE"'",
            organization: "'"$ORG_NAME"'",
            standards_assessed: ['"$(if [ "$STANDARD" = "all" ]; then echo '"hitrust","fedramp","hipaa"'; else echo "\"$STANDARD\""; fi)"'],
            compliance_reports: $reports,
            summary: {
                total_standards: ($reports | length),
                compliant_standards: ($reports | map(select(.assessment.overall_status == "compliant")) | length),
                average_score: ($reports | map(.assessment.compliance_score) | add / length)
            }
        }')
    
    # Output results
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$final_report" > "$OUTPUT_FILE"
        log_success "Compliance report saved to: $OUTPUT_FILE"
    else
        echo "$final_report"
    fi
    
    # Return appropriate exit code
    local compliant_count
    compliant_count=$(echo "$final_report" | jq '.summary.compliant_standards')
    local total_count
    total_count=$(echo "$final_report" | jq '.summary.total_standards')
    
    if [ "$compliant_count" -eq "$total_count" ]; then
        log_success "All standards are compliant"
        return 0
    else
        log_warn "Some standards are not fully compliant"
        return 1
    fi
}

# Main execution
main() {
    parse_args "$@"
    validate_prerequisites
    validate_mfa_compliance
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 