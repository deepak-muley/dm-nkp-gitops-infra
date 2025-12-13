# Workload Cluster GitOps

This directory contains GitOps configurations to be deployed **inside** each workload cluster.

> **Note**: This folder does NOT contain CAPI resources. Cluster definitions remain in
> `management-cluster/workspaces/dm-dev-workspace/clusters/`.

## Structure

```
workload-clusters/
├── _base/                              # Shared base configurations
│   └── infrastructure/                 # Shared infrastructure bases
├── dm-nkp-workload-1/
│   ├── bootstrap.yaml                  # ← Single command bootstrap
│   ├── infrastructure/                 # Core infrastructure components
│   └── apps/                           # Applications
└── dm-nkp-workload-2/
    ├── bootstrap.yaml                  # ← Single command bootstrap
    ├── infrastructure/
    └── apps/
```

## How to Bootstrap a Workload Cluster

### Prerequisites

1. Workload cluster is running and accessible (created by NKP/CAPI)
2. Kubeconfig for the workload cluster
3. Flux controllers already running in `kommander-flux` namespace (NKP default)

### Single Command Bootstrap

Each workload cluster has its own `bootstrap.yaml`. NKP workload clusters already have
Flux controllers running in `kommander-flux` namespace watching all namespaces, so no
need to install Flux separately.

```bash
# dm-nkp-workload-1
export KUBECONFIG=~/.kube/dm-nkp-workload-1.kubeconfig
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml

# dm-nkp-workload-2
export KUBECONFIG=~/.kube/dm-nkp-workload-2.kubeconfig
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml
```

Or locally:
```bash
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml
```

## Adding Applications to a Workload Cluster

1. Create your app manifests in the cluster's `apps/` folder:

```yaml
# region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  # ...
```

2. Update the `apps/kustomization.yaml`:

```yaml
resources:
  - my-app/
```

3. Commit and push - Flux will automatically deploy it.

## Adding a New Workload Cluster

1. Copy an existing cluster folder:
   ```bash
   cp -r dm-nkp-workload-1 dm-nkp-workload-3
   ```

2. Update paths in `flux-system/*.yaml` to point to the new cluster name

3. Bootstrap the new cluster using one of the options above
