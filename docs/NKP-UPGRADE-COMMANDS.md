# NKP 2.16 Upgrade Commands

Exact CLI commands for upgrading NKP 2.16 management and workload clusters in airgapped and non-airgapped environments.

## Prerequisites

1. Verify NKP version: `nkp version`
2. Review NKP Release Notes
3. Ensure KUBECONFIG points to the correct cluster
4. For Nutanix clusters: Create VM image matching target Kubernetes version

## Upgrade Order

1. **Kommander** (Management cluster platform applications)
2. **Management Cluster** (Kubernetes version upgrade)
3. **Workload Clusters** (One at a time)

---

## 1. Upgrade Kommander (Management Cluster Platform)

### Non-Airgapped

```bash
nkp upgrade kommander
```

### Airgapped

```bash
# Run from root of extracted air-gapped bundle
./cli/nkp upgrade kommander --kommander-applications-repository ./application-repositories/kommander-applications-nkp-version.tar.gz
```

**Note:** If running from CLI directory, adjust path:
```bash
./nkp upgrade kommander --kommander-applications-repository ../application-repositories/kommander-applications-nkp-version.tar.gz
```

---

## 2. Upgrade Management Cluster (Nutanix)

### Non-Airgapped & Airgapped

```bash
nkp upgrade cluster nutanix \
  --cluster-name ${MANAGEMENT_CLUSTER_NAME} \
  --vm-image ${VM_IMAGE_NAME}
```

**Variables:**
- `MANAGEMENT_CLUSTER_NAME`: Name of your management cluster (e.g., `dm-nkp-mgmt-1`)
- `VM_IMAGE_NAME`: NKP OS image name in Prism Central (e.g., `nkp-rocky<version>-kubernetes<version>-<timestamp>`)

**Example:**
```bash
nkp upgrade cluster nutanix \
  --cluster-name dm-nkp-mgmt-1 \
  --vm-image nkp-rocky9.4-kubernetes1.33.0-20250101
```

---

## 3. Upgrade Workload Clusters (Nutanix)

### Non-Airgapped & Airgapped

**First, get cluster namespace:**
```bash
kubectl get cluster -A
```

**Then upgrade:**
```bash
nkp upgrade cluster nutanix \
  --cluster-name ${WORKLOAD_CLUSTER_NAME} \
  --vm-image ${VM_IMAGE_NAME} \
  -n ${WORKLOAD_CLUSTER_NAMESPACE}
```

**Variables:**
- `WORKLOAD_CLUSTER_NAME`: Name of workload cluster (e.g., `dm-nkp-workload-1`)
- `VM_IMAGE_NAME`: NKP OS image name in Prism Central
- `WORKLOAD_CLUSTER_NAMESPACE`: Namespace where cluster is deployed (from `kubectl get cluster -A`)

**Example:**
```bash
nkp upgrade cluster nutanix \
  --cluster-name dm-nkp-workload-1 \
  --vm-image nkp-rocky9.4-kubernetes1.33.0-20250101 \
  -n demo-zone-c4zz7-qjq6g
```

---

## Upgrade Workspace Platform Applications

After upgrading Kommander, upgrade platform applications in workspaces:

```bash
# Get workspace name
nkp get workspaces

# Set workspace name
export WORKSPACE_NAME=dm-dev-workspace

# Upgrade all platform applications in workspace
nkp upgrade workspace ${WORKSPACE_NAME}
```

---

## Troubleshooting

### Verbose Output
```bash
nkp upgrade kommander -v 6
```

### Fix Broken HelmReleases
If HelmRelease is in broken state (exhausted, rollback in progress):

```bash
kubectl -n kommander patch helmrelease <helmrelease_name> \
  --type='json' -p='[{"op": "replace", "path": "/spec/suspend", "value": true}]'

kubectl -n kommander patch helmrelease <helmrelease_name> \
  --type='json' -p='[{"op": "replace", "path": "/spec/suspend", "value": false}]'
```

---

## Parallel Worker Pool Upgrades

Control parallel worker pool upgrades using annotation on Cluster object:

```bash
kubectl annotate cluster <cluster-name> \
  topology.cluster.x-k8s.io/upgrade-concurrency=3 \
  -n <namespace>
```

- Default: `1` (upgrades one pool at a time)
- `3`: Upgrades up to 3 worker pools simultaneously

---

## Important Notes

1. **Always upgrade management cluster before workload clusters**
2. **Upgrade workload clusters one at a time** (for Starter edition)
3. **VM image must match target Kubernetes version**
4. **Custom domains may be inaccessible during upgrade**
5. **NKP UI and APIs may be inconsistent until upgrade completes**
6. **Deploy Pod Disruption Budgets** for critical applications before upgrading node pools

---

## References

- NKP 2.16 Release Notes
- [Upgrade Compatibility Tables](https://portal.nutanix.com/page/documents/upgrade-compatibility)
- [Konvoy Image Builder](https://portal.nutanix.com/page/documents/konvoy-image-builder)

