# Compliant Policy Tests

This directory contains **positive tests** - resources that **comply** with all security policies. These serve as reference examples for creating policy-compliant workloads.

**📚 Learning Resources:**
- See [`../KUBESEC-BEST-PRACTICES.md`](../KUBESEC-BEST-PRACTICES.md) for detailed explanations of why each security practice matters, including the security rationale behind high UID/GID (>10000), `hostUsers: false`, and other KubeSec recommendations.

## Namespace

All compliant tests run in the `policy-tests-compliant` namespace.

## Compliant Example

The `compliant-example.yaml` file contains a comprehensive, production-ready example that demonstrates:

### ✅ Pod Security Policies
- ✅ Non-root user (`runAsNonRoot: true`, `runAsUser: 10001` - high UID)
- ✅ High UID/GID (>10000) to avoid conflicts with host users/groups
- ✅ Read-only root filesystem (`readOnlyRootFilesystem: true`) with writable volumes
- ✅ No privilege escalation (`allowPrivilegeEscalation: false`)
- ✅ All capabilities dropped (`capabilities.drop: ["ALL"]`)
- ✅ Seccomp profile (`seccompProfile.type: RuntimeDefault`)
- ✅ Note: `hostUsers: false` recommended for Kubernetes 1.25+ (commented out due to schema compatibility)

### ✅ Image Security Policies
- ✅ Image digest (required by `require-image-digest` policy)
- ✅ Image pull policy set to `IfNotPresent` (not `Always`)

### ✅ RBAC Policies
- ✅ Non-default ServiceAccount
- ✅ Service account token automount disabled (`automountServiceAccountToken: false`)

### ✅ Network Security Policies
- ✅ ClusterIP service (not NodePort or LoadBalancer)
- ✅ Ingress with TLS configuration

### ✅ Resource Management Policies
- ✅ Resource requests and limits specified
- ✅ Standard Kubernetes labels (`app.kubernetes.io/*`)
- ✅ Liveness and readiness probes configured

## Usage

### Apply Compliant Example

```bash
# Apply the compliant example
kubectl apply -k region-usa/az1/_common/policy-tests/compliant/

# Verify no violations
kubectl get policyreport -n policy-tests-compliant
kubectl get clusterpolicyreport | grep policy-tests-compliant
```

### Verify Compliance

```bash
# Check for any policy violations
kubectl get policyreport -n policy-tests-compliant -o yaml

# Gatekeeper constraints (should show no violations)
kubectl get constraints -A
kubectl describe k8srequirerunasnonroot require-run-as-nonroot | grep policy-tests-compliant

# Kyverno policies (should show no violations)
kubectl get clusterpolicy require-run-as-nonroot -o yaml | grep policy-tests-compliant
```

### Clean Up

```bash
# Delete compliant tests
kubectl delete -k region-usa/az1/_common/policy-tests/compliant/

# Or delete namespace
kubectl delete namespace policy-tests-compliant
```

## Reference Guide

Use this compliant example as a template when creating new workloads. Key patterns:

1. **Always set security context** at both pod and container level
2. **Use read-only root filesystem** with emptyDir volumes for writable paths
3. **Specify resource requests and limits** for all containers
4. **Add health probes** for better observability
5. **Use standard labels** (`app.kubernetes.io/*`)
6. **Create dedicated ServiceAccounts** instead of using default
7. **Disable service account token automount** if not needed
8. **Use specific image tags** (avoid `:latest`)
9. **Use ClusterIP services** with Ingress for external access
10. **Configure TLS** for Ingress resources

## Integration

This compliant example is designed to work alongside the violation tests in `policy-tests-violations/` namespace. Together, they provide:

- **Positive examples** (this directory): What TO do
- **Negative examples** (violations directory): What NOT to do

This helps developers understand both sides of policy compliance.

