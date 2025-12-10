# NKP GitOps - Multi-Region Multi-AZ

GitOps repository for managing NKP Management Cluster resources across multiple regions and availability zones.

## Regions & Availability Zones

| Region | Location | Availability Zones | Status |
|--------|----------|-------------------|--------|
| region-usa   | USA   | az1, az2, az3 | ✅ Active (az1) |
| region-india | India | az1, az2, az3 | 🔜 Planned |

This repository currently manages:
- **region-usa/az1/** - USA Region, Availability Zone 1

## What This Manages

- Workspaces & Workspace RBAC
- Projects & Project RBAC
- Clusters & Sealed Secrets
- Network Policies & Resource Quotas
- Platform Applications

## Bootstrap

Apply the bootstrap manifest to enable GitOps on the cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-gitops-dev/main/bootstrap.yaml
```

Or if you have the repo cloned locally:
```bash
kubectl apply -f bootstrap.yaml
```

> **Note:**
> - The bootstrap creates the GitRepository and root Kustomization in `kommander` namespace
> - All child Kustomizations will be created in `dm-nkp-gitops` namespace automatically

## Repository Structure

```
.
├── bootstrap.yaml                                  # Apply once to bootstrap GitOps
├── kustomization.yaml                              # Root - references all flux-ks.yaml files
│
├── region-usa/                                     # 🇺🇸 USA Region
│   ├── az1/                                        # Availability Zone 1 (Active)
│   │   ├── namespaces/
│   │   │   └── dm-nkp-gitops-namespace.yaml
│   │   ├── global/
│   │   │   ├── flux-ks.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── virtualgroups.yaml
│   │   └── workspaces/
│   │       ├── flux-ks.yaml                        # clusterops-workspaces
│   │       ├── kustomization.yaml
│   │       └── dm-dev-workspace/
│   │           ├── dm-dev-workspace.yaml
│   │           ├── applications/
│   │           │   ├── flux-ks.yaml                # clusterops-workspace-applications
│   │           │   └── ...
│   │           ├── clusters/
│   │           │   ├── flux-ks.yaml                # clusterops-clusters
│   │           │   ├── bases/
│   │           │   ├── overlays/
│   │           │   └── sealed-secrets/
│   │           │       └── flux-ks.yaml            # clusterops-sealed-secrets
│   │           ├── networkpolicies/
│   │           │   └── flux-ks.yaml                # clusterops-workspace-networkpolicies
│   │           ├── projects/
│   │           │   ├── flux-ks.yaml                # clusterops-project-definitions
│   │           │   └── dm-dev-project/
│   │           │       └── applications/
│   │           │           └── flux-ks.yaml        # clusterops-project-applications
│   │           ├── rbac/
│   │           │   └── flux-ks.yaml                # clusterops-workspace-rbac
│   │           └── resourcequotas/
│   │               └── flux-ks.yaml                # clusterops-workspace-resourcequotas
│   ├── az2/                                        # Availability Zone 2 (Future)
│   └── az3/                                        # Availability Zone 3 (Future)
│
└── region-india/                                   # 🇮🇳 India Region (Future)
    ├── az1/
    ├── az2/
    └── az3/
```

## Flux Kustomization Dependencies

```
Level 0 (No dependencies):
  ├── clusterops-global
  └── clusterops-workspaces

Level 1 (Depends on workspaces):
  ├── clusterops-workspace-applications
  ├── clusterops-workspace-rbac
  ├── clusterops-workspace-networkpolicies
  ├── clusterops-workspace-resourcequotas
  ├── clusterops-clusters
  ├── clusterops-sealed-secrets
  └── clusterops-project-definitions

Level 2 (Depends on project-definitions):
  └── clusterops-project-applications
```

## Adding a New Region

1. Create region directory: `region-<name>/`
2. Create AZ directories inside: `az1/`, `az2/`, `az3/`
3. Copy structure from existing AZ (e.g., `region-usa/az1/`)
4. Update all paths in flux-ks.yaml files
5. Add references to root `kustomization.yaml`

## Adding a New AZ in Existing Region

1. Copy existing AZ directory (e.g., `region-usa/az1/` → `region-usa/az2/`)
2. Update all flux-ks.yaml files to reference new path
3. Update workspace names, cluster names, etc.
4. Add references to root `kustomization.yaml`

## Adding a New Workspace

1. Create workspace directory: `region-<name>/az<n>/workspaces/<workspace-name>/`
2. Add workspace YAML and flux-ks.yaml files
3. Update `region-<name>/az<n>/workspaces/kustomization.yaml`

## Adding a New Cluster

1. Add cluster YAML under `.../clusters/bases/`
2. Add sealed secrets under `.../clusters/sealed-secrets/`
3. Optionally add overlays for version-specific patches
