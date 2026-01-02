#!/bin/bash
# Script to forcefully remove old kyverno-policies kustomization from kommander-flux namespace
# and prevent it from being recreated

set -e

echo "=== Removing old kyverno-policies kustomization from kommander-flux ==="

# 1. Suspend the kustomization first
echo "Step 1: Suspending the kustomization..."
kubectl annotate kustomization kyverno-policies -n kommander-flux \
  kustomize.toolkit.fluxcd.io/reconcile=disabled \
  --overwrite 2>/dev/null || echo "Kustomization may not exist or already suspended"

# 2. Add finalizer to prevent immediate deletion (optional - helps prevent recreation)
echo "Step 2: Adding finalizer to prevent recreation..."
kubectl patch kustomization kyverno-policies -n kommander-flux \
  --type json \
  -p='[{"op": "add", "path": "/metadata/finalizers", "value": ["finalizers.fluxcd.io"]}]' 2>/dev/null || echo "Could not add finalizer (may not exist)"

# 3. Delete the kustomization
echo "Step 3: Deleting the kustomization..."
kubectl delete kustomization kyverno-policies -n kommander-flux --ignore-not-found=true

# 4. Verify deletion
echo "Step 4: Verifying deletion..."
if kubectl get kustomization kyverno-policies -n kommander-flux 2>/dev/null; then
  echo "WARNING: Kustomization still exists. It may be auto-recreated by Kommander."
  echo "You may need to check Kommander settings for GitOps auto-discovery."
else
  echo "SUCCESS: Kustomization removed successfully."
fi

echo ""
echo "=== Next Steps ==="
echo "1. Check if clusterops-kyverno-policies exists in dm-nkp-gitops-infra namespace"
echo "2. If it keeps getting recreated, check Kommander GitOps auto-discovery settings"
echo "3. Monitor with: kubectl get kustomization -A | grep kyverno"

