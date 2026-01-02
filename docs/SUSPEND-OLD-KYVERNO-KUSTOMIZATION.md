# Suspend Old Kyverno Kustomization in kommander-flux

## Issue

The `kyverno-policies` Flux Kustomization keeps getting recreated in the `kommander-flux` namespace, even after deletion. This is likely being auto-created by Kommander/NKP when it detects Kyverno policies in the GitOps repository.

## Solution

Permanently suspend the kustomization and add annotations to prevent Kommander from recreating it:

```bash
# 1. Suspend the kustomization
kubectl annotate kustomization kyverno-policies -n kommander-flux \
  kustomize.toolkit.fluxcd.io/reconcile=disabled \
  --overwrite

# 2. Add finalizer to prevent deletion (optional, if you want to keep it but disabled)
# kubectl patch kustomization kyverno-policies -n kommander-flux \
#   --type merge -p '{"metadata":{"finalizers":["finalizers.fluxcd.io"]}}'

# 3. Verify it's suspended
kubectl get kustomization kyverno-policies -n kommander-flux -o yaml | grep -A 2 "suspend\|reconcile"
```

## Alternative: Delete and Prevent Recreation

If you want to completely remove it:

```bash
# 1. Delete the kustomization
kubectl delete kustomization kyverno-policies -n kommander-flux

# 2. If it keeps getting recreated, check what's creating it:
kubectl get kustomization kyverno-policies -n kommander-flux -o yaml | \
  grep -A 10 "ownerReferences\|managedFields"

# 3. If it's being created by Kommander, you may need to:
#    - Check Kommander UI for auto-discovery settings
#    - Check if there's a ClusterApp or App that's creating it
#    - Check Kommander configuration for GitOps auto-discovery
```

## Root Cause

Kommander/NKP may have GitOps auto-discovery enabled that automatically creates Flux Kustomizations when it detects certain resources in the GitOps repository. The `kyverno-policies` kustomization is likely being auto-created because:

1. Kommander detects Kyverno policies in the `_common/policies/kyverno/` directory
2. It automatically creates a Flux Kustomization to manage them
3. It uses the default `kommander-flux` namespace for auto-discovered resources

## Current Configuration

The correct Kyverno policies kustomization is:

- **Name**: `clusterops-kyverno-policies`
- **Namespace**: `dm-nkp-gitops-infra`
- **Location**: `region-usa/az1/management-cluster/global/policies/flux-ks-kyverno.yaml`

## Verification

After suspending, verify:

```bash
# Should show suspended or disabled
kubectl get kustomization kyverno-policies -n kommander-flux

# Check the correct one is working
kubectl get kustomization clusterops-kyverno-policies -n dm-nkp-gitops-infra
```

