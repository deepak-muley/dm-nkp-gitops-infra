# Image Security Policy Tests

Tests for image security policies defined in `_common/policies/*/image-security/`.

## Tests

| Test File | Policy | Violation Type | Status |
|-----------|--------|----------------|--------|
| `test-allowed-repos.yaml` | `allowed-repos` / `restrict-image-registries` | Uses image from disallowed registry | ✅ |
| `test-block-latest-tag.yaml` | `block-latest-tag` / `disallow-latest-tag` | Uses :latest tag | ✅ |
| `test-require-image-digest.yaml` | `require-image-digest` | Uses tag instead of digest | ✅ |
| `test-disallow-image-pull-policy-always.yaml` | `disallow-image-pull-policy-always` | Uses imagePullPolicy: Always | ✅ |

## Adding a New Test

1. Create test file: `test-{policy-name}.yaml`
2. Add to `kustomization.yaml`
3. Update this README table
4. Follow template from main README

## Verification Commands

```bash
# Gatekeeper constraints
kubectl get constraints -n policy-tests
kubectl describe k8srequiredlabels allowed-repos

# Kyverno policies
kubectl get clusterpolicy | grep image
kubectl get policyreport -n policy-tests
```

