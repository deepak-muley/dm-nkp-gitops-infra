#!/bin/bash
# Script to debug who is creating the kyverno-policies kustomization in kommander-flux

set -e

echo "=== Debugging kyverno-policies kustomization creation ==="
echo ""

# 1. Check if kustomization exists
echo "1. Checking if kyverno-policies exists..."
if kubectl get kustomization kyverno-policies -n kommander-flux &>/dev/null; then
  echo "   ✓ Found kyverno-policies kustomization"
else
  echo "   ✗ Not found (may have been deleted)"
  exit 0
fi

echo ""
echo "2. Checking ownerReferences (what created it)..."
kubectl get kustomization kyverno-policies -n kommander-flux -o yaml | \
  grep -A 10 "ownerReferences:" || echo "   No ownerReferences found (created manually or by controller)"

echo ""
echo "3. Checking managedFields (what's managing it)..."
kubectl get kustomization kyverno-policies -n kommander-flux -o yaml | \
  grep -A 5 "managedFields:" | head -20

echo ""
echo "4. Checking annotations and labels..."
kubectl get kustomization kyverno-policies -n kommander-flux -o yaml | \
  grep -A 10 "annotations:\|labels:"

echo ""
echo "5. Checking if there's a Kyverno AppDeployment that might be creating it..."
kubectl get appdeployment -A | grep -i kyverno || echo "   No Kyverno AppDeployments found"

echo ""
echo "6. Checking if there's a ClusterApp for Kyverno..."
kubectl get clusterapp -A | grep -i kyverno || echo "   No Kyverno ClusterApps found"

echo ""
echo "7. Checking Kommander GitOps settings (if accessible)..."
kubectl get gitrepository -A | grep -E "kyverno|kommander" || echo "   No related GitRepositories found"

echo ""
echo "8. Checking for any Flux controllers that might auto-discover..."
kubectl get deployment -n kommander-flux | grep -E "kustomize|source" || echo "   No Flux controllers found in kommander-flux"

echo ""
echo "9. Checking recent events for kyverno-policies..."
kubectl get events -n kommander-flux --sort-by='.lastTimestamp' | \
  grep -i "kyverno-policies" | tail -10 || echo "   No recent events found"

echo ""
echo "10. Checking Kyverno AppDeployment in kommander workspace..."
kubectl get appdeployment kyverno -n kommander -o yaml 2>/dev/null | \
  grep -A 10 "spec:\|annotations:" | head -15 || echo "   No Kyverno AppDeployment in kommander namespace"

echo ""
echo "11. Checking for any Kommander operators or controllers..."
kubectl get deployment -n kommander | grep -E "kommander|gitops|flux" || echo "   No obvious Kommander operators found"

echo ""
echo "12. Checking for admission webhooks that might create kustomizations..."
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | \
  grep -i "kommander\|gitops\|flux" || echo "   No related webhooks found"

echo ""
echo "13. Full kustomization YAML (check for clues)..."
echo "    Run: kubectl get kustomization kyverno-policies -n kommander-flux -o yaml"
echo ""
echo "=== Analysis ==="
echo "The most likely culprits are:"
echo "1. Kommander GitOps auto-discovery (scans repo and auto-creates kustomizations)"
echo "2. Kyverno AppDeployment creating a kustomization for policies"
echo "3. A Kommander operator/controller watching for Kyverno resources"
echo ""
echo "=== Next Steps ==="
echo "1. Check managedFields to see which controller is managing it (most important!)"
echo "2. Check Kommander UI for GitOps auto-discovery settings"
echo "3. Check if there's a KommanderConfig or similar CR that enables auto-discovery"
echo "4. Check Kyverno App/ClusterApp for any GitOps integration"
echo "5. Look for any Kommander operators in kommander namespace"

