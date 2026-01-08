# Troubleshooting: clusterops-kyverno-policies Not Created

## Issue

The `clusterops-kyverno-policies` Flux Kustomization is not being created in the `dm-nkp-gitops-infra` namespace.

## Root Cause Analysis

The `clusterops-kyverno-policies` kustomization is created through this dependency chain:

1. **`clusterops-usa-az1`** (in `kommander` namespace)
   - Points to: `./region-usa/az1/management-cluster`
   - Created by: `region-usa/az1/management-cluster/bootstrap.yaml`

2. **`clusterops-global`** (in `dm-nkp-gitops-infra` namespace)
   - Points to: `./region-usa/az1/management-cluster/global`
   - Created by: `region-usa/az1/management-cluster/global/flux-ks.yaml`
   - Included in: `region-usa/az1/management-cluster/kustomization.yaml`

3. **`clusterops-kyverno-policies`** (in `dm-nkp-gitops-infra` namespace)
   - Points to: `./region-usa/az1/_common/policies/kyverno`
   - Created by: `region-usa/az1/management-cluster/global/policies/flux-ks-kyverno.yaml`
   - Included in: `region-usa/az1/management-cluster/global/policies/kustomization.yaml`
   - Which is included in: `region-usa/az1/management-cluster/global/kustomization.yaml`

## Troubleshooting Steps

### 1. Check if clusterops-global exists and is ready

```bash
kubectl get kustomization clusterops-global -n dm-nkp-gitops-infra

# Check status
kubectl get kustomization clusterops-global -n dm-nkp-gitops-infra -o yaml | \
  grep -A 5 "status:\|conditions:"
```

### 2. Check if clusterops-usa-az1 is working

```bash
kubectl get kustomization clusterops-usa-az1 -n kommander

# Check if it's applying global resources
kubectl get kustomization clusterops-usa-az1 -n kommander -o yaml | \
  grep -A 10 "status:\|conditions:"
```

### 3. Verify the kustomization structure

```bash
# Build the global kustomization locally to verify structure
cd region-usa/az1/management-cluster/global
kustomize build . | grep -E "kind: Kustomization|name: clusterops-kyverno-policies"
```

### 4. Check for errors in clusterops-global

```bash
# Check reconciliation status
kubectl describe kustomization clusterops-global -n dm-nkp-gitops-infra

# Check logs
kubectl logs -n kommander-flux deploy/kustomize-controller | \
  grep -i "clusterops-global\|kyverno-policies" | tail -20
```

### 5. Verify namespace exists

```bash
kubectl get namespace dm-nkp-gitops-infra
```

### 6. Force reconciliation

```bash
# Force reconcile clusterops-global
flux reconcile kustomization clusterops-global -n dm-nkp-gitops-infra

# Or manually trigger
kubectl annotate kustomization clusterops-global -n dm-nkp-gitops-infra \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite
```

## Common Issues

### Issue 1: clusterops-global not created

**Symptom**: `clusterops-global` doesn't exist

**Solution**: Check if `clusterops-usa-az1` is working and includes `global/flux-ks.yaml`

```bash
# Verify bootstrap was applied
kubectl get kustomization clusterops-usa-az1 -n kommander

# Check if global/flux-ks.yaml is in the path
kubectl get kustomization clusterops-usa-az1 -n kommander -o yaml | \
  grep -A 5 "path:"
```

### Issue 2: clusterops-global not reconciling

**Symptom**: `clusterops-global` exists but shows errors

**Solution**: Check for build errors or path issues

```bash
# Check status
kubectl get kustomization clusterops-global -n dm-nkp-gitops-infra -o yaml | \
  grep -A 10 "status:"

# Check for path errors
kubectl describe kustomization clusterops-global -n dm-nkp-gitops-infra | \
  grep -i "error\|path\|not found"
```

### Issue 3: policies/kustomization.yaml not found

**Symptom**: Error about missing `policies/kustomization.yaml`

**Solution**: Verify the file exists and is correct

```bash
# Verify file exists
ls -la region-usa/az1/management-cluster/global/policies/kustomization.yaml

# Verify it includes flux-ks-kyverno.yaml
cat region-usa/az1/management-cluster/global/policies/kustomization.yaml
```

### Issue 4: GitRepository not synced

**Symptom**: Path not found errors

**Solution**: Check GitRepository sync status

```bash
# Check GitRepository
kubectl get gitrepository gitops-usa-az1 -n kommander

# Force sync
flux reconcile source git gitops-usa-az1 -n kommander
```

## Expected Behavior

When everything is working correctly:

1. `clusterops-usa-az1` reconciles and creates `clusterops-global`
2. `clusterops-global` reconciles and builds `./region-usa/az1/management-cluster/global`
3. This includes `policies/kustomization.yaml` which includes `flux-ks-kyverno.yaml`
4. `clusterops-kyverno-policies` is created in `dm-nkp-gitops-infra` namespace
5. `clusterops-kyverno-policies` reconciles and applies Kyverno policies

## Verification

After troubleshooting, verify the kustomization exists:

```bash
# Should show clusterops-kyverno-policies
kubectl get kustomization -n dm-nkp-gitops-infra | grep kyverno

# Check its status
kubectl get kustomization clusterops-kyverno-policies -n dm-nkp-gitops-infra -o wide
```

