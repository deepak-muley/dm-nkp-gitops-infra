# USA Region - Availability Zone 1

GitOps configuration for AZ1 in the USA region.

## Directory Structure

```
az1/
├── management-cluster/           # Resources for NKP management cluster
│   ├── bootstrap.yaml            # Bootstrap manifest
│   ├── global/                   # Cluster-wide resources
│   │   └── sealed-secrets-controller/
│   ├── namespaces/
│   └── workspaces/
│       └── dm-dev-workspace/
│           ├── clusters/         # CAPI workload cluster definitions
│           │   ├── bases/        # Base cluster manifests
│           │   ├── overlays/     # Version-specific patches
│           │   └── sealed-secrets/
│           ├── applications/     # Workspace applications
│           └── projects/         # Project definitions
│
└── workload-clusters/            # Resources deployed INSIDE workload clusters
    ├── _base/                    # Shared base configurations
    │   └── infrastructure/
    │       └── sealed-secrets-controller/
    ├── dm-nkp-workload-1/
    │   ├── bootstrap.yaml        # All-in-one bootstrap manifest
    │   ├── infrastructure/       # Infrastructure components
    │   │   └── sealed-secrets/   # Sealed secrets for this cluster
    │   └── apps/                 # Applications
    └── dm-nkp-workload-2/
        ├── bootstrap.yaml
        ├── infrastructure/
        │   └── sealed-secrets/
        └── apps/
```

## Quick Start

### 1. Bootstrap Management Cluster

```bash
# Apply to management cluster
export KUBECONFIG=~/.kube/dm-nkp-mgmt-1.conf
kubectl apply -f region-usa/az1/management-cluster/bootstrap.yaml
```

This sets up GitOps on the management cluster, which will:
- Create workspaces, projects
- Deploy CAPI workload cluster definitions
- Install workspace/project applications

### 2. Bootstrap Workload Clusters

After workload clusters are created and accessible (Flux controllers are already installed by NKP in `kommander-flux` namespace):

```bash
# dm-nkp-workload-1
export KUBECONFIG=~/.kube/dm-nkp-workload-1.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml

# dm-nkp-workload-2
export KUBECONFIG=~/.kube/dm-nkp-workload-2.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml
```

The bootstrap creates:
- `dm-nkp-gitops-workload` namespace for Flux resources
- GitRepository pointing to this repo
- Kustomizations for infrastructure and apps

## Documentation

- [Management Cluster README](management-cluster/README.md)
- [Workload Clusters README](workload-clusters/README.md)

## Resources Managed

| Resource Type | Location |
|--------------|----------|
| Workspaces | `management-cluster/workspaces/` |
| CAPI Cluster Definitions | `management-cluster/workspaces/dm-dev-workspace/clusters/` |
| Workspace Applications | `management-cluster/workspaces/dm-dev-workspace/applications/` |
| Projects | `management-cluster/workspaces/dm-dev-workspace/projects/` |
| Workload Cluster Infra | `workload-clusters/<cluster-name>/infrastructure/` |
| Workload Cluster Apps | `workload-clusters/<cluster-name>/apps/` |
