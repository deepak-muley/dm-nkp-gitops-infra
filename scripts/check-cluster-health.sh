#!/usr/bin/env bash
#
# NKP Cluster Health Check Script
#
# Checks the health of management and workload clusters by summarizing:
#   - Failed/Pending/CrashLoopBackOff pods
#   - Flux Kustomizations not ready
#   - HelmReleases not ready
#   - Node status
#
# Usage:
#   ./check-cluster-health.sh                # Check all clusters
#   ./check-cluster-health.sh mgmt           # Check management cluster only
#   ./check-cluster-health.sh workload1      # Check workload cluster 1 only
#   ./check-cluster-health.sh workload2      # Check workload cluster 2 only
#   ./check-cluster-health.sh --summary      # Show only summary (no details)
#   ./check-cluster-health.sh --watch        # Continuously monitor (every 30s)
#
# Author: Platform Team
# Date: December 2024
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default kubeconfig locations for NKP clusters
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
DEFAULT_WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Function to get kubeconfig for a cluster
get_kubeconfig() {
    local cluster=$1
    case $cluster in
        mgmt) echo "$DEFAULT_MGMT_KUBECONFIG" ;;
        workload1) echo "$DEFAULT_WORKLOAD1_KUBECONFIG" ;;
        workload2) echo "$DEFAULT_WORKLOAD2_KUBECONFIG" ;;
        *) echo "" ;;
    esac
}

SUMMARY_ONLY=false
WATCH_MODE=false
WATCH_INTERVAL=30
SELECTED_CLUSTERS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --summary|-s)
            SUMMARY_ONLY=true
            shift
            ;;
        --watch|-w)
            WATCH_MODE=true
            shift
            ;;
        --interval|-i)
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [CLUSTER...]"
            echo ""
            echo "Options:"
            echo "  --summary, -s       Show only summary (no details)"
            echo "  --watch, -w         Continuously monitor clusters (every 30s)"
            echo "  --interval, -i N    Set watch interval to N seconds (default: 30)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Clusters:"
            echo "  mgmt                Management cluster"
            echo "  workload1           Workload cluster 1"
            echo "  workload2           Workload cluster 2"
            echo ""
            echo "Examples:"
            echo "  $0                         # Check all clusters"
            echo "  $0 mgmt                    # Check management cluster only"
            echo "  $0 mgmt workload1          # Check mgmt and workload1"
            echo "  $0 --summary               # Summary of all clusters"
            echo "  $0 --watch mgmt            # Continuously monitor mgmt cluster"
            exit 0
            ;;
        mgmt|workload1|workload2)
            SELECTED_CLUSTERS+=("$1")
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option or cluster: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no clusters selected, check all
if [[ ${#SELECTED_CLUSTERS[@]} -eq 0 ]]; then
    SELECTED_CLUSTERS=("mgmt" "workload1" "workload2")
fi

# Function to print section header
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

# Function to print cluster header
print_cluster_header() {
    local cluster_name=$1
    local status=$2
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    if [[ "$status" == "healthy" ]]; then
        echo -e "${MAGENTA}║${NC}  ${GREEN}✅ CLUSTER: ${BOLD}$cluster_name${NC}                                        ${MAGENTA}║${NC}"
    elif [[ "$status" == "degraded" ]]; then
        echo -e "${MAGENTA}║${NC}  ${YELLOW}⚠️  CLUSTER: ${BOLD}$cluster_name${NC}                                        ${MAGENTA}║${NC}"
    else
        echo -e "${MAGENTA}║${NC}  ${RED}❌ CLUSTER: ${BOLD}$cluster_name${NC}                                        ${MAGENTA}║${NC}"
    fi
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

# Function to check if cluster is reachable
check_cluster_connectivity() {
    local kubeconfig=$1
    if [[ ! -f "$kubeconfig" ]]; then
        return 1
    fi
    if ! KUBECONFIG="$kubeconfig" kubectl cluster-info &>/dev/null; then
        return 1
    fi
    return 0
}

# Function to get node status
check_nodes() {
    local kubeconfig=$1

    print_subheader "Node Status"

    local total_nodes
    local ready_nodes
    local not_ready_nodes

    total_nodes=$(KUBECONFIG="$kubeconfig" kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_nodes=$(KUBECONFIG="$kubeconfig" kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " | tr -d '[:space:]')
    [[ -z "$total_nodes" ]] && total_nodes=0
    [[ -z "$ready_nodes" ]] && ready_nodes=0
    not_ready_nodes=$((total_nodes - ready_nodes))

    echo -e "  Total Nodes:     ${BOLD}$total_nodes${NC}"
    echo -e "  Ready:           ${GREEN}$ready_nodes${NC}"

    if [[ "$not_ready_nodes" -gt 0 ]]; then
        echo -e "  Not Ready:       ${RED}$not_ready_nodes${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready Nodes:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | while read -r line; do
                echo -e "    ${RED}→${NC} $line"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check pod health
check_pods() {
    local kubeconfig=$1

    print_subheader "Pod Health"

    local total_pods
    local running_pods
    local failed_pods
    local pending_pods
    local crashloop_pods
    local imagepull_pods

    total_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    running_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running\|Completed\|Succeeded" | tr -d '[:space:]')
    failed_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | grep -c "Failed\|Error" | tr -d '[:space:]')
    pending_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | grep -c "Pending" | tr -d '[:space:]')
    crashloop_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" | tr -d '[:space:]')
    imagepull_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | grep -c "ImagePullBackOff\|ErrImagePull" | tr -d '[:space:]')

    # Default to 0 if empty
    [[ -z "$total_pods" ]] && total_pods=0
    [[ -z "$running_pods" ]] && running_pods=0
    [[ -z "$failed_pods" ]] && failed_pods=0
    [[ -z "$pending_pods" ]] && pending_pods=0
    [[ -z "$crashloop_pods" ]] && crashloop_pods=0
    [[ -z "$imagepull_pods" ]] && imagepull_pods=0

    echo -e "  Total Pods:          ${BOLD}$total_pods${NC}"
    echo -e "  Running/Completed:   ${GREEN}$running_pods${NC}"

    local has_issues=false

    if [[ "$failed_pods" -gt 0 ]]; then
        echo -e "  Failed/Error:        ${RED}$failed_pods${NC}"
        has_issues=true
    fi

    if [[ "$pending_pods" -gt 0 ]]; then
        echo -e "  Pending:             ${YELLOW}$pending_pods${NC}"
        has_issues=true
    fi

    if [[ "$crashloop_pods" -gt 0 ]]; then
        echo -e "  CrashLoopBackOff:    ${RED}$crashloop_pods${NC}"
        has_issues=true
    fi

    if [[ "$imagepull_pods" -gt 0 ]]; then
        echo -e "  ImagePullBackOff:    ${RED}$imagepull_pods${NC}"
        has_issues=true
    fi

    if [[ "$has_issues" == true && "$SUMMARY_ONLY" != true ]]; then
        echo ""
        echo -e "  ${YELLOW}Problem Pods:${NC}"
        KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | \
            grep -E "Failed|Error|Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull" | \
            head -20 | while read -r ns name ready status restarts age; do
            echo -e "    ${RED}→${NC} $ns/$name - ${YELLOW}$status${NC} (restarts: $restarts)"
        done

        local problem_count
        problem_count=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | \
            grep -cE "Failed|Error|Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull" | tr -d '[:space:]')
        [[ -z "$problem_count" ]] && problem_count=0

        if [[ "$problem_count" -gt 20 ]]; then
            echo -e "    ${BLUE}... and $((problem_count - 20)) more problem pods${NC}"
        fi
    fi

    if [[ "$has_issues" == true ]]; then
        return 1
    fi
    return 0
}

# Function to check Flux Kustomizations
check_kustomizations() {
    local kubeconfig=$1

    print_subheader "Flux Kustomizations"

    # Check if Flux is installed
    if ! KUBECONFIG="$kubeconfig" kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io &>/dev/null; then
        echo -e "  ${YELLOW}Flux not installed - skipping${NC}"
        return 0
    fi

    local total_ks
    local ready_ks
    local not_ready_ks

    total_ks=$(KUBECONFIG="$kubeconfig" kubectl get kustomizations -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_ks=$(KUBECONFIG="$kubeconfig" kubectl get kustomizations -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    [[ -z "$total_ks" ]] && total_ks=0
    [[ -z "$ready_ks" ]] && ready_ks=0
    not_ready_ks=$((total_ks - ready_ks))

    echo -e "  Total Kustomizations:  ${BOLD}$total_ks${NC}"
    echo -e "  Ready:                 ${GREEN}$ready_ks${NC}"

    if [[ "$not_ready_ks" -gt 0 ]]; then
        echo -e "  Not Ready:             ${RED}$not_ready_ks${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready Kustomizations:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get kustomizations -A --no-headers 2>/dev/null | \
                grep -v "True" | while read -r ns name ready status age; do
                # Get the reason for failure
                local reason
                reason=$(KUBECONFIG="$kubeconfig" kubectl get kustomization "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | head -c 100)
                echo -e "    ${RED}→${NC} $ns/$name"
                if [[ -n "$reason" ]]; then
                    echo -e "      ${YELLOW}Reason:${NC} ${reason}..."
                fi
            done
        fi
        return 1
    fi
    return 0
}

# Function to check HelmReleases
check_helmreleases() {
    local kubeconfig=$1

    print_subheader "Flux HelmReleases"

    # Check if Flux Helm controller is installed
    if ! KUBECONFIG="$kubeconfig" kubectl get crd helmreleases.helm.toolkit.fluxcd.io &>/dev/null; then
        echo -e "  ${YELLOW}Flux Helm Controller not installed - skipping${NC}"
        return 0
    fi

    local total_hr
    local ready_hr
    local not_ready_hr

    total_hr=$(KUBECONFIG="$kubeconfig" kubectl get helmreleases -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_hr=$(KUBECONFIG="$kubeconfig" kubectl get helmreleases -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    [[ -z "$total_hr" ]] && total_hr=0
    [[ -z "$ready_hr" ]] && ready_hr=0
    not_ready_hr=$((total_hr - ready_hr))

    echo -e "  Total HelmReleases:    ${BOLD}$total_hr${NC}"
    echo -e "  Ready:                 ${GREEN}$ready_hr${NC}"

    if [[ "$not_ready_hr" -gt 0 ]]; then
        echo -e "  Not Ready:             ${RED}$not_ready_hr${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready HelmReleases:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get helmreleases -A --no-headers 2>/dev/null | \
                grep -v "True" | while read -r ns name ready status age; do
                # Get the reason for failure
                local reason
                reason=$(KUBECONFIG="$kubeconfig" kubectl get helmrelease "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | head -c 100)
                echo -e "    ${RED}→${NC} $ns/$name"
                if [[ -n "$reason" ]]; then
                    echo -e "      ${YELLOW}Reason:${NC} ${reason}..."
                fi
            done
        fi
        return 1
    fi
    return 0
}

# Function to check GitRepositories
check_gitrepositories() {
    local kubeconfig=$1

    print_subheader "Flux GitRepositories"

    # Check if Flux Source controller is installed
    if ! KUBECONFIG="$kubeconfig" kubectl get crd gitrepositories.source.toolkit.fluxcd.io &>/dev/null; then
        echo -e "  ${YELLOW}Flux Source Controller not installed - skipping${NC}"
        return 0
    fi

    local total_gr
    local ready_gr
    local not_ready_gr

    total_gr=$(KUBECONFIG="$kubeconfig" kubectl get gitrepositories -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_gr=$(KUBECONFIG="$kubeconfig" kubectl get gitrepositories -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    [[ -z "$total_gr" ]] && total_gr=0
    [[ -z "$ready_gr" ]] && ready_gr=0
    not_ready_gr=$((total_gr - ready_gr))

    echo -e "  Total GitRepositories: ${BOLD}$total_gr${NC}"
    echo -e "  Ready:                 ${GREEN}$ready_gr${NC}"

    if [[ "$not_ready_gr" -gt 0 ]]; then
        echo -e "  Not Ready:             ${RED}$not_ready_gr${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready GitRepositories:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get gitrepositories -A --no-headers 2>/dev/null | \
                grep -v "True" | while read -r ns name url ready status age; do
                echo -e "    ${RED}→${NC} $ns/$name"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check HelmChartProxies (management cluster only)
check_helmchartproxies() {
    local kubeconfig=$1

    print_subheader "CAPI HelmChartProxies"

    # Check if HelmChartProxy CRD exists
    if ! KUBECONFIG="$kubeconfig" kubectl get crd helmchartproxies.addons.cluster.x-k8s.io &>/dev/null; then
        echo -e "  ${YELLOW}HelmChartProxy CRD not installed - skipping${NC}"
        return 0
    fi

    local total_hcp
    local ready_hcp
    local not_ready_hcp

    total_hcp=$(KUBECONFIG="$kubeconfig" kubectl get helmchartproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_hcp=$(KUBECONFIG="$kubeconfig" kubectl get helmchartproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    [[ -z "$total_hcp" ]] && total_hcp=0
    [[ -z "$ready_hcp" ]] && ready_hcp=0
    not_ready_hcp=$((total_hcp - ready_hcp))

    echo -e "  Total HelmChartProxies:  ${BOLD}$total_hcp${NC}"
    echo -e "  Ready:                   ${GREEN}$ready_hcp${NC}"

    if [[ "$not_ready_hcp" -gt 0 ]]; then
        echo -e "  Not Ready:               ${RED}$not_ready_hcp${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready HelmChartProxies:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get helmchartproxies -A --no-headers 2>/dev/null | \
                grep -v "True" | head -10 | while read -r ns name ready age; do
                echo -e "    ${RED}→${NC} $ns/$name"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check HelmReleaseProxies (management cluster only)
check_helmreleaseproxies() {
    local kubeconfig=$1

    print_subheader "CAPI HelmReleaseProxies"

    # Check if HelmReleaseProxy CRD exists
    if ! KUBECONFIG="$kubeconfig" kubectl get crd helmreleaseproxies.addons.cluster.x-k8s.io &>/dev/null; then
        echo -e "  ${YELLOW}HelmReleaseProxy CRD not installed - skipping${NC}"
        return 0
    fi

    local total_hrp
    local ready_hrp
    local not_ready_hrp

    total_hrp=$(KUBECONFIG="$kubeconfig" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    ready_hrp=$(KUBECONFIG="$kubeconfig" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    [[ -z "$total_hrp" ]] && total_hrp=0
    [[ -z "$ready_hrp" ]] && ready_hrp=0
    not_ready_hrp=$((total_hrp - ready_hrp))

    echo -e "  Total HelmReleaseProxies: ${BOLD}$total_hrp${NC}"
    echo -e "  Ready:                    ${GREEN}$ready_hrp${NC}"

    if [[ "$not_ready_hrp" -gt 0 ]]; then
        echo -e "  Not Ready:                ${RED}$not_ready_hrp${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Ready HelmReleaseProxies:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | \
                grep -v "True" | head -10 | while read -r ns name cluster ready status revision; do
                echo -e "    ${RED}→${NC} $ns/$name (cluster: $cluster)"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check AppDeployments (management cluster only)
check_appdeployments() {
    local kubeconfig=$1

    print_subheader "Kommander AppDeployments"

    # Check if AppDeployment CRD exists
    if ! KUBECONFIG="$kubeconfig" kubectl get crd appdeployments.apps.kommander.d2iq.io &>/dev/null; then
        echo -e "  ${YELLOW}AppDeployment CRD not installed - skipping${NC}"
        return 0
    fi

    local total_ad
    local synced_ad
    local not_synced_ad

    total_ad=$(KUBECONFIG="$kubeconfig" kubectl get appdeployments -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    [[ -z "$total_ad" ]] && total_ad=0

    # Check for synced AppDeployments by looking at status.clusters[].conditions
    # An AppDeployment is considered synced if all its clusters have AppDeploymentInstanceSynced=True
    synced_ad=$(KUBECONFIG="$kubeconfig" kubectl get appdeployments -A -o json 2>/dev/null | \
        jq '[.items[] | select(.status.clusters != null) | select(all(.status.clusters[].conditions[]?; select(.type == "AppDeploymentInstanceSynced") | .status == "True"))] | length' | tr -d '[:space:]')
    [[ -z "$synced_ad" ]] && synced_ad=0

    not_synced_ad=$((total_ad - synced_ad))

    echo -e "  Total AppDeployments:    ${BOLD}$total_ad${NC}"
    echo -e "  Synced:                  ${GREEN}$synced_ad${NC}"

    if [[ "$not_synced_ad" -gt 0 ]]; then
        echo -e "  Not Synced:              ${RED}$not_synced_ad${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Synced AppDeployments:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get appdeployments -A -o json 2>/dev/null | \
                jq -r '.items[] | select(.status.clusters != null) |
                    select(any(.status.clusters[].conditions[]?; select(.type == "AppDeploymentInstanceSynced") | .status != "True")) |
                    "\(.metadata.namespace)/\(.metadata.name)"' | head -10 | while read -r ad; do
                echo -e "    ${RED}→${NC} $ad"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check AppDeploymentInstances (management cluster only)
check_appdeploymentinstances() {
    local kubeconfig=$1

    print_subheader "Kommander AppDeploymentInstances"

    # Check if AppDeploymentInstance CRD exists
    if ! KUBECONFIG="$kubeconfig" kubectl get crd appdeploymentinstances.apps.kommander.d2iq.io &>/dev/null; then
        echo -e "  ${YELLOW}AppDeploymentInstance CRD not installed - skipping${NC}"
        return 0
    fi

    local total_adi
    local healthy_adi
    local not_healthy_adi

    total_adi=$(KUBECONFIG="$kubeconfig" kubectl get appdeploymentinstances -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    [[ -z "$total_adi" ]] && total_adi=0

    # Check for healthy AppDeploymentInstances (KustomizationReady=True and KustomizationHealthy=True)
    healthy_adi=$(KUBECONFIG="$kubeconfig" kubectl get appdeploymentinstances -A -o json 2>/dev/null | \
        jq '[.items[] | select(
            (.status.conditions[]? | select(.type == "KustomizationReady") | .status == "True") and
            (.status.conditions[]? | select(.type == "KustomizationHealthy") | .status == "True")
        )] | length' | tr -d '[:space:]')
    [[ -z "$healthy_adi" ]] && healthy_adi=0

    not_healthy_adi=$((total_adi - healthy_adi))

    echo -e "  Total AppDeploymentInstances: ${BOLD}$total_adi${NC}"
    echo -e "  Healthy:                      ${GREEN}$healthy_adi${NC}"

    if [[ "$not_healthy_adi" -gt 0 ]]; then
        echo -e "  Not Healthy:                  ${RED}$not_healthy_adi${NC}"

        if [[ "$SUMMARY_ONLY" != true ]]; then
            echo ""
            echo -e "  ${YELLOW}Not Healthy AppDeploymentInstances:${NC}"
            KUBECONFIG="$kubeconfig" kubectl get appdeploymentinstances -A -o json 2>/dev/null | \
                jq -r '.items[] | select(
                    ((.status.conditions[]? | select(.type == "KustomizationReady") | .status) != "True") or
                    ((.status.conditions[]? | select(.type == "KustomizationHealthy") | .status) != "True")
                ) | "\(.metadata.namespace)/\(.metadata.name)"' | head -10 | while read -r adi; do
                echo -e "    ${RED}→${NC} $adi"
            done
        fi
        return 1
    fi
    return 0
}

# Function to check a single cluster
check_cluster() {
    local cluster_name=$1
    local kubeconfig
    kubeconfig=$(get_kubeconfig "$cluster_name")

    local cluster_healthy=true
    local issues=()

    # Check if kubeconfig exists
    if [[ ! -f "$kubeconfig" ]]; then
        print_cluster_header "$cluster_name" "unreachable"
        echo -e "  ${RED}Kubeconfig not found: $kubeconfig${NC}"
        return 1
    fi

    # Check connectivity
    if ! check_cluster_connectivity "$kubeconfig"; then
        print_cluster_header "$cluster_name" "unreachable"
        echo -e "  ${RED}Cannot connect to cluster. Check kubeconfig: $kubeconfig${NC}"
        return 1
    fi

    # Get context name
    local context_name
    context_name=$(KUBECONFIG="$kubeconfig" kubectl config current-context 2>/dev/null || echo "unknown")

    # Check all components
    if ! check_nodes "$kubeconfig"; then
        cluster_healthy=false
        issues+=("nodes")
    fi

    if ! check_pods "$kubeconfig"; then
        cluster_healthy=false
        issues+=("pods")
    fi

    if ! check_kustomizations "$kubeconfig"; then
        cluster_healthy=false
        issues+=("kustomizations")
    fi

    if ! check_helmreleases "$kubeconfig"; then
        cluster_healthy=false
        issues+=("helmreleases")
    fi

    if ! check_gitrepositories "$kubeconfig"; then
        cluster_healthy=false
        issues+=("gitrepositories")
    fi

    # Management cluster specific checks
    if [[ "$cluster_name" == "mgmt" ]]; then
        if ! check_helmchartproxies "$kubeconfig"; then
            cluster_healthy=false
            issues+=("helmchartproxies")
        fi

        if ! check_helmreleaseproxies "$kubeconfig"; then
            cluster_healthy=false
            issues+=("helmreleaseproxies")
        fi

        if ! check_appdeployments "$kubeconfig"; then
            cluster_healthy=false
            issues+=("appdeployments")
        fi

        if ! check_appdeploymentinstances "$kubeconfig"; then
            cluster_healthy=false
            issues+=("appdeploymentinstances")
        fi
    fi

    # Print cluster header at the start
    if [[ "$cluster_healthy" == true ]]; then
        print_cluster_header "$cluster_name (context: $context_name)" "healthy"
    else
        print_cluster_header "$cluster_name (context: $context_name)" "degraded"
    fi

    return 0
}

# Function to print overall summary header
print_overall_summary_header() {
    print_header "OVERALL HEALTH SUMMARY"
    echo ""
    printf "%-12s | %-6s | %-6s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s\n" "Cluster" "Nodes" "Pods" "KS" "HR" "GR" "HCP" "HRP" "AD" "ADI"
    printf "%-12s-|-%-6s-|-%-6s-|-%-4s-|-%-4s-|-%-4s-|-%-4s-|-%-4s-|-%-4s-|-%-4s\n" "------------" "------" "------" "----" "----" "----" "----" "----" "----" "----"
}

# Function to print a summary row
print_summary_row() {
    local cluster=$1
    local summary=$2

    IFS=':' read -r nodes pods ks hr gr hcp hrp ad adi <<< "$summary"

    # Helper function to get symbol and color
    get_status_display() {
        local val=$1
        if [[ "$val" == "✓" ]]; then
            echo "${GREEN}✓${NC}"
        elif [[ "$val" == "-" ]]; then
            echo "${YELLOW}-${NC}"
        else
            echo "${RED}✗${NC}"
        fi
    }

    local nodes_d pods_d ks_d hr_d gr_d hcp_d hrp_d ad_d adi_d
    nodes_d=$(get_status_display "$nodes")
    pods_d=$(get_status_display "$pods")
    ks_d=$(get_status_display "$ks")
    hr_d=$(get_status_display "$hr")
    gr_d=$(get_status_display "$gr")
    hcp_d=$(get_status_display "$hcp")
    hrp_d=$(get_status_display "$hrp")
    ad_d=$(get_status_display "$ad")
    adi_d=$(get_status_display "$adi")

    # Use echo -e for proper color rendering
    echo -e "$(printf '%-12s' "$cluster") | ${nodes_d}      | ${pods_d}      | ${ks_d}    | ${hr_d}    | ${gr_d}    | ${hcp_d}    | ${hrp_d}    | ${ad_d}    | ${adi_d}"
}

# Function to print summary footer
print_summary_footer() {
    echo ""
    echo -e "Legend: ${GREEN}✓${NC} = Healthy, ${RED}✗${NC} = Issues, ${YELLOW}-${NC} = N/A or Not Installed"
    echo ""
    echo -e "Columns: KS=Kustomizations, HR=HelmReleases, GR=GitRepos, HCP=HelmChartProxies, HRP=HelmReleaseProxies,"
    echo -e "         AD=AppDeployments, ADI=AppDeploymentInstances (HCP, HRP, AD, ADI are management cluster only)"
}

# Function to collect summary data for a cluster
collect_cluster_summary() {
    local cluster_name=$1
    local kubeconfig
    kubeconfig=$(get_kubeconfig "$cluster_name")

    local nodes="✗"
    local pods="✗"
    local ks="-"
    local hr="-"
    local gr="-"
    local hcp="-"
    local hrp="-"
    local ad="-"
    local adi="-"

    if [[ ! -f "$kubeconfig" ]] || ! check_cluster_connectivity "$kubeconfig" 2>/dev/null; then
        echo "✗:✗:✗:✗:✗:-:-:-:-"
        return
    fi

    # Check nodes
    local not_ready_nodes
    not_ready_nodes=$(KUBECONFIG="$kubeconfig" kubectl get nodes --no-headers 2>/dev/null | grep -cv " Ready " | tr -d '[:space:]')
    [[ -z "$not_ready_nodes" ]] && not_ready_nodes=0
    [[ "$not_ready_nodes" -eq 0 ]] && nodes="✓"

    # Check pods
    local problem_pods
    problem_pods=$(KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null | \
        grep -cE "Failed|Error|Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull" | tr -d '[:space:]')
    [[ -z "$problem_pods" ]] && problem_pods=0
    [[ "$problem_pods" -eq 0 ]] && pods="✓"

    # Check kustomizations
    if KUBECONFIG="$kubeconfig" kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io &>/dev/null; then
        local not_ready_ks
        local total_ks
        total_ks=$(KUBECONFIG="$kubeconfig" kubectl get kustomizations -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
        local ready_ks
        ready_ks=$(KUBECONFIG="$kubeconfig" kubectl get kustomizations -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
        [[ -z "$total_ks" ]] && total_ks=0
        [[ -z "$ready_ks" ]] && ready_ks=0
        not_ready_ks=$((total_ks - ready_ks))
        [[ "$not_ready_ks" -eq 0 ]] && ks="✓" || ks="✗"
    fi

    # Check helmreleases (Flux)
    if KUBECONFIG="$kubeconfig" kubectl get crd helmreleases.helm.toolkit.fluxcd.io &>/dev/null; then
        local not_ready_hr
        local total_hr
        total_hr=$(KUBECONFIG="$kubeconfig" kubectl get helmreleases -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
        local ready_hr
        ready_hr=$(KUBECONFIG="$kubeconfig" kubectl get helmreleases -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
        [[ -z "$total_hr" ]] && total_hr=0
        [[ -z "$ready_hr" ]] && ready_hr=0
        not_ready_hr=$((total_hr - ready_hr))
        [[ "$not_ready_hr" -eq 0 ]] && hr="✓" || hr="✗"
    fi

    # Check gitrepositories
    if KUBECONFIG="$kubeconfig" kubectl get crd gitrepositories.source.toolkit.fluxcd.io &>/dev/null; then
        local not_ready_gr
        local total_gr
        total_gr=$(KUBECONFIG="$kubeconfig" kubectl get gitrepositories -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
        local ready_gr
        ready_gr=$(KUBECONFIG="$kubeconfig" kubectl get gitrepositories -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
        [[ -z "$total_gr" ]] && total_gr=0
        [[ -z "$ready_gr" ]] && ready_gr=0
        not_ready_gr=$((total_gr - ready_gr))
        [[ "$not_ready_gr" -eq 0 ]] && gr="✓" || gr="✗"
    fi

    # Management cluster specific checks
    if [[ "$cluster_name" == "mgmt" ]]; then
        # Check HelmChartProxies
        if KUBECONFIG="$kubeconfig" kubectl get crd helmchartproxies.addons.cluster.x-k8s.io &>/dev/null; then
            local not_ready_hcp
            local total_hcp
            total_hcp=$(KUBECONFIG="$kubeconfig" kubectl get helmchartproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
            local ready_hcp
            ready_hcp=$(KUBECONFIG="$kubeconfig" kubectl get helmchartproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
            [[ -z "$total_hcp" ]] && total_hcp=0
            [[ -z "$ready_hcp" ]] && ready_hcp=0
            not_ready_hcp=$((total_hcp - ready_hcp))
            [[ "$not_ready_hcp" -eq 0 ]] && hcp="✓" || hcp="✗"
        fi

        # Check HelmReleaseProxies
        if KUBECONFIG="$kubeconfig" kubectl get crd helmreleaseproxies.addons.cluster.x-k8s.io &>/dev/null; then
            local not_ready_hrp
            local total_hrp
            total_hrp=$(KUBECONFIG="$kubeconfig" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
            local ready_hrp
            ready_hrp=$(KUBECONFIG="$kubeconfig" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
            [[ -z "$total_hrp" ]] && total_hrp=0
            [[ -z "$ready_hrp" ]] && ready_hrp=0
            not_ready_hrp=$((total_hrp - ready_hrp))
            [[ "$not_ready_hrp" -eq 0 ]] && hrp="✓" || hrp="✗"
        fi

        # Check AppDeployments
        if KUBECONFIG="$kubeconfig" kubectl get crd appdeployments.apps.kommander.d2iq.io &>/dev/null; then
            local total_ad
            local synced_ad
            total_ad=$(KUBECONFIG="$kubeconfig" kubectl get appdeployments -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
            [[ -z "$total_ad" ]] && total_ad=0
            synced_ad=$(KUBECONFIG="$kubeconfig" kubectl get appdeployments -A -o json 2>/dev/null | \
                jq '[.items[] | select(.status.clusters != null) | select(all(.status.clusters[].conditions[]?; select(.type == "AppDeploymentInstanceSynced") | .status == "True"))] | length' | tr -d '[:space:]')
            [[ -z "$synced_ad" ]] && synced_ad=0
            local not_synced_ad=$((total_ad - synced_ad))
            [[ "$not_synced_ad" -eq 0 ]] && ad="✓" || ad="✗"
        fi

        # Check AppDeploymentInstances
        if KUBECONFIG="$kubeconfig" kubectl get crd appdeploymentinstances.apps.kommander.d2iq.io &>/dev/null; then
            local total_adi
            local healthy_adi
            total_adi=$(KUBECONFIG="$kubeconfig" kubectl get appdeploymentinstances -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
            [[ -z "$total_adi" ]] && total_adi=0
            healthy_adi=$(KUBECONFIG="$kubeconfig" kubectl get appdeploymentinstances -A -o json 2>/dev/null | \
                jq '[.items[] | select(
                    (.status.conditions[]? | select(.type == "KustomizationReady") | .status == "True") and
                    (.status.conditions[]? | select(.type == "KustomizationHealthy") | .status == "True")
                )] | length' | tr -d '[:space:]')
            [[ -z "$healthy_adi" ]] && healthy_adi=0
            local not_healthy_adi=$((total_adi - healthy_adi))
            [[ "$not_healthy_adi" -eq 0 ]] && adi="✓" || adi="✗"
        fi
    fi

    echo "$nodes:$pods:$ks:$hr:$gr:$hcp:$hrp:$ad:$adi"
}

# Main function
main() {
    clear 2>/dev/null || true

    echo -e "${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           NKP CLUSTER HEALTH CHECK                               ║"
    echo "║           $(date '+%Y-%m-%d %H:%M:%S')                                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Collect and display summary
    print_overall_summary_header

    for cluster in "${SELECTED_CLUSTERS[@]}"; do
        local summary
        summary=$(collect_cluster_summary "$cluster")
        print_summary_row "$cluster" "$summary"
    done

    print_summary_footer

    # Print detailed info unless summary only
    if [[ "$SUMMARY_ONLY" != true ]]; then
        for cluster in "${SELECTED_CLUSTERS[@]}"; do
            check_cluster "$cluster"
        done
    fi

    # Quick actions
    print_header "QUICK ACTIONS"
    echo ""
    echo "Check specific cluster in detail:"
    echo -e "  ${GREEN}./scripts/check-cluster-health.sh mgmt${NC}"
    echo ""
    echo "Watch mode (refresh every 30s):"
    echo -e "  ${GREEN}./scripts/check-cluster-health.sh --watch${NC}"
    echo ""
    echo "Force reconcile all Flux resources:"
    echo -e "  ${GREEN}flux reconcile kustomization flux-system --with-source${NC}"
    echo ""
    echo "View pod logs for a failing pod:"
    echo -e "  ${GREEN}kubectl logs -n <namespace> <pod-name> --previous${NC}"
    echo ""
    echo "Describe a failing resource:"
    echo -e "  ${GREEN}kubectl describe pod -n <namespace> <pod-name>${NC}"
    echo ""
}

# Run main function
if [[ "$WATCH_MODE" == true ]]; then
    while true; do
        main
        echo ""
        echo -e "${BLUE}Refreshing in ${WATCH_INTERVAL}s... (Ctrl+C to stop)${NC}"
        sleep "$WATCH_INTERVAL"
    done
else
    main
fi

