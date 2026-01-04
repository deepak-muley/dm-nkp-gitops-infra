# Resource Management Policy Tests

Tests for resource management policies defined in `_common/policies/*/resource-management/`.

## Tests

| Test File | Policy | Violation Type | Status |
|-----------|--------|----------------|--------|
| `test-required-resources.yaml` | `required-resources` / `require-requests-limits` | Missing resource requests/limits | ✅ |
| `test-required-labels.yaml` | `required-labels` / `require-standard-labels` | Missing required labels | ✅ |
| `test-container-limits.yaml` | `container-limits` / `enforce-max-container-limits` | Exceeds maximum limits | ✅ |
| `test-required-probes.yaml` | `required-probes` / `require-health-probes` | Missing liveness/readiness probes | ✅ |
| `test-require-pod-disruption-budget.yaml` | `require-pod-disruption-budget` | Missing PDB | ⏳ TODO |

## Adding a New Test

1. Create test file: `test-{policy-name}.yaml`
2. Add to `kustomization.yaml`
3. Update this README table
4. Follow template from main README

## Verification Commands

```bash
# Gatekeeper constraints
kubectl get constraints -n policy-tests
kubectl describe k8srequiredlabels required-resources

# Kyverno policies
kubectl get clusterpolicy | grep resource
kubectl get policyreport -n policy-tests
```

