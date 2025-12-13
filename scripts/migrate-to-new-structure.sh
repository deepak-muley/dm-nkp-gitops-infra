#!/bin/bash
#
# Migration Script: Safely migrate to new management-cluster/workload-clusters structure
#
# This script handles the path change and bootstraps workload clusters.
#
# Usage:
#   ./scripts/migrate-to-new-structure.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Kubeconfig paths
MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Flux resources
KUSTOMIZATION_NAME="clusterops-usa-az1"
KUSTOMIZATION_NAMESPACE="kommander"
GITREPO_NAME="gitops-usa-az1"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
NEW_BOOTSTRAP_PATH="$REPO_ROOT/region-usa/az1/management-cluster/bootstrap.yaml"
WORKLOAD1_BOOTSTRAP="$REPO_ROOT/region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml"
WORKLOAD2_BOOTSTRAP="$REPO_ROOT/region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  NKP GitOps Structure Migration Script                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for user confirmation
confirm() {
    echo -e "${YELLOW}$1${NC}"
    read -p "Press Enter to continue or Ctrl+C to abort..."
}

# Check kubeconfig files exist
echo -e "${BLUE}[1/10] Checking kubeconfig files...${NC}"
for kc in "$MGMT_KUBECONFIG" "$WORKLOAD1_KUBECONFIG" "$WORKLOAD2_KUBECONFIG"; do
    if [ -f "$kc" ]; then
        echo -e "${GREEN}✓ Found: $kc${NC}"
    else
        echo -e "${RED}✗ Missing: $kc${NC}"
    fi
done
echo ""

# Check management cluster connectivity
echo -e "${BLUE}[2/10] Checking management cluster connectivity...${NC}"
export KUBECONFIG="$MGMT_KUBECONFIG"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to management cluster${NC}"
    echo "Kubeconfig: $MGMT_KUBECONFIG"
    exit 1
fi
echo -e "${GREEN}✓ Connected to management cluster${NC}"
kubectl config current-context
echo ""

# Check if the kustomization exists
echo -e "${BLUE}[3/10] Checking existing Flux Kustomization...${NC}"
if kubectl get kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Found existing Kustomization: $KUSTOMIZATION_NAME${NC}"
    CURRENT_PATH=$(kubectl get kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" -o jsonpath='{.spec.path}')
    echo -e "  Current path: ${YELLOW}$CURRENT_PATH${NC}"
    echo -e "  New path:     ${GREEN}./region-usa/az1/management-cluster${NC}"
    NEEDS_MIGRATION=true
else
    echo -e "${YELLOW}No existing Kustomization found - fresh deployment${NC}"
    NEEDS_MIGRATION=false
fi
echo ""

# Show current clusters
echo -e "${BLUE}[4/10] Current CAPI clusters:${NC}"
kubectl get clusters -A 2>/dev/null || echo "No clusters found"
echo ""

confirm "Ready to proceed?"

# Disable pruning if migration needed
if [ "$NEEDS_MIGRATION" = true ]; then
    echo -e "${BLUE}[5/10] Disabling pruning on Kustomization...${NC}"
    kubectl patch kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" \
        --type=merge -p '{"spec":{"prune":false}}'
    echo -e "${GREEN}✓ Pruning disabled${NC}"
else
    echo -e "${BLUE}[5/10] Skipping - no existing kustomization${NC}"
fi
echo ""

# Git push
echo -e "${BLUE}[6/10] Push changes to Git${NC}"
echo -e "${YELLOW}Pushing changes to Git...${NC}"
cd "$REPO_ROOT"
git add -A
git status
echo ""
confirm "Review the changes above. Press Enter to commit and push, or Ctrl+C to abort..."

git commit -m "Restructure: separate management-cluster and workload-clusters" || echo "Nothing to commit"
git push
echo -e "${GREEN}✓ Pushed to Git${NC}"
echo ""

# Apply new bootstrap
echo -e "${BLUE}[7/10] Applying new management cluster bootstrap...${NC}"
export KUBECONFIG="$MGMT_KUBECONFIG"
kubectl apply -f "$NEW_BOOTSTRAP_PATH"
echo -e "${GREEN}✓ Management cluster bootstrap applied${NC}"
echo ""

# Trigger reconciliation
echo -e "${BLUE}[8/10] Triggering Flux reconciliation...${NC}"
if command_exists flux; then
    flux reconcile source git "$GITREPO_NAME" -n "$KUSTOMIZATION_NAMESPACE" || true
    sleep 5
    flux reconcile kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" || true
else
    kubectl annotate gitrepository "$GITREPO_NAME" -n "$KUSTOMIZATION_NAMESPACE" \
        reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite 2>/dev/null || true
    sleep 5
    kubectl annotate kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" \
        reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite 2>/dev/null || true
fi
echo -e "${GREEN}✓ Reconciliation triggered${NC}"
echo ""

echo "Waiting 30 seconds for reconciliation..."
sleep 30

# Verify management cluster
echo -e "${BLUE}Verification - Management Cluster:${NC}"
kubectl get kustomizations -n dm-nkp-gitops 2>/dev/null || true
kubectl get clusters -A 2>/dev/null || echo "No clusters found"
echo ""

# Re-enable pruning
if [ "$NEEDS_MIGRATION" = true ]; then
    echo -e "${YELLOW}Re-enabling pruning...${NC}"
    kubectl patch kustomization "$KUSTOMIZATION_NAME" -n "$KUSTOMIZATION_NAMESPACE" \
        --type=merge -p '{"spec":{"prune":true}}'
    echo -e "${GREEN}✓ Pruning re-enabled${NC}"
fi
echo ""

# Bootstrap workload clusters
echo -e "${BLUE}[9/10] Bootstrapping Workload Cluster 1...${NC}"
if [ -f "$WORKLOAD1_KUBECONFIG" ]; then
    export KUBECONFIG="$WORKLOAD1_KUBECONFIG"
    if kubectl cluster-info >/dev/null 2>&1; then
        echo "Connected to dm-nkp-workload-1"
        kubectl apply -f "$WORKLOAD1_BOOTSTRAP"
        echo -e "${GREEN}✓ dm-nkp-workload-1 bootstrap applied${NC}"
    else
        echo -e "${YELLOW}Cannot connect to dm-nkp-workload-1 - skipping${NC}"
    fi
else
    echo -e "${YELLOW}Kubeconfig not found for dm-nkp-workload-1 - skipping${NC}"
fi
echo ""

echo -e "${BLUE}[10/10] Bootstrapping Workload Cluster 2...${NC}"
if [ -f "$WORKLOAD2_KUBECONFIG" ]; then
    export KUBECONFIG="$WORKLOAD2_KUBECONFIG"
    if kubectl cluster-info >/dev/null 2>&1; then
        echo "Connected to dm-nkp-workload-2"
        kubectl apply -f "$WORKLOAD2_BOOTSTRAP"
        echo -e "${GREEN}✓ dm-nkp-workload-2 bootstrap applied${NC}"
    else
        echo -e "${YELLOW}Cannot connect to dm-nkp-workload-2 - skipping${NC}"
    fi
else
    echo -e "${YELLOW}Kubeconfig not found for dm-nkp-workload-2 - skipping${NC}"
fi
echo ""

# Final verification
echo -e "${BLUE}Final Verification:${NC}"
echo ""

echo "Workload Cluster 1 Flux resources:"
if [ -f "$WORKLOAD1_KUBECONFIG" ]; then
    export KUBECONFIG="$WORKLOAD1_KUBECONFIG"
    kubectl get gitrepository,kustomization -n dm-nkp-gitops-workload 2>/dev/null || echo "  Not ready yet or cannot connect"
fi
echo ""

echo "Workload Cluster 2 Flux resources:"
if [ -f "$WORKLOAD2_KUBECONFIG" ]; then
    export KUBECONFIG="$WORKLOAD2_KUBECONFIG"
    kubectl get gitrepository,kustomization -n dm-nkp-gitops-workload 2>/dev/null || echo "  Not ready yet or cannot connect"
fi
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Migration Complete!                                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  ✓ Management cluster migrated to new path"
echo "  ✓ Workload clusters bootstrapped (if accessible)"
echo ""
echo "Next steps:"
echo "  1. Verify management cluster: KUBECONFIG=$MGMT_KUBECONFIG kubectl get kustomizations -A"
echo "  2. Verify workload cluster 1: KUBECONFIG=$WORKLOAD1_KUBECONFIG kubectl get kustomization -n dm-nkp-gitops-workload"
echo "  3. Verify workload cluster 2: KUBECONFIG=$WORKLOAD2_KUBECONFIG kubectl get kustomization -n dm-nkp-gitops-workload"
echo ""
