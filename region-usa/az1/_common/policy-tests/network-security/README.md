# Network Security Policy Tests

Tests for network security policies defined in `_common/policies/*/network-security/`.

## Tests

| Test File | Policy | Violation Type | Status |
|-----------|--------|----------------|--------|
| `test-block-nodeport.yaml` | `block-nodeport` / `disallow-nodeport-services` | Creates NodePort service | ✅ |
| `test-block-loadbalancer.yaml` | `block-loadbalancer` / `disallow-loadbalancer-services` | Creates LoadBalancer service | ✅ |
| `test-block-host-ports.yaml` | `block-host-ports` / `disallow-host-ports` | Uses hostPort | ✅ |
| `test-require-ingress-tls.yaml` | `require-ingress-tls` | Ingress without TLS | ✅ |
| `test-restrict-external-ips.yaml` | `restrict-external-ips` | Service with externalIPs | ✅ |
| `test-require-network-policy.yaml` | `require-network-policy` | Missing NetworkPolicy | ⏳ TODO |

## Adding a New Test

1. Create test file: `test-{policy-name}.yaml`
2. Add to `kustomization.yaml`
3. Update this README table
4. Follow template from main README

## Verification Commands

```bash
# Gatekeeper constraints
kubectl get constraints -n policy-tests
kubectl describe k8srequiredlabels block-nodeport

# Kyverno policies
kubectl get clusterpolicy | grep network
kubectl get policyreport -n policy-tests
```

