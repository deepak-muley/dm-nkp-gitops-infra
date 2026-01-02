#!/bin/bash
# Script to manually create clusterops-kyverno-policies kustomization
# This is a workaround if clusterops-global isn't creating it automatically

set -e

echo "=== Creating clusterops-kyverno-policies kustomization ==="

# Check if namespace exists
if ! kubectl get namespace dm-nkp-gitops-infra &>/dev/null; then
  echo "ERROR: Namespace dm-nkp-gitops-infra does not exist"
  echo "Creating namespace..."
  kubectl create namespace dm-nkp-gitops-infra
fi

# Check if GitRepository exists
if ! kubectl get gitrepository gitops-usa-az1 -n kommander &>/dev/null; then
  echo "ERROR: GitRepository gitops-usa-az1 does not exist in kommander namespace"
  exit 1
fi

# Create the kustomization manually
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-kyverno-policies
  namespace: dm-nkp-gitops-infra
spec:
  interval: 5m
  path: ./region-usa/az1/_common/policies/kyverno
  prune: true
  sourceRef:
    kind: GitRepository
    name: gitops-usa-az1
    namespace: kommander
  timeout: 2m
EOF

echo ""
echo "=== Verifying creation ==="
kubectl get kustomization clusterops-kyverno-policies -n dm-nkp-gitops-infra

echo ""
echo "=== Force reconciliation ==="
flux reconcile kustomization clusterops-kyverno-policies -n dm-nkp-gitops-infra

echo ""
echo "=== Status ==="
kubectl get kustomization clusterops-kyverno-policies -n dm-nkp-gitops-infra -o wide

