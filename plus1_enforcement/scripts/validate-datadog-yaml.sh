#!/bin/bash

# Plus1 Enforcement - Datadog YAML Validation Script
# Validates entity.datadog.yaml files for v3.0 schema compliance and lifecycle extraction

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_YAML_PATH="entity.datadog.yaml"
EXPECTED_API_VERSION="v3.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <repository_path>

Validates entity.datadog.yaml files for Plus1 Enforcement compliance.

OPTIONS:
    -f, --file PATH         Path to Datadog YAML file (default: entity.datadog.yaml)
    -v, --verbose          Enable verbose output
    -j, --json             Output results in JSON format
    -q, --quiet            Suppress all output except errors
    -h, --help             Show this help message

EXAMPLES:
    $0 /path/to/repository
    $0 --file custom.yaml /path/to/repo
    $0 --json /path/to/repo > results.json

EXIT CODES:
    0    Valid production lifecycle
    1    Invalid or missing file
    2    Schema validation failed
    3    Non-production lifecycle
    4    Missing lifecycle field

EOF
}

# Logging functions
log_info() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*" >&2
    fi
}

log_success() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
    fi
}

log_warning() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $*" >&2
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" && "${QUIET:-false}" != "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

# Check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing tools:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                yq)
                    log_error "  yq: https://github.com/mikefarah/yq#install"
                    ;;
                jq)
                    log_error "  jq: https://stedolan.github.io/jq/download/"
                    ;;
            esac
        done
        exit 1
    fi
}

# Validate YAML file structure and schema
validate_yaml_schema() {
    local yaml_file="$1"
    local validation_result="{}"
    
    log_verbose "Validating YAML schema for: $yaml_file"
    
    # Check if file exists and is readable
    if [[ ! -f "$yaml_file" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "file_not_found",
            "message": "File does not exist"
        }')
        echo "$validation_result"
        return 1
    fi
    
    if [[ ! -r "$yaml_file" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "file_not_readable",
            "message": "File is not readable"
        }')
        echo "$validation_result"
        return 1
    fi
    
    # Check if file is valid YAML
    if ! yq eval '.' "$yaml_file" >/dev/null 2>&1; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "invalid_yaml",
            "message": "File contains invalid YAML syntax"
        }')
        echo "$validation_result"
        return 2
    fi
    
    # Extract key fields
    local api_version
    local kind
    local lifecycle
    local metadata_name
    
    api_version=$(yq eval '.apiVersion // "missing"' "$yaml_file")
    kind=$(yq eval '.kind // "missing"' "$yaml_file")
    lifecycle=$(yq eval '.spec.lifecycle // "missing"' "$yaml_file")
    metadata_name=$(yq eval '.metadata.name // "missing"' "$yaml_file")
    
    log_verbose "Extracted fields:"
    log_verbose "  apiVersion: $api_version"
    log_verbose "  kind: $kind"
    log_verbose "  lifecycle: $lifecycle"
    log_verbose "  metadata.name: $metadata_name"
    
    # Validate apiVersion
    if [[ "$api_version" == "missing" || "$api_version" == "null" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "missing_api_version",
            "message": "Missing apiVersion field"
        }')
        echo "$validation_result"
        return 2
    fi
    
    if [[ ! "$api_version" =~ ^v3\.0 ]]; then
        validation_result=$(jq -n --arg actual "$api_version" --arg expected "$EXPECTED_API_VERSION" '{
            "valid": false,
            "error": "invalid_api_version",
            "message": "Invalid apiVersion. Expected: \($expected), Got: \($actual)"
        }')
        echo "$validation_result"
        return 2
    fi
    
    # Validate required fields
    if [[ "$kind" == "missing" || "$kind" == "null" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "missing_kind",
            "message": "Missing kind field"
        }')
        echo "$validation_result"
        return 2
    fi
    
    if [[ "$metadata_name" == "missing" || "$metadata_name" == "null" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "missing_metadata_name",
            "message": "Missing metadata.name field"
        }')
        echo "$validation_result"
        return 2
    fi
    
    # Check lifecycle field
    if [[ "$lifecycle" == "missing" || "$lifecycle" == "null" ]]; then
        validation_result=$(jq -n '{
            "valid": false,
            "error": "missing_lifecycle",
            "message": "Missing spec.lifecycle field"
        }')
        echo "$validation_result"
        return 4
    fi
    
    # Determine if lifecycle indicates production
    local is_production=false
    if [[ "$lifecycle" =~ ^[Pp]roduction$ ]]; then
        is_production=true
    fi
    
    # Create successful validation result
    validation_result=$(jq -n \
        --arg api_version "$api_version" \
        --arg kind "$kind" \
        --arg lifecycle "$lifecycle" \
        --arg metadata_name "$metadata_name" \
        --argjson is_production "$is_production" \
        '{
            "valid": true,
            "api_version": $api_version,
            "kind": $kind,
            "lifecycle": $lifecycle,
            "metadata_name": $metadata_name,
            "is_production": $is_production,
            "message": "Valid Datadog YAML schema"
        }')
    
    echo "$validation_result"
    
    if [[ "$is_production" == "true" ]]; then
        return 0
    else
        return 3
    fi
}

# Main validation function
validate_repository() {
    local repo_path="$1"
    local yaml_file_path="$2"
    local full_yaml_path="$repo_path/$yaml_file_path"
    
    log_info "Validating repository: $repo_path"
    log_verbose "Looking for Datadog YAML at: $full_yaml_path"
    
    # Validate the YAML file
    local validation_result
    local exit_code
    
    validation_result=$(validate_yaml_schema "$full_yaml_path")
    exit_code=$?
    
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        # Add repository information to the result
        echo "$validation_result" | jq --arg repo_path "$repo_path" --arg yaml_path "$yaml_file_path" '. + {
            "repository_path": $repo_path,
            "yaml_file_path": $yaml_path,
            "timestamp": now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }'
    else
        # Parse result for human-readable output
        local is_valid
        local lifecycle
        local is_production
        local message
        
        is_valid=$(echo "$validation_result" | jq -r '.valid')
        lifecycle=$(echo "$validation_result" | jq -r '.lifecycle // "unknown"')
        is_production=$(echo "$validation_result" | jq -r '.is_production // false')
        message=$(echo "$validation_result" | jq -r '.message')
        
        if [[ "$is_valid" == "true" ]]; then
            if [[ "$is_production" == "true" ]]; then
                log_success "Repository qualifies for Plus1 Enforcement (lifecycle: $lifecycle)"
            else
                log_warning "Repository has valid YAML but non-production lifecycle: $lifecycle"
            fi
        else
            log_error "$message"
        fi
    fi
    
    return $exit_code
}

# Parse command line arguments
YAML_FILE_PATH="$DEFAULT_YAML_PATH"
VERBOSE=false
JSON_OUTPUT=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            YAML_FILE_PATH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check for repository path argument
if [[ $# -eq 0 ]]; then
    log_error "Repository path is required"
    usage
    exit 1
fi

REPOSITORY_PATH="$1"

# Validate repository path
if [[ ! -d "$REPOSITORY_PATH" ]]; then
    log_error "Repository path does not exist or is not a directory: $REPOSITORY_PATH"
    exit 1
fi

# Check dependencies
check_dependencies

# Run validation
log_verbose "Starting validation with configuration:"
log_verbose "  Repository path: $REPOSITORY_PATH"
log_verbose "  YAML file path: $YAML_FILE_PATH"
log_verbose "  Expected API version: $EXPECTED_API_VERSION"
log_verbose "  Verbose mode: $VERBOSE"
log_verbose "  JSON output: $JSON_OUTPUT"
log_verbose "  Quiet mode: $QUIET"

validate_repository "$REPOSITORY_PATH" "$YAML_FILE_PATH"
exit_code=$?

if [[ "${JSON_OUTPUT:-false}" != "true" ]]; then
    case $exit_code in
        0)
            log_verbose "Validation completed successfully - production repository"
            ;;
        1)
            log_verbose "Validation failed - file issues"
            ;;
        2)
            log_verbose "Validation failed - schema validation failed"
            ;;
        3)
            log_verbose "Validation completed - non-production repository"
            ;;
        4)
            log_verbose "Validation failed - missing lifecycle field"
            ;;
    esac
fi

exit $exit_code 