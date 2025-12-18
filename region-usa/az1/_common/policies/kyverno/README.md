# Kyverno Security Policies

This directory contains comprehensive Kyverno policies for enforcing security standards across the Kubernetes cluster.

**Reference**: [Kyverno Policy Library](https://kyverno.io/policies/) | [GitHub](https://github.com/kyverno/kyverno)

## Policy Summary

| Category | Policies | Description |
|----------|----------|-------------|
| **Pod Security** | 13 | PSS Baseline & Restricted controls |
| **Image Security** | 4 | Registry whitelist, tag validation |
| **Resource Management** | 5 | Requests/limits, labels, probes |
| **Network Security** | 6 | Service types, TLS, NetworkPolicy |
| **RBAC** | 5 | Cluster-admin, wildcards, ServiceAccounts |
| **Supply Chain** | 1 | Image signature verification |
| **Multi-Tenancy** | 3 | Quotas, namespaces, priority |
| **Best Practices** | 5 | HA, anti-affinity, deployment strategy |
| **Mutations** | 3 | Auto-inject secure defaults |
| **Total** | **45** | Comprehensive security coverage |

## Directory Structure

```
kyverno/
├── kustomization.yaml              # Main kustomization
├── README.md                       # This file
├── pod-security/                   # Pod Security Standards (13 policies)
│   ├── block-privileged-container.yaml
│   ├── block-privilege-escalation.yaml
│   ├── require-run-as-nonroot.yaml
│   ├── block-host-namespace.yaml
│   ├── disallowed-capabilities.yaml
│   ├── drop-all-capabilities.yaml
│   ├── require-readonly-rootfs.yaml
│   ├── restrict-seccomp.yaml
│   ├── restrict-hostpath.yaml      # NEW
│   ├── restrict-proc-mount.yaml    # NEW
│   ├── restrict-sysctls.yaml       # NEW
│   ├── restrict-volume-types.yaml  # NEW
│   └── kustomization.yaml
├── image-security/                 # Container image policies (4 policies)
│   ├── allowed-repos.yaml
│   ├── block-latest-tag.yaml
│   ├── require-image-digest.yaml
│   ├── disallow-image-pull-policy-always.yaml
│   └── kustomization.yaml
├── resource-management/            # Resource limits/labels (5 policies)
│   ├── required-resources.yaml
│   ├── container-limits.yaml
│   ├── required-labels.yaml
│   ├── required-probes.yaml
│   ├── require-pod-disruption-budget.yaml
│   └── kustomization.yaml
├── network-security/               # Network exposure (6 policies)
│   ├── block-nodeport.yaml
│   ├── block-loadbalancer.yaml
│   ├── block-host-ports.yaml
│   ├── require-ingress-tls.yaml
│   ├── require-network-policy.yaml
│   ├── restrict-external-ips.yaml
│   └── kustomization.yaml
├── rbac/                           # RBAC & ServiceAccount (5 policies)
│   ├── block-cluster-admin.yaml
│   ├── block-default-sa.yaml
│   ├── block-wildcard-rbac.yaml
│   ├── block-automount-sa-token.yaml
│   ├── restrict-secrets-access.yaml
│   └── kustomization.yaml
├── supply-chain/                   # Supply Chain Security (1 policy) NEW
│   ├── verify-image-signatures.yaml
│   └── kustomization.yaml
├── multi-tenancy/                  # Multi-Tenancy (3 policies) NEW
│   ├── require-resourcequota.yaml
│   ├── require-pod-priorityclass.yaml
│   ├── restrict-namespace-creation.yaml
│   └── kustomization.yaml
├── best-practices/                 # Best Practices (5 policies) NEW
│   ├── require-minimum-replicas.yaml
│   ├── require-pod-antiaffinity.yaml
│   ├── require-deployment-strategy.yaml
│   ├── disallow-empty-ingress-host.yaml
│   ├── add-safe-to-evict.yaml
│   └── kustomization.yaml
└── mutations/                      # Mutation Policies (3 policies) NEW
    ├── add-default-securitycontext.yaml
    ├── add-imagepullsecrets.yaml
    ├── add-default-tolerations.yaml
    └── kustomization.yaml
```

## Policy Categories

### 🔒 Pod Security (13 policies - PSS Baseline & Restricted)

| Policy | Description | Severity | PSS Level |
|--------|-------------|----------|-----------|
| `disallow-privileged-containers` | Blocks privileged mode | 🔴 Critical | Baseline |
| `disallow-host-namespaces` | Blocks host PID/IPC/Network | 🔴 Critical | Baseline |
| `disallow-capabilities` | Blocks dangerous capabilities | 🔴 Critical | Baseline |
| `disallow-host-path` | Blocks hostPath volumes | 🔴 Critical | Baseline |
| `disallow-privilege-escalation` | Prevents privilege escalation | 🟠 High | Restricted |
| `require-run-as-nonroot` | Requires non-root user | 🟠 High | Restricted |
| `require-drop-all-capabilities` | Requires dropping ALL caps | 🟠 High | Restricted |
| `restrict-seccomp-strict` | Requires seccomp profiles | 🟠 High | Restricted |
| `restrict-proc-mount` | Restricts /proc mount type | 🟠 High | Baseline |
| `restrict-sysctls` | Blocks unsafe sysctls | 🟠 High | Baseline |
| `require-readonly-root-filesystem` | Requires read-only rootfs | 🟡 Medium | Best Practice |
| `restrict-volume-types` | Limits volume types | 🟡 Medium | Restricted |

### 🖼️ Image Security (4 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `restrict-image-registries` | Whitelist of allowed registries | 🔴 Critical |
| `disallow-latest-tag` | Blocks `:latest` tag usage | 🟠 High |
| `validate-image-pull-policy` | Validates pull policy | 🟡 Medium |
| `require-image-digest` | Requires image digests | 🟡 Medium |

### 📋 Resource Management (5 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `require-requests-limits` | Requires CPU/memory limits | 🔴 Critical |
| `require-labels` | Requires standard K8s labels | 🟠 High |
| `restrict-container-resources` | Enforces max resource limits | 🟡 Medium |
| `require-probes` | Requires liveness/readiness | 🟡 Medium |
| `require-pdb` | Requires PodDisruptionBudget | 🟡 Medium |

### 🌐 Network Security (6 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `disallow-host-ports` | Blocks host port bindings | 🟠 High |
| `require-ingress-tls` | Requires TLS on Ingress | 🟠 High |
| `require-networkpolicy` | Generates default NetworkPolicies | 🟠 High |
| `restrict-external-ips` | Blocks external IPs on Services | 🟠 High |
| `disallow-nodeport-services` | Blocks NodePort services | 🟡 Medium |
| `disallow-loadbalancer-services` | Blocks LoadBalancer services | 🟡 Medium |

### 🔐 RBAC Security (5 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `restrict-clusterrole-binding` | Restricts cluster-admin bindings | 🔴 Critical |
| `disallow-wildcards-in-roles` | Blocks wildcard (*) in RBAC | 🔴 Critical |
| `disallow-default-serviceaccount` | Blocks use of default SA | 🟠 High |
| `restrict-secrets-role` | Restricts secrets access | 🟠 High |
| `require-sa-token-automount-disabled` | Requires explicit SA token | 🟡 Medium |

### 🔗 Supply Chain Security (1 policy)

| Policy | Description | Severity |
|--------|-------------|----------|
| `verify-image-signatures` | Verifies Sigstore/cosign signatures | 🔴 Critical |

> **Note**: Requires configuration with your signing keys/keyless setup.

### 👥 Multi-Tenancy (3 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `require-resourcequota` | Generates ResourceQuota for namespaces | 🟠 High |
| `restrict-namespace-creation` | Controls namespace creation | 🟠 High |
| `require-pod-priorityclass` | Requires priority class | 🟡 Medium |

### ✅ Best Practices (5 policies)

| Policy | Description | Severity |
|--------|-------------|----------|
| `require-minimum-replicas` | Requires 2+ replicas in prod | 🟠 High |
| `require-pod-antiaffinity` | Spreads pods across nodes | 🟡 Medium |
| `require-deployment-strategy` | Requires RollingUpdate | 🟡 Medium |
| `disallow-empty-ingress-host` | Prevents catch-all ingress | 🟡 Medium |
| `add-safe-to-evict` | Adds safe-to-evict annotation | 🟢 Low |

### 🔄 Mutation Policies (3 policies)

| Policy | Description | Effect |
|--------|-------------|--------|
| `add-default-securitycontext` | Injects secure defaults | Adds runAsNonRoot, seccomp, caps |
| `add-imagepullsecrets` | Auto-adds pull secrets | Adds imagePullSecrets for private registries |
| `add-default-tolerations` | Adds resilience tolerations | Handles node not-ready/unreachable |

## Enforcement Actions

| Mode | Description | Use Case |
|------|-------------|----------|
| `Enforce` | Blocks non-compliant resources | Production enforcement |
| `Audit` | Allows but logs violations | Rollout/testing phase |

**Current Configuration**: All policies are set to `Audit` mode for safe rollout.

## Rollout Strategy

### Phase 1: Assessment (Current)
1. ✅ Deploy all policies with `validationFailureAction: Audit`
2. Review violations: `kubectl get policyreport -A`
3. Identify legitimate issues vs. expected exceptions

### Phase 2: Tune Policies
1. Add namespace exclusions for platform components
2. Update allowed registries for your environment
3. Adjust resource limits based on workloads

### Phase 3: Enforcement
1. Change critical policies from `Audit` to `Enforce`
2. Monitor with: `kubectl get clusterpolicyreport`
3. Iterate on exceptions

## Monitoring

### Check Policy Status
```bash
kubectl get clusterpolicy
kubectl get policy -A
```

### View Violations (PolicyReport)
```bash
# Cluster-level report
kubectl get clusterpolicyreport -o yaml

# Namespace-level reports
kubectl get policyreport -A

# Summary view
kubectl get policyreport -A -o custom-columns='NAMESPACE:.metadata.namespace,PASS:.summary.pass,FAIL:.summary.fail,WARN:.summary.warn'
```

### Use the violations script
```bash
# Check Kyverno violations
./scripts/check-violations.sh -e kyverno mgmt

# Check specific namespace
./scripts/check-violations.sh -e kyverno -n kommander mgmt
```

## Customization

### Adding Namespace Exclusions
```yaml
spec:
  rules:
    - name: rule-name
      exclude:
        any:
          - resources:
              namespaces:
                - your-exception-namespace
```

### Changing to Enforce Mode
```yaml
spec:
  validationFailureAction: Enforce  # Changed from Audit
```

### Configuring Image Signature Verification
Edit `supply-chain/verify-image-signatures.yaml` and add your signing configuration.

## References

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno Policy Library](https://kyverno.io/policies/)
- [Kyverno GitHub](https://github.com/kyverno/kyverno)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
