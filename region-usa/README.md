# USA Region

GitOps configuration for USA region availability zones.

## Directory Structure

```
region-usa/
└── az1/
    ├── management-cluster/     # Resources for NKP management cluster
    │   ├── bootstrap.yaml      # Bootstrap manifest
    │   ├── global/
    │   ├── namespaces/
    │   └── workspaces/
    │       └── dm-dev-workspace/
    │           ├── clusters/   # CAPI cluster definitions
    │           ├── applications/
    │           └── projects/
    └── workload-clusters/      # Resources deployed INSIDE workload clusters
        ├── dm-nkp-workload-1/
        └── dm-nkp-workload-2/
```

## Availability Zones

| AZ | Management Cluster Bootstrap | Status | Management Cluster |
|----|------------------------------|--------|-------------------|
| az1 | `az1/management-cluster/bootstrap.yaml` | ✅ Active | dm-nkp-mgmt-1 |
| az2 | `az2/management-cluster/bootstrap.yaml` | 🔜 Planned | - |
| az3 | `az3/management-cluster/bootstrap.yaml` | 🔜 Planned | - |

## Bootstrap Commands

### Management Cluster (AZ1)

```bash
# Bootstrap management cluster GitOps
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/management-cluster/bootstrap.yaml
```

### Workload Clusters

After workload clusters are created by CAPI, bootstrap GitOps inside them:

```bash
# Set kubeconfig to target workload cluster
export KUBECONFIG=~/.kube/dm-nkp-workload-1.kubeconfig

# Install Flux components (uses dm-nkp-gitops-workload namespace)
flux install --namespace=dm-nkp-gitops-workload

# Apply the bootstrap manifests
kubectl apply -k region-usa/az1/workload-clusters/dm-nkp-workload-1/flux-system/
```

See [workload-clusters/README.md](az1/workload-clusters/README.md) for detailed instructions.

## AZ1 Resources

Currently managing:
- Workspace: `dm-dev-workspace`
- Clusters: `dm-nkp-workload-1`, `dm-nkp-workload-2`
- Project: `dm-dev-project`

## Adding a New AZ

1. Copy structure from `az1/` as a template
2. Update `management-cluster/kustomization.yaml` with resources
3. Update all configurations (IPs, names, secrets)
4. Apply the bootstrap file to the new management cluster
