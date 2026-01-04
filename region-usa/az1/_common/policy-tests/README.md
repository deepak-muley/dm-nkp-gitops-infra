# Policy Tests

This directory contains comprehensive test resources for validating that security policies are active and properly enforced. The tests are organized into **positive (compliant)** and **negative (violations)** examples.

**📚 Learning Resources:**
- See [`KUBESEC-BEST-PRACTICES.md`](KUBESEC-BEST-PRACTICES.md) for detailed explanations of security best practices, including why high UID/GID (>10000) is recommended, why `hostUsers: false` improves security, and the rationale behind other KubeSec recommendations.

## Structure

```
policy-tests/
├── namespace-compliant.yaml          # policy-tests-compliant namespace
├── namespace-violations.yaml         # policy-tests-violations namespace
├── kustomization.yaml                # Main kustomization
├── README.md                         # This file
├── compliant/                        # ✅ Positive tests (policy-compliant resources)
│   ├── kustomization.yaml
│   ├── compliant-example.yaml        # Comprehensive compliant example
│   └── README.md
├── violations/                       # ❌ Negative tests (policy violations)
│   └── kustomization.yaml            # References category subdirectories
├── pod-security/                     # Pod security violation tests
│   ├── kustomization.yaml
│   ├── README.md
│   └── test-*.yaml
├── rbac/                             # RBAC violation tests
│   ├── kustomization.yaml
│   ├── README.md
│   └── test-*.yaml
├── image-security/                   # Image security violation tests
│   ├── kustomization.yaml
│   ├── README.md
│   └── test-*.yaml
├── network-security/                 # Network security violation tests
│   ├── kustomization.yaml
│   ├── README.md
│   └── test-*.yaml
└── resource-management/              # Resource management violation tests
    ├── kustomization.yaml
    ├── README.md
    └── test-*.yaml
```

## Namespaces

- **`policy-tests-compliant`**: Contains resources that **comply** with all policies (positive tests)
- **`policy-tests-violations`**: Contains resources that **violate** policies (negative tests)

## Usage

### Apply All Tests (Compliant + Violations)

```bash
# Apply all policy tests (both compliant and violations)
kubectl apply -k region-usa/az1/_common/policy-tests/

# Or from the repository root
kubectl apply -k ./region-usa/az1/_common/policy-tests/
```

### Apply Only Compliant Examples

```bash
# Apply only compliant (positive) examples
kubectl apply -k region-usa/az1/_common/policy-tests/compliant/

# Verify no violations in compliant namespace
kubectl get policyreport -n policy-tests-compliant
```

### Apply Only Violation Tests

```bash
# Apply only violation (negative) tests
kubectl apply -k region-usa/az1/_common/policy-tests/violations/

# Verify violations are detected
kubectl get policyreport -n policy-tests-violations
```

### Verify Policy Violations

#### Gatekeeper Policies

```bash
# List all constraint violations
kubectl get constraints -A

# Check specific constraint
kubectl get k8srequirerunasnonroot.constraints.gatekeeper.sh require-run-as-nonroot -o yaml

# Check constraint status (shows violations)
kubectl describe k8srequirerunasnonroot require-run-as-nonroot

# Check violations in violations namespace
kubectl get constraints -A | grep policy-tests-violations
```

#### Kyverno Policies

```bash
# List all policies
kubectl get clusterpolicy

# Check policy status (shows violations)
kubectl get clusterpolicy require-run-as-nonroot -o yaml

# View policy reports for violations
kubectl get policyreport -n policy-tests-violations
kubectl get clusterpolicyreport

# View policy reports for compliant examples (should show no violations)
kubectl get policyreport -n policy-tests-compliant
```

### Clean Up Tests

```bash
# Delete all test resources
kubectl delete -k region-usa/az1/_common/policy-tests/

# Delete only compliant tests
kubectl delete -k region-usa/az1/_common/policy-tests/compliant/

# Delete only violation tests
kubectl delete -k region-usa/az1/_common/policy-tests/violations/

# Or delete namespaces directly
kubectl delete namespace policy-tests-compliant
kubectl delete namespace policy-tests-violations
```

## Test Types

### ✅ Compliant Tests (Positive Examples)

The `compliant/` directory contains a comprehensive example demonstrating all best practices. This serves as a reference template for creating policy-compliant workloads.

See [`compliant/README.md`](compliant/README.md) for details.

### ❌ Violation Tests (Negative Examples)

The violation tests are organized by policy category and intentionally violate specific policies to ensure they are being detected.

## Violation Test Categories

### Pod Security Tests (10 tests)

Tests for Pod Security Standards (PSS) policies:

| Test File | Policy Tested | Expected Violation |
|-----------|---------------|-------------------|
| `test-block-privileged-container.yaml` | `block-privileged-container` | Container with privileged: true |
| `test-block-host-namespace.yaml` | `block-host-namespace` | Pod using hostPID/hostIPC/hostNetwork |
| `test-disallowed-capabilities.yaml` | `disallowed-capabilities` | Container with dangerous capabilities |
| `test-restrict-hostpath.yaml` | `restrict-hostpath` | Pod using hostPath volumes |
| `test-block-privilege-escalation.yaml` | `block-privilege-escalation` | Container with allowPrivilegeEscalation: true |
| `test-require-run-as-nonroot.yaml` | `require-run-as-nonroot` | Pod running as root (UID 0) |
| `test-drop-all-capabilities.yaml` | `drop-all-capabilities` | Container not dropping all capabilities |
| `test-restrict-seccomp.yaml` | `restrict-seccomp` | Pod without seccomp profile |
| `test-restrict-volume-types.yaml` | `restrict-volume-types` | Pod using restricted volume types |
| `test-require-readonly-rootfs.yaml` | `require-readonly-rootfs` | Pod without read-only root filesystem |

**Namespace**: `policy-tests-violations`

### RBAC Tests (5 tests)

Tests for RBAC and ServiceAccount policies:

| Test File | Policy Tested | Expected Violation |
|-----------|---------------|-------------------|
| `test-block-cluster-admin.yaml` | `block-cluster-admin` | ClusterRoleBinding to cluster-admin |
| `test-block-wildcard-rbac.yaml` | `block-wildcard-rbac` | RBAC rules using wildcard (*) |
| `test-block-default-sa.yaml` | `block-default-sa` | Pod using default ServiceAccount |
| `test-automount-sa-token.yaml` | `block-automount-sa-token` | Pod with default service account token automount |
| `test-restrict-secrets-access.yaml` | `restrict-secrets-access` | RBAC allowing broad secrets access |

**Namespace**: `policy-tests-violations`

### Image Security Tests (4 tests)

Tests for container image security policies:

| Test File | Policy Tested | Expected Violation |
|-----------|---------------|-------------------|
| `test-allowed-repos.yaml` | `allowed-repos` | Image from disallowed registry |
| `test-block-latest-tag.yaml` | `block-latest-tag` | Image using :latest tag |
| `test-require-image-digest.yaml` | `require-image-digest` | Image using tag instead of digest |
| `test-disallow-image-pull-policy-always.yaml` | `disallow-image-pull-policy-always` | Container with imagePullPolicy: Always |

**Namespace**: `policy-tests-violations`

### Network Security Tests (5 tests)

Tests for network security policies:

| Test File | Policy Tested | Expected Violation |
|-----------|---------------|-------------------|
| `test-block-nodeport.yaml` | `block-nodeport` | Service with type: NodePort |
| `test-block-loadbalancer.yaml` | `block-loadbalancer` | Service with type: LoadBalancer |
| `test-block-host-ports.yaml` | `block-host-ports` | Pod using hostPort |
| `test-require-ingress-tls.yaml` | `require-ingress-tls` | Ingress without TLS configuration |
| `test-restrict-external-ips.yaml` | `restrict-external-ips` | Service with externalIPs |

**Namespace**: `policy-tests-violations`

### Resource Management Tests (4 tests)

Tests for resource management policies:

| Test File | Policy Tested | Expected Violation |
|-----------|---------------|-------------------|
| `test-required-resources.yaml` | `required-resources` | Container without resource requests/limits |
| `test-required-labels.yaml` | `required-labels` | Resource missing required labels |
| `test-container-limits.yaml` | `container-limits` | Container exceeding maximum limits |
| `test-required-probes.yaml` | `required-probes` | Container without health probes |

**Namespace**: `policy-tests-violations`

## Adding New Tests

When adding a new policy, follow these steps:

### 1. Identify Policy Location

Find the policy in `_common/policies/`:
- **Gatekeeper**: `_common/policies/gatekeeper/constraints/{category}/{policy-name}.yaml`
- **Kyverno**: `_common/policies/kyverno/{category}/{policy-name}.yaml`

### 2. Create Test File

Create a test file in the corresponding category directory:

```bash
# Example: Adding test for block-privileged-container policy
# Location: _common/policy-tests/pod-security/test-block-privileged-container.yaml
```

### 3. Test File Template

Use this template for test files:

```yaml
# Test: {Policy Name} Policy Violation
# Policy: {policy-name} (Gatekeeper & Kyverno)
#
# This test resource violates the policy by {description of violation}.
# Expected behavior:
#   - Gatekeeper: Should create violation (if enforcementAction: deny, will block)
#   - Kyverno: Should create violation (if validationFailureAction: Enforce, will block)
#
# To verify violations:
#   Gatekeeper: kubectl get {constraint-kind}.constraints.gatekeeper.sh {constraint-name} -o yaml
#   Kyverno: kubectl get clusterpolicy {policy-name} -o yaml
#
apiVersion: v1
kind: Pod  # or other resource type
metadata:
  name: test-{policy-name}
  namespace: policy-tests-violations
  labels:
    test-policy: {policy-name}
    test-type: violation
spec:
  # ... resource spec that violates the policy ...
```

### 4. Update Kustomization

Add the test file to the category's `kustomization.yaml`:

```yaml
# In _common/policy-tests/{category}/kustomization.yaml
resources:
  - test-{policy-name}.yaml
```

### 5. Update This README

Add the test to the appropriate category table in this README.

## Policy Enforcement Modes

Policies can run in different enforcement modes:

### Gatekeeper Enforcement Actions

- `deny`: Blocks violations (prevents resource creation/update)
- `warn`: Logs violations but allows resource creation
- `dryrun`: Simulates enforcement (logs what would be blocked)

### Kyverno Validation Failure Actions

- `Enforce`: Blocks violations (prevents resource creation/update)
- `Audit`: Logs violations but allows resource creation

**Note**: These tests are designed to create violations. If policies are in `deny`/`Enforce` mode, the test resources will be **blocked** and won't be created. In `warn`/`Audit` mode, resources will be created but violations will be logged.

## Best Practices

1. **One Test Per Policy**: Each policy should have a corresponding test file
2. **Clear Naming**: Use `test-{policy-name}.yaml` naming convention
3. **Documentation**: Include comments explaining what violation is being tested
4. **Isolation**: All tests run in the `policy-tests` namespace
5. **Clean Up**: Remove tests after validation to avoid clutter

## Integration with GitOps

These tests can be deployed via GitOps, but consider:

- **For CI/CD**: Apply tests, verify violations, then clean up
- **For Development**: Keep tests deployed for ongoing validation
- **For Production**: Consider excluding test namespaces from policy enforcement (if needed)

To deploy via GitOps, add to management cluster kustomization:

```yaml
# In management-cluster/kustomization.yaml (if needed)
resources:
  - _common/policy-tests  # Includes both compliant and violations
  # Or separately:
  # - _common/policy-tests/compliant
  # - _common/policy-tests/violations
```

## Test Coverage Summary

This test suite provides comprehensive coverage for validation policies:

### ✅ Compliant Examples
- **1 comprehensive example** demonstrating all best practices (Deployment, Service, Ingress, ServiceAccount)

### ❌ Violation Tests
- **Pod Security**: 10 tests covering PSS Baseline & Restricted policies
- **RBAC**: 5 tests covering RBAC and ServiceAccount policies
- **Image Security**: 4 tests covering container image policies
- **Network Security**: 5 tests covering network exposure policies
- **Resource Management**: 4 tests covering resource limits and labels

**Total**: 1 compliant example + 28 violation test resources covering major validation policies.

**Note**: Mutation policies (e.g., `add-default-securitycontext`) don't need violation tests as they modify resources rather than validate them. Some advanced policies (supply-chain, multi-tenancy) may require environment-specific configuration and are not included in this basic test suite.

## Troubleshooting

### Tests Not Creating Violations

1. **Check policy is active**:
   ```bash
   kubectl get clusterpolicy
   kubectl get constraints
   ```

2. **Check namespace exclusions**: Verify `policy-tests` is not in `excludedNamespaces`

3. **Check policy enforcement mode**: Verify policies are not disabled

4. **Check resource actually violates policy**: Review test resource spec

### Resources Blocked When They Shouldn't Be

- If tests are blocked and you expect them to create (in audit mode):
  - Check if policy is in `deny`/`Enforce` mode
  - Check namespace exclusions
  - Verify test resource correctly violates the policy

## Related Documentation

- Policy documentation: `_common/policies/README.md`
- Gatekeeper policies: `_common/policies/gatekeeper/README.md`
- Kyverno policies: `_common/policies/kyverno/README.md`

