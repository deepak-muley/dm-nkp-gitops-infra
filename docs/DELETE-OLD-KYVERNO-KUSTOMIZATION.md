# Delete Old Kyverno Kustomization

## Issue

There is an old `kyverno-policies` Flux Kustomization in the `kommander-flux` namespace that was created before we moved Kyverno policies to the `dm-nkp-gitops-infra` namespace.

## Solution

Delete the old kustomization manually:

```bash
kubectl delete kustomization kyverno-policies -n kommander-flux
```

## Current Configuration

The correct Kyverno policies kustomization is now:

- **Name**: `clusterops-kyverno-policies`
- **Namespace**: `dm-nkp-gitops-infra`
- **Location**: `region-usa/az1/management-cluster/global/policies/flux-ks-kyverno.yaml`

## Verification

After deleting the old kustomization, verify only the correct one exists:

```bash
# Should show only clusterops-kyverno-policies in dm-nkp-gitops-infra
kubectl get kustomization -A | grep kyverno

# Old one should be gone
kubectl get kustomization kyverno-policies -n kommander-flux  # Should return "not found"
```

