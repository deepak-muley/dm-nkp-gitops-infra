# HCP/HRP Failures Debug Report

**Date:** 2025-12-27
**Cluster:** dm-nkp-workload-1
**Status:** Multiple failures detected

## Summary

Three HelmReleaseProxies (HRPs) are failing on `dm-nkp-workload-1`:
1. `cilium-dm-nkp-workload-1-kbx8x` - post-upgrade hooks failed
2. `konnector-agent-dm-nkp-workload-1-6jdqc` - post-upgrade hooks failed
3. `nutanix-csi-storage-dm-nkp-workload-1-kxh46` - pre-upgrade hooks failed

All failures are due to Helm hook timeouts waiting for pods to become ready.

## Root Cause Analysis

### 1. Cilium Pod Failures
- **Status:** 2/4 Cilium pods in `CrashLoopBackOff`
- **Issue:** Startup probe failing on port 9879 (healthz endpoint)
- **Impact:** Cilium daemonset shows 0/4 ready, preventing proper CNI functionality

### 2. CCM (Cloud Controller Manager) Crash
- **Status:** CCM pod in `CrashLoopBackOff`
- **Error:** `dial tcp 10.96.0.1:443: i/o timeout` - Cannot reach Kubernetes API server
- **Impact:**
  - Nodes cannot be initialized (taints remain)
  - Worker nodes have `node.cloudprovider.kubernetes.io/uninitialized` taint
  - Worker nodes have `node.cluster.x-k8s.io/uninitialized` taint (CAPI)

### 3. Node Taint Issues
- **Control Plane Node:** Has `node.cloudprovider.kubernetes.io/uninitialized` taint
- **Worker Nodes:** Have both `node.cloudprovider.kubernetes.io/uninitialized` and `node.cluster.x-k8s.io/uninitialized` taints
- **Impact:** Prevents pods from scheduling (konnector-agent, CSI precheck, cilium-operator)

### 4. Pod Scheduling Failures
- **konnector-agent:** Cannot schedule due to node taints
- **nutanix-csi-precheck-job:** Cannot schedule due to node taints
- **cilium-operator:** Some replicas cannot schedule (control plane has no free ports, workers have taints)

## Circular Dependency Problem

```
Cilium failing → Network issues → CCM can't reach API → CCM crashes →
Nodes stay uninitialized → Pods can't schedule → Helm hooks timeout → HRPs fail
```

## Detailed Findings

### Failed HRPs

```bash
# Check failed HRPs
kubectl get helmreleaseproxies -n dm-dev-workspace --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf | grep -E "(cilium|konnector|nutanix-csi).*workload-1"
```

| HRP Name | Cluster | Status | Reason | Message |
|----------|---------|--------|--------|---------|
| cilium-dm-nkp-workload-1-kbx8x | dm-nkp-workload-1 | failed | HelmInstallOrUpgradeFailed | post-upgrade hooks failed: timed out waiting for condition |
| konnector-agent-dm-nkp-workload-1-6jdqc | dm-nkp-workload-1 | failed | HelmInstallOrUpgradeFailed | post-upgrade hooks failed: timed out waiting for condition |
| nutanix-csi-storage-dm-nkp-workload-1-kxh46 | dm-nkp-workload-1 | failed | HelmInstallOrUpgradeFailed | pre-upgrade hooks failed: timed out waiting for condition |

### Failed HCPs

```bash
# Check failed HCPs
kubectl get helmchartproxies -n dm-dev-workspace --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf | grep -v "True"
```

| HCP Name | Status | Reason |
|----------|--------|--------|
| cilium-019afb99-7556-7c79-b02b-f66b91c8f57a | False | HelmReleaseProxySpecsUpdating |
| konnector-agent-019afb99-7556-7c79-b02b-f66b91c8f57a | False | HelmInstallOrUpgradeFailed |
| nutanix-csi-019afb99-7556-7c79-b02b-f66b91c8f57a | False | HelmInstallOrUpgradeFailed |

### Workload Cluster Status

**Nodes:**
- All 4 nodes are in `Ready` state
- All nodes have uninitialized taints preventing pod scheduling

**Critical Pods:**
- Cilium: 0/4 ready (2 pods crashing, 2 running but unhealthy)
- CCM: 0/1 ready (CrashLoopBackOff)
- Konnector-agent: 0/1 ready (Pending - can't schedule)
- CSI precheck: 0/1 ready (Pending - can't schedule)

## Recommended Fixes

### Step 1: Fix Cilium Issues

The Cilium pods are failing health checks. First, check if there's a configuration issue:

```bash
# Check Cilium configuration
kubectl get configmap -n kube-system cilium-config --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig -o yaml

# Verify k8sServiceHost matches control plane VIP
# Should be: 10.23.130.62 (from HCP configuration)
```

If Cilium configuration is correct, try restarting the daemonset:

```bash
# Restart Cilium daemonset
kubectl rollout restart daemonset/cilium -n kube-system --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig

# Wait for pods to become ready
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=5m --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
```

### Step 2: Fix CCM Issues

CCM is crashing because it can't reach the API server. This is likely because Cilium networking isn't fully functional.

**Option A: Wait for Cilium to stabilize**
Once Cilium is working, CCM should be able to connect.

**Option B: Check CCM credentials**
Verify the secret exists and is correct:

```bash
# Check CCM secret
kubectl get secret -n kube-system nutanix-ccm-credentials --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig

# Restart CCM deployment
kubectl rollout restart deployment/nutanix-cloud-controller-manager -n kube-system --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
```

### Step 3: Remove Node Taints (If CCM Still Fails)

**⚠️ WARNING:** Only do this if CCM continues to fail after Cilium is fixed. This is a workaround, not a permanent solution.

```bash
# Remove uninitialized taints from worker nodes
WORKLOAD_KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig

# Get worker node names
WORKER_NODES=$(kubectl get nodes --kubeconfig=$WORKLOAD_KUBECONFIG -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/control-plane!="")].metadata.name}')

# Remove CAPI uninitialized taint (this will be re-added if CCM doesn't work)
for node in $WORKER_NODES; do
    kubectl taint nodes $node node.cluster.x-k8s.io/uninitialized- --kubeconfig=$WORKLOAD_KUBECONFIG || true
done

# CCM should remove cloudprovider taint once it's working
```

### Step 4: Retry Failed HRPs

Once the underlying issues are fixed, retry the failed HRPs:

```bash
MGMT_KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf
NAMESPACE=dm-dev-workspace

# Delete failed HRPs (they will be recreated by HCP)
kubectl delete helmreleaseproxy cilium-dm-nkp-workload-1-kbx8x -n $NAMESPACE --kubeconfig=$MGMT_KUBECONFIG
kubectl delete helmreleaseproxy konnector-agent-dm-nkp-workload-1-6jdqc -n $NAMESPACE --kubeconfig=$MGMT_KUBECONFIG
kubectl delete helmreleaseproxy nutanix-csi-storage-dm-nkp-workload-1-kxh46 -n $NAMESPACE --kubeconfig=$MGMT_KUBECONFIG

# Wait for HCP to recreate them
kubectl wait --for=condition=Ready helmreleaseproxy -l cluster.x-k8s.io/cluster-name=dm-nkp-workload-1 -n $NAMESPACE --timeout=10m --kubeconfig=$MGMT_KUBECONFIG
```

## Verification Commands

```bash
# Check HRP status
kubectl get helmreleaseproxies -n dm-dev-workspace --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf | grep workload-1

# Check HCP status
kubectl get helmchartproxies -n dm-dev-workspace --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf | grep workload-1

# Check workload cluster pods
kubectl get pods -n kube-system --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig | grep -E "(cilium|nutanix-cloud|konnector)"

# Check node taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
```

## Prevention

To prevent similar issues in the future:

1. **Monitor Cilium health** - Ensure Cilium pods are healthy before deploying other components
2. **Verify CCM is working** - CCM must be able to reach API server and initialize nodes
3. **Check node taints** - Ensure nodes don't have blocking taints before deploying applications
4. **Increase hook timeouts** - Consider increasing Helm hook timeouts if pods take longer to start
5. **Use readiness gates** - Ensure pods have proper readiness probes

## Related Documentation

- [CAREN Workarounds](../../tools/caren-workarounds/README.md)
- [Debugging GitOps](../../docs/DEBUGGING-GITOPS.md)
- [Cluster Health Check Script](../../scripts/check-cluster-health.sh)

