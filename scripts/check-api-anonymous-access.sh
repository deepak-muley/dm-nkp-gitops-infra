#!/usr/bin/env bash
#
# Kubernetes API Anonymous Access Check Script
#
# Tests various Kubernetes API endpoints to determine if they are accessible
# without authentication (anonymous access). This is a security check to ensure
# that the API server is properly configured to require authentication.
#
# Usage:
#   ./check-api-anonymous-access.sh
#   ./check-api-anonymous-access.sh --kubeconfig /path/to/kubeconfig
#   KUBECONFIG=/path/to/kubeconfig ./check-api-anonymous-access.sh
#
# Author: Platform Team
# Date: December 2024
#

set -e

KUBECONFIG_FILE=""
API_SERVER_URL=""
NO_COLOR_FLAG=false
FORCE_COLOR_FLAG=false

# Function to setup colors based on TTY and flags
setup_colors() {
    # Check if colors should be used
    # Disable colors if --no-color is set, NO_COLOR env var is set, not a TTY, or TERM is dumb
    local use_colors=true

    # More aggressive check: disable colors if any of these conditions are true
    if [[ "$NO_COLOR_FLAG" == "true" ]] || \
       [[ "${NO_COLOR:-}" == "1" ]] || \
       [[ "${TERM:-}" == "dumb" ]] || \
       [[ ! -t 1 ]] || \
       [[ -t 1 && -p /dev/stdout ]]; then  # Also disable if stdout is a pipe
        use_colors=false
    fi

    # Set color variables - ensure they're truly empty when disabled
    if [[ "$use_colors" == "true" ]]; then
        # Use ANSI escape sequences with $'...' syntax for proper interpretation
        RED=$'\033[0;31m'
        GREEN=$'\033[0;32m'
        YELLOW=$'\033[1;33m'
        BLUE=$'\033[0;34m'
        CYAN=$'\033[0;36m'
        BOLD=$'\033[1m'
        NC=$'\033[0m'
    else
        # Explicitly unset and then set to empty to ensure no escape sequences remain
        unset RED GREEN YELLOW BLUE CYAN BOLD NC 2>/dev/null || true
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        CYAN=""
        BOLD=""
        NC=""
    fi
}

# Initialize colors
setup_colors

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --kubeconfig|-k)
            KUBECONFIG_FILE="$2"
            shift 2
            ;;
        --api-server|-a)
            API_SERVER_URL="$2"
            shift 2
            ;;
        --no-color)
            NO_COLOR_FLAG=true
            setup_colors
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --kubeconfig, -k PATH    Path to kubeconfig file"
            echo "  --api-server, -a URL      Direct API server URL (e.g., https://10.23.130.61:6443)"
            echo "  --no-color               Disable colored output"
            echo "  --help, -h                Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  KUBECONFIG               Path to kubeconfig file (used if --kubeconfig not provided)"
            echo "  NO_COLOR                  Set to 1 to disable colors"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --kubeconfig /path/to/kubeconfig"
            echo "  $0 --api-server https://10.23.130.61:6443"
            echo "  $0 --no-color"
            echo "  KUBECONFIG=/path/to/kubeconfig $0"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print header
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Function to print sub-header
print_subheader() {
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────${NC}"
}

# Function to get API server URL from kubeconfig
get_api_server_from_kubeconfig() {
    local kubeconfig=$1

    if [[ ! -f "$kubeconfig" ]]; then
        echo -e "${RED}Error: Kubeconfig file not found: $kubeconfig${NC}" >&2
        return 1
    fi

    # Try to get server URL from kubeconfig
    local server_url
    server_url=$(kubectl --kubeconfig="$kubeconfig" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")

    if [[ -z "$server_url" ]]; then
        echo -e "${RED}Error: Could not extract API server URL from kubeconfig${NC}" >&2
        return 1
    fi

    echo "$server_url"
}

# Function to determine API server URL
determine_api_server() {
    if [[ -n "$API_SERVER_URL" ]]; then
        echo "$API_SERVER_URL"
        return 0
    fi

    # Determine kubeconfig to use
    local kubeconfig_to_use=""
    if [[ -n "$KUBECONFIG_FILE" ]]; then
        kubeconfig_to_use="$KUBECONFIG_FILE"
    elif [[ -n "$KUBECONFIG" ]]; then
        kubeconfig_to_use="$KUBECONFIG"
    else
        # Try default kubeconfig location
        if [[ -f "$HOME/.kube/config" ]]; then
            kubeconfig_to_use="$HOME/.kube/config"
        else
            echo -e "${RED}Error: No kubeconfig specified and KUBECONFIG env var not set${NC}" >&2
            echo -e "${YELLOW}Please provide --kubeconfig or set KUBECONFIG environment variable${NC}" >&2
            return 1
        fi
    fi

    get_api_server_from_kubeconfig "$kubeconfig_to_use"
}

# Function to test an API endpoint
test_endpoint() {
    local base_url=$1
    local endpoint=$2
    local description=$3

    local full_url="${base_url}${endpoint}"

    # Use curl with -k to skip certificate verification (for testing)
    # Use -s for silent mode, -o /dev/null to discard body, -w to get status code
    # Use --max-time 5 for timeout
    local http_code
    local response_body
    local curl_output

    # Capture both status code and response body
    curl_output=$(curl -k -s -w "\n%{http_code}" --max-time 5 "$full_url" 2>&1 || echo -e "\n000")
    http_code=$(echo "$curl_output" | tail -n 1)
    # Use sed to remove last line (http_code) for macOS compatibility
    response_body=$(echo "$curl_output" | sed '$d')

    # Determine if access was successful
    # 200-299 = success, 401/403 = auth required (good), 000 = connection failed
    local status=""
    local status_color=""
    local status_icon=""

    if [[ "$http_code" == "000" ]]; then
        status="CONNECTION_FAILED"
        status_color="${RED}"
        status_icon="❌"
    elif [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        status="ACCESSIBLE"
        status_color="${RED}"
        status_icon="⚠️ "
    elif [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
        status="AUTH_REQUIRED"
        status_color="${GREEN}"
        status_icon="✅"
    else
        status="HTTP_${http_code}"
        status_color="${YELLOW}"
        status_icon="⚠️ "
    fi

    # Print result
    printf "  %-50s %s %s%-15s${NC} (HTTP %s)\n" \
        "$description" \
        "$status_icon" \
        "$status_color" \
        "$status" \
        "$http_code"

    # If accessible, show a snippet of the response
    if [[ "$status" == "ACCESSIBLE" ]]; then
        local snippet
        snippet=$(echo "$response_body" | head -c 200 | tr -d '\n' | sed 's/  */ /g')
        if [[ -n "$snippet" ]]; then
            echo -e "    ${YELLOW}Response snippet: ${snippet}...${NC}"
        fi
    fi

    # Return status code for summary
    if [[ "$status" == "ACCESSIBLE" ]]; then
        return 1  # Found a vulnerability
    else
        return 0  # Secure
    fi
}

# Function to get kubeconfig file path
get_kubeconfig_path() {
    if [[ -n "$KUBECONFIG_FILE" ]]; then
        echo "$KUBECONFIG_FILE"
        return 0
    elif [[ -n "$KUBECONFIG" ]]; then
        echo "$KUBECONFIG"
        return 0
    elif [[ -f "$HOME/.kube/config" ]]; then
        echo "$HOME/.kube/config"
        return 0
    fi
    return 1
}

# Function to check for anonymous RBAC bindings
check_anonymous_rbac_bindings() {
    local kubeconfig=$1
    local api_server=$2

    # Check if we can access the cluster with kubeconfig
    if [[ ! -f "$kubeconfig" ]]; then
        return 1
    fi

    # Check if kubectl and jq are available
    if ! command -v kubectl &>/dev/null || ! command -v jq &>/dev/null; then
        return 1
    fi

    # Check for ClusterRoleBindings with anonymous access
    local anonymous_crbs
    anonymous_crbs=$(kubectl --kubeconfig="$kubeconfig" get clusterrolebindings -o json 2>/dev/null | \
        jq -r '.items[] | select(.subjects? // [] | any((.kind == "User" and .name == "system:anonymous") or (.kind == "Group" and .name == "system:unauthenticated"))) | .metadata.name' 2>/dev/null || echo "")

    # Check for RoleBindings with anonymous access
    local anonymous_rbs
    anonymous_rbs=$(kubectl --kubeconfig="$kubeconfig" get rolebindings -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.subjects? // [] | any((.kind == "User" and .name == "system:anonymous") or (.kind == "Group" and .name == "system:unauthenticated"))) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

    # Return results as newline-separated values
    if [[ -n "$anonymous_crbs" ]] || [[ -n "$anonymous_rbs" ]]; then
        echo "CRB:${anonymous_crbs}"
        echo "RB:${anonymous_rbs}"
        return 0
    fi

    return 1
}

# Function to get rules from a ClusterRole or Role
get_role_rules() {
    local kubeconfig=$1
    local role_type=$2  # "clusterrole" or "role"
    local role_name=$3
    local namespace=${4:-""}  # Optional namespace for Role

    if [[ "$role_type" == "clusterrole" ]]; then
        kubectl --kubeconfig="$kubeconfig" get clusterrole "$role_name" -o json 2>/dev/null | \
            jq -r '.rules[]? | "\(.apiGroups[]? // "core")|\(.resources[]?)|\(.verbs[]?)"' 2>/dev/null || echo ""
    else
        if [[ -n "$namespace" ]]; then
            kubectl --kubeconfig="$kubeconfig" get role "$role_name" -n "$namespace" -o json 2>/dev/null | \
                jq -r '.rules[]? | "\(.apiGroups[]? // "core")|\(.resources[]?)|\(.verbs[]?)"' 2>/dev/null || echo ""
        fi
    fi
}

# Function to test endpoints based on RBAC rules
# This function modifies vulnerable_count and total_count variables from parent scope
test_rbac_endpoints() {
    local api_server=$1
    local kubeconfig=$2

    # Helper function to test and update counts
    test_and_count() {
        local endpoint=$1
        local description=$2
        test_endpoint "$api_server" "$endpoint" "$description" && : || ((vulnerable_count++))
        ((total_count++))
    }

    # Check for anonymous bindings
    local rbac_check_output
    rbac_check_output=$(check_anonymous_rbac_bindings "$kubeconfig" "$api_server" 2>/dev/null || echo "")

    if [[ -z "$rbac_check_output" ]]; then
        return 0  # No anonymous bindings found
    fi

    print_subheader "Anonymous RBAC Bindings Detected"
    echo -e "  ${RED}${BOLD}⚠️  SECURITY ISSUE: Anonymous RBAC bindings found!${NC}"
    echo ""

    # Parse ClusterRoleBindings
    local anonymous_crbs
    anonymous_crbs=$(echo "$rbac_check_output" | grep "^CRB:" | sed 's/^CRB://' | grep -v "^$")

    if [[ -n "$anonymous_crbs" ]]; then
        echo -e "  ${RED}ClusterRoleBindings with anonymous access:${NC}"
        while IFS= read -r crb_name; do
            if [[ -n "$crb_name" ]]; then
                echo -e "    ${YELLOW}→${NC} $crb_name"

                # Get the ClusterRole name
                local clusterrole_name
                clusterrole_name=$(kubectl --kubeconfig="$kubeconfig" get clusterrolebinding "$crb_name" -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "")

                if [[ -n "$clusterrole_name" ]]; then
                    echo -e "      ${CYAN}ClusterRole: $clusterrole_name${NC}"

                    # Get rules and test endpoints
                    local rules
                    rules=$(get_role_rules "$kubeconfig" "clusterrole" "$clusterrole_name" 2>/dev/null || echo "")

                    if [[ -n "$rules" ]]; then
                        echo -e "      ${CYAN}Testing endpoints allowed by this ClusterRole...${NC}"
                        while IFS='|' read -r api_group resource verb; do
                            if [[ -n "$api_group" && -n "$resource" && -n "$verb" ]]; then
                                # Convert to API endpoint
                                local endpoint=""
                                if [[ "$api_group" == "core" ]] || [[ -z "$api_group" ]]; then
                                    endpoint="/api/v1/${resource}"
                                else
                                    # Try common API versions
                                    endpoint="/apis/${api_group}/v1/${resource}"
                                fi

                                # Test the endpoint (only for list/get verbs)
                                if [[ "$verb" == "list" ]] || [[ "$verb" == "get" ]] || [[ "$verb" == "*" ]]; then
                                    local description="Anonymous: ${resource} (${verb})"
                                    test_and_count "$endpoint" "$description"
                                fi
                            fi
                        done <<< "$rules"
                    fi
                fi
            fi
        done <<< "$anonymous_crbs"
        echo ""
    fi

    # Parse RoleBindings
    local anonymous_rbs
    anonymous_rbs=$(echo "$rbac_check_output" | grep "^RB:" | sed 's/^RB://' | grep -v "^$")

    if [[ -n "$anonymous_rbs" ]]; then
        echo -e "  ${RED}RoleBindings with anonymous access:${NC}"
        while IFS= read -r rb_path; do
            if [[ -n "$rb_path" ]]; then
                local namespace="${rb_path%%/*}"
                local rb_name="${rb_path##*/}"
                echo -e "    ${YELLOW}→${NC} $rb_path"

                # Get the Role name
                local role_name
                role_name=$(kubectl --kubeconfig="$kubeconfig" get rolebinding "$rb_name" -n "$namespace" -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "")

                if [[ -n "$role_name" ]]; then
                    echo -e "      ${CYAN}Role: $role_name (namespace: $namespace)${NC}"

                    # Get rules and test endpoints
                    local rules
                    rules=$(get_role_rules "$kubeconfig" "role" "$role_name" "$namespace" 2>/dev/null || echo "")

                    if [[ -n "$rules" ]]; then
                        echo -e "      ${CYAN}Testing endpoints allowed by this Role...${NC}"
                        while IFS='|' read -r api_group resource verb; do
                            if [[ -n "$api_group" && -n "$resource" && -n "$verb" ]]; then
                                # Convert to API endpoint
                                local endpoint=""
                                if [[ "$api_group" == "core" ]] || [[ -z "$api_group" ]]; then
                                    endpoint="/api/v1/namespaces/${namespace}/${resource}"
                                else
                                    endpoint="/apis/${api_group}/v1/namespaces/${namespace}/${resource}"
                                fi

                                # Test the endpoint (only for list/get verbs)
                                if [[ "$verb" == "list" ]] || [[ "$verb" == "get" ]] || [[ "$verb" == "*" ]]; then
                                    local description="Anonymous: ${namespace}/${resource} (${verb})"
                                    test_and_count "$endpoint" "$description"
                                fi
                            fi
                        done <<< "$rules"
                    fi
                fi
            fi
        done <<< "$anonymous_rbs"
        echo ""
    fi

    # Always report this as a security issue (even if endpoints return 403, the bindings exist)
    return 1
}

# Function to discover CRDs and their API groups/versions
discover_crds() {
    local kubeconfig=$1
    local api_server=$2

    # Check if we can access the cluster with kubeconfig
    if [[ ! -f "$kubeconfig" ]]; then
        return 1
    fi

    # Try to get CRDs - if this fails, we can't discover them
    if ! kubectl --kubeconfig="$kubeconfig" get crd &>/dev/null; then
        return 1
    fi

    # Get all CRDs and extract their API group, version, and plural name
    kubectl --kubeconfig="$kubeconfig" get crd -o json 2>/dev/null | \
        jq -r '.items[] |
            select(.spec.group != null and .spec.versions != null) |
            .spec as $spec |
            .spec.versions[]? |
            select(.served == true) |
            "\($spec.group)/\(.name)/\($spec.names.plural)"' 2>/dev/null | \
        sort -u
}

# Function to test common CRD patterns
# This function modifies vulnerable_count and total_count variables from parent scope
test_common_crd_patterns() {
    local api_server=$1

    # Helper function to test and update counts
    test_and_count() {
        local endpoint=$1
        local description=$2
        test_endpoint "$api_server" "$endpoint" "$description" && : || ((vulnerable_count++))
        ((total_count++))
    }

    # Test common CRD patterns (Flux, Kommander, CAPI, etc.)
    print_subheader "Common Custom Resource APIs (Pattern-based)"

    # Flux CD resources
    test_and_count "/apis/kustomize.toolkit.fluxcd.io/v1" "Flux Kustomizations API"
    test_and_count "/apis/kustomize.toolkit.fluxcd.io/v1/kustomizations" "List Kustomizations"
    test_and_count "/apis/source.toolkit.fluxcd.io/v1" "Flux Sources API"
    test_and_count "/apis/source.toolkit.fluxcd.io/v1/gitrepositories" "List GitRepositories"
    test_and_count "/apis/helm.toolkit.fluxcd.io/v2beta1" "Flux HelmReleases API"
    test_and_count "/apis/helm.toolkit.fluxcd.io/v2beta1/helmreleases" "List HelmReleases"

    # Kommander resources
    test_and_count "/apis/apps.kommander.d2iq.io/v1alpha1" "Kommander Apps API"
    test_and_count "/apis/apps.kommander.d2iq.io/v1alpha1/appdeployments" "List AppDeployments"
    test_and_count "/apis/apps.kommander.d2iq.io/v1alpha1/appdeploymentinstances" "List AppDeploymentInstances"

    # CAPI resources
    test_and_count "/apis/cluster.x-k8s.io/v1beta1" "CAPI Clusters API"
    test_and_count "/apis/cluster.x-k8s.io/v1beta1/clusters" "List Clusters"
    test_and_count "/apis/addons.cluster.x-k8s.io/v1beta1" "CAPI Addons API"
    test_and_count "/apis/addons.cluster.x-k8s.io/v1beta1/helmchartproxies" "List HelmChartProxies"

    # Sealed Secrets
    test_and_count "/apis/bitnami.com/v1alpha1" "Sealed Secrets API"
    test_and_count "/apis/bitnami.com/v1alpha1/sealedsecrets" "List SealedSecrets"

    # Gatekeeper
    test_and_count "/apis/templates.gatekeeper.sh/v1beta1" "Gatekeeper Templates API"
    test_and_count "/apis/status.gatekeeper.sh/v1beta1" "Gatekeeper Status API"

    # Kyverno
    test_and_count "/apis/kyverno.io/v1" "Kyverno Policies API"
    test_and_count "/apis/kyverno.io/v1/policies" "List Kyverno Policies"
}

# Function to test CRD endpoints
# This function modifies vulnerable_count and total_count variables from parent scope
test_crd_endpoints() {
    local api_server=$1
    local kubeconfig_path=$2

    # Helper function to test and update counts
    test_and_count() {
        local endpoint=$1
        local description=$2
        test_endpoint "$api_server" "$endpoint" "$description" && : || ((vulnerable_count++))
        ((total_count++))
    }

    # Check if we can discover CRDs
    if [[ -z "$kubeconfig_path" ]] || [[ ! -f "$kubeconfig_path" ]]; then
        echo -e "  ${YELLOW}Note: No kubeconfig available - testing common CRD patterns${NC}"
        test_common_crd_patterns "$api_server"
        return 0
    fi

    # Discover CRDs from the cluster
    local crd_count=0
    local discovered_crds
    discovered_crds=$(discover_crds "$kubeconfig_path" "$api_server" 2>/dev/null || echo "")

    if [[ -z "$discovered_crds" ]]; then
        echo -e "  ${YELLOW}Note: Could not discover CRDs from cluster${NC}"
        echo -e "  ${YELLOW}Testing common CRD patterns instead${NC}"
        test_common_crd_patterns "$api_server"
        return 0
    fi

    print_subheader "Custom Resource APIs (Discovered from Cluster)"
    echo -e "  ${CYAN}Discovered CRDs from cluster...${NC}"

    # Test each discovered CRD endpoint
    while IFS= read -r crd_path; do
        if [[ -n "$crd_path" ]]; then
            local group_version="${crd_path%/*}"
            local resource="${crd_path##*/}"
            local crd_name="${resource}"

            # Test the API group/version endpoint
            test_and_count "/apis/${group_version}" "${group_version} API"

            # Test the resource list endpoint
            test_and_count "/apis/${group_version}/${resource}" "List ${crd_name}"
            ((crd_count++))
        fi
    done <<< "$discovered_crds"

    if [[ $crd_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No CRDs discovered - testing common patterns instead${NC}"
        test_common_crd_patterns "$api_server"
    else
        echo -e "  ${GREEN}Tested endpoints for $crd_count discovered CRD types${NC}"
    fi
}

# Main function
main() {
    clear 2>/dev/null || true

    echo -e "${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     KUBERNETES API ANONYMOUS ACCESS SECURITY CHECK              ║"
    echo "║     $(date '+%Y-%m-%d %H:%M:%S')                                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Determine API server URL
    print_header "Configuration"
    local api_server
    if ! api_server=$(determine_api_server); then
        exit 1
    fi

    echo -e "  API Server URL: ${BOLD}$api_server${NC}"
    if [[ -n "$KUBECONFIG_FILE" ]]; then
        echo -e "  Kubeconfig: ${BOLD}$KUBECONFIG_FILE${NC}"
    elif [[ -n "$KUBECONFIG" ]]; then
        echo -e "  Kubeconfig: ${BOLD}$KUBECONFIG${NC} (from env)"
    fi

    # Test endpoints
    print_header "Testing API Endpoints (Anonymous Access)"
    echo ""
    echo -e "  ${YELLOW}Note: Testing without authentication headers${NC}"
    echo -e "  ${YELLOW}Expected: HTTP 401/403 (authentication required)${NC}"
    echo -e "  ${RED}Warning: HTTP 200-299 indicates anonymous access is allowed${NC}"
    echo ""

    local vulnerable_count=0
    local total_count=0

    # Core API endpoints
    print_subheader "Core API Endpoints"
    test_endpoint "$api_server" "/api/v1" "Core API v1" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/pods" "List Pods" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/namespaces" "List Namespaces" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/secrets" "List Secrets" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/configmaps" "List ConfigMaps" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/services" "List Services" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/api/v1/nodes" "List Nodes" && : || ((vulnerable_count++))
    ((total_count++))

    # Health and version endpoints
    print_subheader "Health and Version Endpoints"
    test_endpoint "$api_server" "/version" "Version Info" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/healthz" "Health Check" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/livez" "Liveness Probe" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/readyz" "Readiness Probe" && : || ((vulnerable_count++))
    ((total_count++))

    # API Groups
    print_subheader "API Groups"
    test_endpoint "$api_server" "/apis" "API Groups List" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/apps/v1" "Apps API v1" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/apps/v1/deployments" "List Deployments" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/rbac.authorization.k8s.io/v1" "RBAC API v1" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/rbac.authorization.k8s.io/v1/roles" "List Roles" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/rbac.authorization.k8s.io/v1/rolebindings" "List RoleBindings" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/rbac.authorization.k8s.io/v1/clusterroles" "List ClusterRoles" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" "List ClusterRoleBindings" && : || ((vulnerable_count++))
    ((total_count++))

    # Custom Resources - test CRD discovery and common patterns
    print_subheader "CustomResourceDefinitions API"
    test_endpoint "$api_server" "/apis/apiextensions.k8s.io/v1" "CRD Extensions API" && : || ((vulnerable_count++))
    ((total_count++))
    test_endpoint "$api_server" "/apis/apiextensions.k8s.io/v1/customresourcedefinitions" "List CRDs" && : || ((vulnerable_count++))
    ((total_count++))

    # Test all discovered CRDs and common patterns
    local kubeconfig_path
    kubeconfig_path=$(get_kubeconfig_path 2>/dev/null || echo "")
    test_crd_endpoints "$api_server" "$kubeconfig_path"

    # Check for anonymous RBAC bindings and test endpoints they allow
    if [[ -n "$kubeconfig_path" ]] && [[ -f "$kubeconfig_path" ]]; then
        # Function returns 1 if bindings found (security issue), 0 if not found
        # Note: vulnerable_count is already incremented inside the function for each endpoint tested
        test_rbac_endpoints "$api_server" "$kubeconfig_path" || true
    fi

    # Summary
    print_header "Summary"
    echo ""
    echo -e "  Total Endpoints Tested: ${BOLD}$total_count${NC}"
    echo -e "  Vulnerable Endpoints:   ${RED}${BOLD}$vulnerable_count${NC}"
    echo -e "  Secure Endpoints:       ${GREEN}${BOLD}$((total_count - vulnerable_count))${NC}"
    echo ""

    if [[ $vulnerable_count -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}⚠️  SECURITY ISSUE DETECTED${NC}"
        echo -e "  ${RED}Some API endpoints are accessible without authentication!${NC}"
        echo ""
        echo -e "  ${YELLOW}Note:${NC}"
        echo -e "  Health endpoints (/version, /healthz, /livez, /readyz) are typically"
        echo -e "  allowed to be accessible for monitoring purposes. However, sensitive"
        echo -e "  endpoints like /api/v1/pods, /api/v1/secrets should require authentication."
        echo ""
        echo -e "  ${YELLOW}Recommendation:${NC}"
        echo -e "  1. Review Kubernetes API server configuration"
        echo -e "  2. Ensure --anonymous-auth=false is set on API server (if desired)"
        echo -e "  3. Verify RBAC policies are properly configured"
        echo -e "  4. Remove any ClusterRoleBindings or RoleBindings that grant access to:"
        echo -e "     - system:anonymous user"
        echo -e "     - system:unauthenticated group"
        echo -e "  5. Check for any NetworkPolicies or admission controllers"
        echo -e "  6. Consider restricting health endpoints if not needed externally"
        echo ""
        return 1
    else
        echo -e "  ${GREEN}${BOLD}✅ SECURITY CHECK PASSED${NC}"
        echo -e "  ${GREEN}All tested endpoints require authentication${NC}"
        echo ""
        return 0
    fi
}

# Run main function
main

