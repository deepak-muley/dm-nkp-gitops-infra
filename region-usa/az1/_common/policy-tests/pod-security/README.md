# Pod Security Policy Tests

Tests for Pod Security Standards (PSS) policies defined in `_common/policies/*/pod-security/`.

## Tests

| Test File | Policy | Violation Type | Status |
|-----------|--------|----------------|--------|
| `test-block-privileged-container.yaml` | `block-privileged-container` | Privileged: true | ✅ |
| `test-block-host-namespace.yaml` | `block-host-namespace` | hostPID, hostIPC, or hostNetwork: true | ✅ |
| `test-disallowed-capabilities.yaml` | `disallowed-capabilities` | Uses dangerous capabilities (NET_ADMIN, etc.) | ✅ |
| `test-restrict-hostpath.yaml` | `restrict-hostpath` | Uses hostPath volumes | ✅ |
| `test-block-privilege-escalation.yaml` | `block-privilege-escalation` | allowPrivilegeEscalation: true | ✅ |
| `test-require-run-as-nonroot.yaml` | `require-run-as-nonroot` | Runs container as root (UID 0) | ✅ |
| `test-drop-all-capabilities.yaml` | `drop-all-capabilities` | Not dropping all capabilities | ✅ |
| `test-restrict-seccomp.yaml` | `restrict-seccomp` | Missing seccomp profile | ✅ |
| `test-restrict-volume-types.yaml` | `restrict-volume-types` | Uses restricted volume types | ✅ |
| `test-require-readonly-rootfs.yaml` | `require-readonly-rootfs` | Missing readOnlyRootFilesystem: true | ✅ |

## Adding a New Test

1. Create test file: `test-{policy-name}.yaml`
2. Add to `kustomization.yaml`
3. Update this README table
4. Follow template from main README

## Verification Commands

```bash
# Gatekeeper constraints
kubectl get constraints -n policy-tests
kubectl describe k8srequirerunasnonroot require-run-as-nonroot

# Kyverno policies
kubectl get clusterpolicy | grep pod-security
kubectl get policyreport -n policy-tests
```

