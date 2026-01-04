# RBAC Policy Tests

Tests for RBAC and ServiceAccount policies defined in `_common/policies/*/rbac/`.

## Tests

| Test File | Policy | Violation Type | Status |
|-----------|--------|----------------|--------|
| `test-block-cluster-admin.yaml` | `block-cluster-admin` / `disallow-cluster-admin` | Binds cluster-admin role | ✅ |
| `test-block-wildcard-rbac.yaml` | `block-wildcard-rbac` / `disallow-wildcard-rbac` | Uses wildcard (*) in RBAC rules | ✅ |
| `test-block-default-sa.yaml` | `block-default-sa` / `disallow-default-serviceaccount` | Uses default ServiceAccount | ✅ |
| `test-automount-sa-token.yaml` | `block-automount-sa-token` / `require-sa-token-automount-disabled` | Missing automountServiceAccountToken: false | ✅ |
| `test-restrict-secrets-access.yaml` | `restrict-secrets-access` | Broad secrets access in RBAC | ✅ |

## Adding a New Test

1. Create test file: `test-{policy-name}.yaml`
2. Add to `kustomization.yaml`
3. Update this README table
4. Follow template from main README

## Verification Commands

```bash
# Gatekeeper constraints
kubectl get constraints -n policy-tests
kubectl describe k8sblockautomountsatoken require-explicit-automount

# Kyverno policies
kubectl get clusterpolicy | grep rbac
kubectl get policyreport -n policy-tests
```

