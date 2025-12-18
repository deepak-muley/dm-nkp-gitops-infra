#!/bin/bash
#
# Bootstrap script to create ClusterResourceSet for sealed-secrets private key
#
# This script creates a Secret containing the sealed-secrets private key and
# a ClusterResourceSet that deploys it to all workload clusters.
#
# SECURITY: The private key is NEVER stored in git. It is loaded from a local
# file and applied directly to the management cluster.
#
# Prerequisites:
# - kubectl configured with management cluster context
# - Sealed-secrets private key backup file exists
#
# Usage:
#   ./scripts/bootstrap-sealed-secrets-key-crs.sh [options]
#
# Options:
#   -k, --kubeconfig    Path to kubeconfig (default: uses KUBECONFIG env or default context)
#   -f, --key-file      Path to sealed-secrets key backup (default: /Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml)
#   -n, --namespace     Namespace for ClusterResourceSet (default: dm-dev-workspace)
#   -d, --dry-run       Show what would be created without applying
#   -c, --cleanup       Remove the ClusterResourceSet and Secret
#   -h, --help          Show this help message

set -euo pipefail

# Default values
KUBECONFIG_PATH="${KUBECONFIG:-}"
KEY_FILE="/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml"
NAMESPACE="dm-dev-workspace"
DRY_RUN=false
CLEANUP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resource names
SECRET_NAME="sealed-secrets-key-resources"
CRS_NAME="sealed-secrets-key-crs"

print_usage() {
    head -30 "$0" | tail -25
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -f|--key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Set kubectl command with optional kubeconfig
KUBECTL="kubectl"
if [[ -n "$KUBECONFIG_PATH" ]]; then
    KUBECTL="kubectl --kubeconfig=$KUBECONFIG_PATH"
fi

# Cleanup mode
if [[ "$CLEANUP" == "true" ]]; then
    log_info "Cleaning up ClusterResourceSet and Secret..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete ClusterResourceSet: $CRS_NAME"
        log_info "[DRY-RUN] Would delete Secret: $SECRET_NAME"
    else
        $KUBECTL delete clusterresourceset "$CRS_NAME" -n "$NAMESPACE" --ignore-not-found
        $KUBECTL delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
        log_success "Cleanup completed"
    fi
    exit 0
fi

# Verify key file exists
if [[ ! -f "$KEY_FILE" ]]; then
    log_error "Sealed-secrets key file not found: $KEY_FILE"
    log_error "Please ensure the key backup exists at the specified location."
    exit 1
fi

log_info "Using sealed-secrets key from: $KEY_FILE"
log_info "Target namespace: $NAMESPACE"

# Verify we can connect to the cluster
if ! $KUBECTL cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

log_info "Connected to cluster: $($KUBECTL config current-context)"

# Verify namespace exists
if ! $KUBECTL get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Read the key file content
KEY_CONTENT=$(cat "$KEY_FILE")

# Validate it looks like a sealed-secrets key
if ! echo "$KEY_CONTENT" | grep -q "kind: Secret"; then
    log_error "Key file doesn't appear to be a valid Kubernetes Secret"
    exit 1
fi

if ! echo "$KEY_CONTENT" | grep -q "sealed-secrets-key"; then
    log_warn "Key file might not be a sealed-secrets key (name doesn't contain 'sealed-secrets-key')"
fi

# Create the Secret that will hold the key content for ClusterResourceSet
# The Secret data contains the YAML that will be applied to workload clusters
log_info "Creating Secret with sealed-secrets key content..."

SECRET_MANIFEST=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: sealed-secrets
    app.kubernetes.io/component: cluster-resource-set
  annotations:
    description: "Contains sealed-secrets private key for ClusterResourceSet deployment"
type: addons.cluster.x-k8s.io/resource-set
stringData:
  sealed-secrets-key.yaml: |
$(echo "$KEY_CONTENT" | sed 's/^/    /')
EOF
)

# Create the ClusterResourceSet
log_info "Creating ClusterResourceSet..."

CRS_MANIFEST=$(cat <<EOF
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: ${CRS_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: sealed-secrets
    app.kubernetes.io/component: cluster-resource-set
  annotations:
    description: "Deploys sealed-secrets private key to workload clusters"
spec:
  # Select all Nutanix-based clusters
  clusterSelector:
    matchLabels:
      konvoy.d2iq.io/provider: nutanix
  resources:
    - kind: Secret
      name: ${SECRET_NAME}
  # ApplyOnce ensures key is deployed when cluster is provisioned
  strategy: ApplyOnce
EOF
)

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create the following resources:"
    echo ""
    echo "--- Secret (contains sealed-secrets key) ---"
    echo "$SECRET_MANIFEST" | head -20
    echo "... (key content truncated for security) ..."
    echo ""
    echo "--- ClusterResourceSet ---"
    echo "$CRS_MANIFEST"
    echo ""
    log_info "[DRY-RUN] No changes made"
else
    # Apply the Secret
    echo "$SECRET_MANIFEST" | $KUBECTL apply -f -
    log_success "Secret '$SECRET_NAME' created/updated"

    # Apply the ClusterResourceSet
    echo "$CRS_MANIFEST" | $KUBECTL apply -f -
    log_success "ClusterResourceSet '$CRS_NAME' created/updated"

    echo ""
    log_success "Bootstrap completed!"
    echo ""
    log_info "The sealed-secrets private key will be automatically deployed to all"
    log_info "clusters matching label: konvoy.d2iq.io/provider=nutanix"
    echo ""
    log_info "To verify:"
    echo "  $KUBECTL get clusterresourceset -n $NAMESPACE"
    echo "  $KUBECTL get clusterresourcesetbinding -n $NAMESPACE"
    echo ""
    log_warn "SECURITY REMINDER: The private key is stored in a Kubernetes Secret"
    log_warn "in the management cluster. It is NOT stored in git."
fi

