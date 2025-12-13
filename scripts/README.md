# Scripts

Utility scripts for managing the NKP GitOps infrastructure.

## migrate-to-new-structure.sh

Safely migrates from the old repository structure to the new management-cluster/workload-clusters structure.

### What It Does

1. **Disables pruning** on the Flux Kustomization (prevents resource deletion)
2. **Prompts you to push** changes to Git
3. **Applies new bootstrap** with updated path
4. **Triggers reconciliation** via Flux CLI or kubectl annotations
5. **Verifies** resources are healthy
6. **Optionally re-enables pruning**

### Usage

```bash
# Make sure kubectl is configured to management cluster
export KUBECONFIG=~/.kube/dm-nkp-mgmt-1.kubeconfig

# Run the migration
./scripts/migrate-to-new-structure.sh
```

### Why Is This Needed?

The repository structure changed from:
```
region-usa/az1/
├── bootstrap.yaml
├── global/
├── namespaces/
└── workspaces/
```

To:
```
region-usa/az1/
├── management-cluster/    # Management cluster resources moved here
│   ├── bootstrap.yaml
│   ├── global/
│   ├── namespaces/
│   └── workspaces/
└── workload-clusters/     # NEW: Resources for workload clusters
    ├── dm-nkp-workload-1/
    └── dm-nkp-workload-2/
```

The Flux Kustomization path changed from `./region-usa/az1` to `./region-usa/az1/management-cluster`.

Without disabling pruning first, Flux would see the old path as empty and **delete all resources** including your clusters!

