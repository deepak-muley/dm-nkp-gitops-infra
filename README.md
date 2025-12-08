# cluster-gitops

The objective of this project is to provide guidance on using gitops to manage NKP Management Cluster resources like:
- Workspaces & Workspace RBAC
- Projects & Workspace RBAC
- Clusters

Simply apply the following manifest to apply this to the cluster.
> Note: Make changes to the workspacs, projects, rbac and clusters to be created as required
> For clusters it is assumed that any secrets with PC credentials or Registry Credentials will be applied directly in the given workspace namespace of the Management Cluster
```
kubectl apply -f -  <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-demo
  namespace: kommander
spec:
  interval:  5s
  ref:
    branch: dev
  timeout: 20s
  url: https://github.com/deepak-muley/dm-gitops-dev.git
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-demo
  namespace: kommander
spec:
  interval: 5s
  path: ./
  prune: true
  sourceRef:
   kind: GitRepository
   name: gitops-demo
   namespace: kommander
EOF


```

Here is the structure of the folders and files.
```
.
├── clusters-kustomization.yaml
├── global-kustomization.yaml
├── kustomization.yaml
├── kustomizations
│   ├── clusters
│   │   └── kustomization.yaml
│   ├── global
│   │   └── kustomization.yaml
│   ├── projects
│   │   └── kustomization.yaml
│   ├── workspace-rbac
│   │   └── kustomization.yaml
│   └── workspaces
│       ├── applications
│       │   └── kustomization.yaml
│       └── kustomization.yaml
├── projects-kustomization.yaml
├── README.md
├── resources
│   ├── global
│   │   ├── kustomization.yaml
│   │   └── virtualgroups.yaml
│   └── workspaces
│       ├── batcave
│       │   ├── batcave.yaml
│       │   ├── clusters
│       │   │   ├── dummy-configmap.yaml
│       │   │   └── kustomization.yaml
│       │   ├── projects
│       │   │   ├── batman
│       │   │   │   └── batman.yaml
│       │   │   ├── kustomization.yaml
│       │   │   └── robin
│       │   │       └── robin.yaml
│       │   └── rbac
│       │       ├── batcave-superheros-rolebinding.yaml
│       │       └── kustomization.yaml
│       ├── dm-dev-workspace
│       │   ├── clusters
│       │   │   ├── dm-nkp-workload-1-sealed-secrets.yaml
│       │   │   ├── dm-nkp-workload-1.yaml
│       │   │   ├── dm-nkp-workload-2-sealed-secrets.yaml
│       │   │   ├── dm-nkp-workload-2.yaml
│       │   │   ├── kustomization.yaml
│       │   │   ├── README.md
│       │   │   └── sealed-secrets-public-key.pem
│       │   ├── dm-dev-workspace.yaml
│       │   └── projects
│       │       ├── dm-dev-project
│       │       │   └── dm-dev-project.yaml
│       │       └── kustomization.yaml
│       ├── kommander
│       │   └── applications
│       │       ├── kube-prometheus-stack-overrides-configmap.yaml
│       │       ├── kube-prometheus-stack.yaml
│       │       └── kustomization.yaml
│       ├── kustomization.yaml
│       └── oscorp
│           ├── oscorp.yaml
│           └── projects
│               ├── green-goblin
│               │   └── green-goblin.yaml
│               ├── kustomization.yaml
│               └── spiderman
│                   └── spiderman.yaml
├── workspace-applications-kustomization.yaml
├── workspace-rbac-kustomization.yaml
└── workspaces-kustomization.yaml
```
