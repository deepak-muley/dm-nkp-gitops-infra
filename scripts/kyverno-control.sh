#!/bin/bash
#
# Kyverno Control Script
#
# Enable or disable Kyverno policies and webhooks on the management cluster.
#
# Usage:
#   ./scripts/kyverno-control.sh --enable          # Enable Kyverno
#   ./scripts/kyverno-control.sh --disable         # Disable Kyverno
#   ./scripts/kyverno-control.sh --status          # Check current status
#   ./scripts/kyverno-control.sh --enable mgmt     # Enable on management cluster
#   ./scripts/kyverno-control.sh --disable mgmt    # Disable on management cluster
#
# Author: Platform Team
# Date: January 2025
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default kubeconfig locations for NKP clusters
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
DEFAULT_WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Kyverno resources
KYVERNO_KUSTOMIZATION="clusterops-kyverno-policies"
KYVERNO_KUSTOMIZATION_NS="dm-nkp-gitops-infra"
KYVERNO_APPDEPLOYMENT="kyverno"
KYVERNO_APPDEPLOYMENT_NS="kommander"
KYVERNO_NAMESPACE="kyverno"

# Webhook names (Kyverno creates these - match any webhook with kyverno in the name or service)
VALIDATING_WEBHOOK_PATTERN="kyverno"
MUTATING_WEBHOOK_PATTERN="kyverno"

ACTION=""
KUBECONFIG_FILE=""
DRY_RUN=false

# Function to resolve kubeconfig path
resolve_kubeconfig() {
    local arg="$1"
    case "$arg" in
        mgmt|management)
            echo "$DEFAULT_MGMT_KUBECONFIG"
            ;;
        workload1|workload-1)
            echo "$DEFAULT_WORKLOAD1_KUBECONFIG"
            ;;
        workload2|workload-2)
            echo "$DEFAULT_WORKLOAD2_KUBECONFIG"
            ;;
        *)
            if [[ -f "$arg" ]]; then
                echo "$arg"
            else
                echo ""
            fi
            ;;
    esac
}

# Function to print header
print_header() {
    local title="$1"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Function to print status
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        success)
            echo -e "${GREEN}✓${NC} $message"
            ;;
        error)
            echo -e "${RED}✗${NC} $message"
            ;;
        warning)
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        info)
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
    esac
}

# Function to check if kubectl is available
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_status "error" "kubectl is not installed or not in PATH"
        exit 1
    fi

    if [[ -z "$KUBECONFIG_FILE" ]]; then
        print_status "error" "Kubeconfig file not specified or not found"
        exit 1
    fi

    if [[ ! -f "$KUBECONFIG_FILE" ]]; then
        print_status "error" "Kubeconfig file not found: $KUBECONFIG_FILE"
        exit 1
    fi

    # Test kubectl access
    if ! kubectl --kubeconfig="$KUBECONFIG_FILE" cluster-info &> /dev/null; then
        print_status "error" "Cannot access cluster with kubeconfig: $KUBECONFIG_FILE"
        exit 1
    fi

    # Warn if jq is not available (script will use fallback)
    if ! command -v jq &> /dev/null; then
        print_status "warning" "jq is not installed - webhook detection may be less accurate"
    fi
}

# Function to get Kyverno webhook names
get_kyverno_webhooks() {
    local webhook_type="$1"  # validating or mutating

    # Try using jq if available - check both name and service namespace
    if command -v jq &> /dev/null; then
        kubectl --kubeconfig="$KUBECONFIG_FILE" get "${webhook_type}webhookconfiguration" -o json 2>/dev/null | \
            jq -r ".items[] | select(.metadata.name | ascii_downcase | contains(\"kyverno\") or (.webhooks[0].clientConfig.service.namespace // \"\") == \"$KYVERNO_NAMESPACE\") | .metadata.name" 2>/dev/null || echo ""
    else
        # Fallback: use grep to find webhooks containing kyverno
        kubectl --kubeconfig="$KUBECONFIG_FILE" get "${webhook_type}webhookconfiguration" -o name 2>/dev/null | \
            grep -i "kyverno" | sed 's/.*\///' || echo ""
    fi
}

# Function to disable webhook
disable_webhook() {
    local webhook_name="$1"
    local webhook_type="$2"  # ValidatingWebhookConfiguration or MutatingWebhookConfiguration

    if [[ -z "$webhook_name" ]]; then
        return 0
    fi

    print_status "info" "Disabling $webhook_type: $webhook_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would disable webhook: $webhook_name"
        return 0
    fi

    # Get webhook count
    local webhook_count=0
    if command -v jq &> /dev/null; then
        webhook_count=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get "$webhook_type" "$webhook_name" -o json 2>/dev/null | \
            jq '.webhooks | length' 2>/dev/null || echo "0")
    else
        # Fallback: try to count webhooks
        webhook_count=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get "$webhook_type" "$webhook_name" -o jsonpath='{.webhooks[*].name}' 2>/dev/null | wc -w | tr -d ' ')
    fi

    if [[ "$webhook_count" -gt 0 ]]; then
        # Disable all webhooks in the configuration
        local patch_ops="["
        for ((i=0; i<webhook_count; i++)); do
            if [[ $i -gt 0 ]]; then
                patch_ops+=","
            fi
            patch_ops+="{\"op\": \"replace\", \"path\": \"/webhooks/$i/failurePolicy\", \"value\": \"Ignore\"}"
        done
        patch_ops+="]"

        kubectl --kubeconfig="$KUBECONFIG_FILE" patch "$webhook_type" "$webhook_name" \
            --type='json' \
            -p="$patch_ops" 2>/dev/null || true
    fi

    # Also scale down the admission controller to prevent webhook calls
    if [[ "$webhook_type" == "MutatingWebhookConfiguration" ]] || [[ "$webhook_type" == "ValidatingWebhookConfiguration" ]]; then
        kubectl --kubeconfig="$KUBECONFIG_FILE" scale deployment kyverno-admission-controller -n "$KYVERNO_NAMESPACE" --replicas=0 2>/dev/null || true
    fi
}

# Function to enable webhook
enable_webhook() {
    local webhook_name="$1"
    local webhook_type="$2"  # ValidatingWebhookConfiguration or MutatingWebhookConfiguration

    if [[ -z "$webhook_name" ]]; then
        return 0
    fi

    print_status "info" "Enabling $webhook_type: $webhook_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would enable webhook: $webhook_name"
        return 0
    fi

    # Get webhook count
    local webhook_count=0
    if command -v jq &> /dev/null; then
        webhook_count=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get "$webhook_type" "$webhook_name" -o json 2>/dev/null | \
            jq '.webhooks | length' 2>/dev/null || echo "0")
    else
        # Fallback: try to count webhooks
        webhook_count=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get "$webhook_type" "$webhook_name" -o jsonpath='{.webhooks[*].name}' 2>/dev/null | wc -w | tr -d ' ')
    fi

    if [[ "$webhook_count" -gt 0 ]]; then
        # Restore webhook to default failure policy (Fail)
        local patch_ops="["
        for ((i=0; i<webhook_count; i++)); do
            if [[ $i -gt 0 ]]; then
                patch_ops+=","
            fi
            patch_ops+="{\"op\": \"replace\", \"path\": \"/webhooks/$i/failurePolicy\", \"value\": \"Fail\"}"
        done
        patch_ops+="]"

        kubectl --kubeconfig="$KUBECONFIG_FILE" patch "$webhook_type" "$webhook_name" \
            --type='json' \
            -p="$patch_ops" 2>/dev/null || true
    fi

    # Scale up the admission controller
    if [[ "$webhook_type" == "MutatingWebhookConfiguration" ]] || [[ "$webhook_type" == "ValidatingWebhookConfiguration" ]]; then
        kubectl --kubeconfig="$KUBECONFIG_FILE" scale deployment kyverno-admission-controller -n "$KYVERNO_NAMESPACE" --replicas=1 2>/dev/null || true
    fi
}

# Function to disable Kyverno
disable_kyverno() {
    print_header "Disabling Kyverno"

    # 1. Suspend Flux Kustomization for policies
    print_status "info" "Suspending Flux Kustomization: $KYVERNO_KUSTOMIZATION"
    if [[ "$DRY_RUN" != "true" ]]; then
        if kubectl --kubeconfig="$KUBECONFIG_FILE" get kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" &>/dev/null; then
            kubectl --kubeconfig="$KUBECONFIG_FILE" annotate kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" \
                kustomize.toolkit.fluxcd.io/suspend=true --overwrite 2>/dev/null || \
            flux suspend kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" --kubeconfig="$KUBECONFIG_FILE" 2>/dev/null || true
            print_status "success" "Suspended Flux Kustomization: $KYVERNO_KUSTOMIZATION"
        else
            print_status "warning" "Flux Kustomization not found: $KYVERNO_KUSTOMIZATION"
        fi
    else
        echo -e "${YELLOW}[DRY RUN]${NC} Would suspend Flux Kustomization: $KYVERNO_KUSTOMIZATION"
    fi

    echo ""

    # 2. Disable ValidatingWebhookConfigurations
    print_status "info" "Disabling Kyverno ValidatingWebhookConfigurations"
    local validating_webhooks=$(get_kyverno_webhooks "validating")
    if [[ -n "$validating_webhooks" ]]; then
        while IFS= read -r webhook; do
            [[ -n "$webhook" ]] && disable_webhook "$webhook" "ValidatingWebhookConfiguration"
        done <<< "$validating_webhooks"
    else
        print_status "warning" "No Kyverno ValidatingWebhookConfigurations found"
    fi

    echo ""

    # 3. Disable MutatingWebhookConfigurations
    print_status "info" "Disabling Kyverno MutatingWebhookConfigurations"
    local mutating_webhooks=$(get_kyverno_webhooks "mutating")
    if [[ -n "$mutating_webhooks" ]]; then
        while IFS= read -r webhook; do
            [[ -n "$webhook" ]] && disable_webhook "$webhook" "MutatingWebhookConfiguration"
        done <<< "$mutating_webhooks"
    else
        print_status "warning" "No Kyverno MutatingWebhookConfigurations found"
    fi

    echo ""
    print_status "success" "Kyverno has been disabled"
}

# Function to enable Kyverno
enable_kyverno() {
    print_header "Enabling Kyverno"

    # 1. Resume Flux Kustomization for policies
    print_status "info" "Resuming Flux Kustomization: $KYVERNO_KUSTOMIZATION"
    if [[ "$DRY_RUN" != "true" ]]; then
        if kubectl --kubeconfig="$KUBECONFIG_FILE" get kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" &>/dev/null; then
            kubectl --kubeconfig="$KUBECONFIG_FILE" annotate kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" \
                kustomize.toolkit.fluxcd.io/suspend- --overwrite 2>/dev/null || \
            flux resume kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" --kubeconfig="$KUBECONFIG_FILE" 2>/dev/null || true
            print_status "success" "Resumed Flux Kustomization: $KYVERNO_KUSTOMIZATION"
        else
            print_status "warning" "Flux Kustomization not found: $KYVERNO_KUSTOMIZATION"
        fi
    else
        echo -e "${YELLOW}[DRY RUN]${NC} Would resume Flux Kustomization: $KYVERNO_KUSTOMIZATION"
    fi

    echo ""

    # 2. Enable ValidatingWebhookConfigurations
    print_status "info" "Enabling Kyverno ValidatingWebhookConfigurations"
    local validating_webhooks=$(get_kyverno_webhooks "validating")
    if [[ -n "$validating_webhooks" ]]; then
        while IFS= read -r webhook; do
            [[ -n "$webhook" ]] && enable_webhook "$webhook" "ValidatingWebhookConfiguration"
        done <<< "$validating_webhooks"
    else
        print_status "warning" "No Kyverno ValidatingWebhookConfigurations found"
    fi

    echo ""

    # 3. Enable MutatingWebhookConfigurations
    print_status "info" "Enabling Kyverno MutatingWebhookConfigurations"
    local mutating_webhooks=$(get_kyverno_webhooks "mutating")
    if [[ -n "$mutating_webhooks" ]]; then
        while IFS= read -r webhook; do
            [[ -n "$webhook" ]] && enable_webhook "$webhook" "MutatingWebhookConfiguration"
        done <<< "$mutating_webhooks"
    else
        print_status "warning" "No Kyverno MutatingWebhookConfigurations found"
    fi

    echo ""
    print_status "success" "Kyverno has been enabled"
}

# Function to check status
check_status() {
    print_header "Kyverno Status"

    # Check Flux Kustomization
    echo -e "${CYAN}Flux Kustomization:${NC}"
    if kubectl --kubeconfig="$KUBECONFIG_FILE" get kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" &>/dev/null; then
        local suspended=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" -o jsonpath='{.metadata.annotations.kustomize\.toolkit\.fluxcd\.io/suspend}' 2>/dev/null || echo "false")
        local ready=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get kustomization "$KYVERNO_KUSTOMIZATION" -n "$KYVERNO_KUSTOMIZATION_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

        if [[ "$suspended" == "true" ]]; then
            print_status "warning" "Kustomization is SUSPENDED"
        else
            print_status "success" "Kustomization is ACTIVE (Ready: $ready)"
        fi
        echo ""
    else
        print_status "error" "Kustomization not found: $KYVERNO_KUSTOMIZATION"
        echo ""
    fi

    # Check AppDeployment
    echo -e "${CYAN}AppDeployment:${NC}"
    if kubectl --kubeconfig="$KUBECONFIG_FILE" get appdeployment "$KYVERNO_APPDEPLOYMENT" -n "$KYVERNO_APPDEPLOYMENT_NS" &>/dev/null; then
        local suspended=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get appdeployment "$KYVERNO_APPDEPLOYMENT" -n "$KYVERNO_APPDEPLOYMENT_NS" -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "false")
        if [[ "$suspended" == "true" ]]; then
            print_status "warning" "AppDeployment is SUSPENDED"
        else
            print_status "success" "AppDeployment is ACTIVE"
        fi
        echo ""
    else
        print_status "warning" "AppDeployment not found: $KYVERNO_APPDEPLOYMENT"
        echo ""
    fi

    # Check ValidatingWebhookConfigurations
    echo -e "${CYAN}ValidatingWebhookConfigurations:${NC}"
    local validating_webhooks=$(get_kyverno_webhooks "validating")
    if [[ -n "$validating_webhooks" ]]; then
        while IFS= read -r webhook; do
            if [[ -n "$webhook" ]]; then
                local failure_policy=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get validatingwebhookconfiguration "$webhook" -o jsonpath='{.webhooks[0].failurePolicy}' 2>/dev/null || echo "Unknown")
                if [[ "$failure_policy" == "Ignore" ]]; then
                    print_status "warning" "$webhook: DISABLED (failurePolicy=Ignore)"
                else
                    print_status "success" "$webhook: ENABLED (failurePolicy=$failure_policy)"
                fi
            fi
        done <<< "$validating_webhooks"
    else
        print_status "warning" "No Kyverno ValidatingWebhookConfigurations found"
    fi
    echo ""

    # Check MutatingWebhookConfigurations
    echo -e "${CYAN}MutatingWebhookConfigurations:${NC}"
    local mutating_webhooks=$(get_kyverno_webhooks "mutating")
    if [[ -n "$mutating_webhooks" ]]; then
        while IFS= read -r webhook; do
            if [[ -n "$webhook" ]]; then
                local failure_policy=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get mutatingwebhookconfiguration "$webhook" -o jsonpath='{.webhooks[0].failurePolicy}' 2>/dev/null || echo "Unknown")
                if [[ "$failure_policy" == "Ignore" ]]; then
                    print_status "warning" "$webhook: DISABLED (failurePolicy=Ignore)"
                else
                    print_status "success" "$webhook: ENABLED (failurePolicy=$failure_policy)"
                fi
            fi
        done <<< "$mutating_webhooks"
    else
        print_status "warning" "No Kyverno MutatingWebhookConfigurations found"
    fi
    echo ""

    # Check Kyverno pods
    echo -e "${CYAN}Kyverno Pods:${NC}"
    if kubectl --kubeconfig="$KUBECONFIG_FILE" get namespace "$KYVERNO_NAMESPACE" &>/dev/null; then
        local pod_count=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get pods -n "$KYVERNO_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$pod_count" -gt 0 ]]; then
            kubectl --kubeconfig="$KUBECONFIG_FILE" get pods -n "$KYVERNO_NAMESPACE" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready 2>/dev/null || true
        else
            print_status "warning" "No pods found in namespace: $KYVERNO_NAMESPACE"
        fi
    else
        print_status "warning" "Namespace not found: $KYVERNO_NAMESPACE"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --enable|-e)
            ACTION="enable"
            shift
            ;;
        --disable|-d)
            ACTION="disable"
            shift
            ;;
        --status|-s)
            ACTION="status"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --kubeconfig|-k)
            if [[ -n "$2" && "$2" != -* ]]; then
                KUBECONFIG_FILE=$(resolve_kubeconfig "$2")
                if [[ -z "$KUBECONFIG_FILE" ]]; then
                    echo -e "${RED}Error: Invalid kubeconfig: $2${NC}"
                    exit 1
                fi
                shift 2
            else
                echo -e "${RED}Error: --kubeconfig requires a path${NC}"
                exit 1
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [KUBECONFIG]"
            echo ""
            echo "Actions:"
            echo "  --enable, -e          Enable Kyverno (resume policies, enable webhooks)"
            echo "  --disable, -d          Disable Kyverno (suspend policies, disable webhooks)"
            echo "  --status, -s           Check current Kyverno status"
            echo ""
            echo "Options:"
            echo "  --kubeconfig, -k PATH  Path to kubeconfig file"
            echo "  --dry-run              Show what would be done without making changes"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Kubeconfig shortcuts:"
            echo "  mgmt         Use management cluster kubeconfig"
            echo "  workload1    Use workload cluster 1 kubeconfig"
            echo "  workload2    Use workload cluster 2 kubeconfig"
            echo ""
            echo "Examples:"
            echo "  $0 --disable                    # Disable Kyverno (uses default mgmt kubeconfig)"
            echo "  $0 --enable mgmt                # Enable Kyverno on management cluster"
            echo "  $0 --status mgmt                # Check status on management cluster"
            echo "  $0 --disable --dry-run          # Show what would be disabled"
            echo "  $0 --enable -k /path/to/config  # Enable with custom kubeconfig"
            exit 0
            ;;
        mgmt|management|workload1|workload-1|workload2|workload-2)
            if [[ -z "$KUBECONFIG_FILE" ]]; then
                KUBECONFIG_FILE=$(resolve_kubeconfig "$1")
            fi
            shift
            ;;
        *)
            if [[ -z "$KUBECONFIG_FILE" ]]; then
                KUBECONFIG_FILE=$(resolve_kubeconfig "$1")
                if [[ -z "$KUBECONFIG_FILE" ]]; then
                    echo -e "${RED}Error: Unknown option or invalid kubeconfig: $1${NC}"
                    echo "Use --help for usage information"
                    exit 1
                fi
            else
                echo -e "${RED}Error: Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set default kubeconfig if not specified
if [[ -z "$KUBECONFIG_FILE" ]]; then
    KUBECONFIG_FILE="$DEFAULT_MGMT_KUBECONFIG"
fi

# Validate action
if [[ -z "$ACTION" ]]; then
    echo -e "${RED}Error: Must specify --enable, --disable, or --status${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Check prerequisites
check_prerequisites

# Execute action
case "$ACTION" in
    enable)
        enable_kyverno
        ;;
    disable)
        disable_kyverno
        ;;
    status)
        check_status
        ;;
    *)
        echo -e "${RED}Error: Unknown action: $ACTION${NC}"
        exit 1
        ;;
esac
