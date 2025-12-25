# Dev Environment Overlay

This overlay applies dev environment-specific configurations to all clusters.

## Structure

```
overlays/dev/
├── kustomization.yaml          # Main kustomization with all patches
├── update-image-name.sh        # Helper script to update image for all clusters
├── update-k8s-version.sh       # Helper script to update k8s version for all clusters
├── common-patches.yaml         # Reference file (shows common patch pattern)
├── cluster-specific-patches/   # Reference directory (shows cluster-specific pattern)
│   ├── dm-nkp-workload-1.yaml
│   └── dm-nkp-workload-2.yaml
└── README.md                   # This file
```

## Quick Reference

### Update Image Name for ALL Clusters

**Option 1: Use helper script (recommended)**
```bash
./update-image-name.sh OLD_IMAGE_NAME NEW_IMAGE_NAME
# Example:
./update-image-name.sh nkp-rocky-9.6-release-1.34.1-20251225180234 nkp-rocky-9.6-release-1.35.0-20260101120000
```

**Option 2: Manual update**
1. Open `kustomization.yaml`
2. Find the "COMMON PATCHES" section (single patch with `kind: Cluster` target)
3. Update the image name value in **ONE place** - it applies to all clusters automatically!
   ```yaml
   - target:
       kind: Cluster  # ← Applies to ALL clusters
     patch: |-
       - op: replace
         path: /spec/topology/variables/0/value/controlPlane/nutanix/machineDetails/image/name
         value: nkp-rocky-9.6-release-NEW-VERSION  # ← Update here
   ```

### Update K8s Version for ALL Clusters

**Option 1: Use helper script (recommended)**
```bash
./update-k8s-version.sh NEW_VERSION
# Example:
./update-k8s-version.sh v1.35.0
```

**Option 2: Manual update**
1. Open `kustomization.yaml`
2. Find the "COMMON PATCHES" section (or add version patches)
3. Add version patches if not present:
   ```yaml
   - target:
       kind: Cluster
       name: dm-nkp-workload-1
     patch: |-
       - op: replace
         path: /spec/topology/version
         value: v1.35.0
   ```

### Update a SPECIFIC Cluster

1. Open `kustomization.yaml`
2. Find the cluster in "CLUSTER-SPECIFIC PATCHES" section
3. Modify only that cluster's patches

### Add a New Cluster

1. **No need to add common patches!** The wildcard target `kind: Cluster` automatically applies to all clusters, including new ones.

2. Add cluster-specific patches in "CLUSTER-SPECIFIC PATCHES" section:
   ```yaml
   - target:
       kind: Cluster
       name: dm-nkp-workload-N
     patch: |-
       - op: replace
         path: /spec/topology/class
         value: nkp-nutanix-v2.17.0
       - op: add
         path: /spec/topology/workers/machineDeployments/0/replicas
         value: 3
   ```

## Reference Files

- `common-patches.yaml` - Shows the pattern for common patches (for reference only)
- `cluster-specific-patches/` - Shows the pattern for cluster-specific patches (for reference only)

These files are for reference/documentation. The actual patches are in `kustomization.yaml`.

## Scaling to 100+ Clusters

When you have many clusters, consider:

1. **Use search & replace** for common updates:
   ```bash
   # Update image name for all clusters
   sed -i 's/nkp-rocky-9.6-release-OLD/nkp-rocky-9.6-release-NEW/g' kustomization.yaml
   ```

2. **Use scripts** to generate patches for new clusters:
   ```bash
   # Generate common patches for a new cluster
   ./scripts/generate-cluster-patches.sh dm-nkp-workload-3
   ```

3. **Keep patches organized**:
   - Common patches at the top
   - Cluster-specific patches below
   - Clear comments separating sections

## Best Practices

- ✅ Update common values (image, version) in COMMON PATCHES section
- ✅ Keep cluster-specific config in CLUSTER-SPECIFIC PATCHES section
- ✅ Use clear comments to separate sections
- ✅ Test with `kustomize build` before committing
- ❌ Don't duplicate common values in cluster-specific patches
- ❌ Don't mix common and cluster-specific patches

