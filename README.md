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
├── kustomization.yaml
├── kustomizations
│   ├── clusters
│   ├── project-rbac
│   ├── projects
│   │   └── kustomization.yaml
│   ├── workspace-rbac
│   └── workspaces
│       └── kustomization.yaml
├── projects-kustomization.yaml
├── resources
│   └── workspaces
│       ├── batcave
│       │   ├── batcave.yaml
│       │   ├── clusters
│       │   ├── projects
│       │   │   ├── batman
│       │   │   │   ├── batman.yaml
│       │   │   │   └── rbac
│       │   │   └── robin
│       │   │       ├── rbac
│       │   │       └── robin.yaml
│       │   └── rbac
│       └── oscorp
│           ├── clusters
│           ├── oscorp.yaml
│           ├── projects
│           │   ├── green-goblin
│           │   │   ├── green-goblin.yaml
│           │   │   └── rbac
│           │   └── spiderman
│           │       ├── rbac
│           │       └── spiderman.yaml
│           └── rbac
└── workspaces-kustomization.yaml
```
