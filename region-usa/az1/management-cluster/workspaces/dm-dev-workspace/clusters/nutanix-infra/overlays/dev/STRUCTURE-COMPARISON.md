# Structure Comparison: Bases + Overlays vs Merged Bases

This document compares two approaches for managing cluster configurations at scale.

## Current Structure: Bases + Overlays (RECOMMENDED)

### Directory Layout
```
nutanix-infra/
├── bases/
│   ├── dm-nkp-workload-1.yaml      # Cluster-specific base config
│   ├── dm-nkp-workload-2.yaml
│   └── kustomization.yaml
└── overlays/
    └── dev/
        ├── kustomization.yaml      # All patches (common + cluster-specific)
        ├── update-image-name.sh    # Helper script
        ├── update-k8s-version.sh   # Helper script
        └── README.md
```

### How It Works

**Base files** (`bases/`):
- Define cluster identity and unique configuration
- One file per cluster
- Contains cluster-specific values (endpoints, secrets, network configs)

**Overlay files** (`overlays/dev/`):
- Apply environment-specific patches
- Common patches: image name, k8s version (apply to ALL clusters)
- Cluster-specific patches: class, replicas, annotations (unique per cluster)

### Example: kustomization.yaml Structure

```yaml
patches:
  # COMMON PATCHES - Apply to ALL clusters
  - target: { kind: Cluster, name: dm-nkp-workload-1 }
    patch: |-
      - op: replace
        path: /spec/topology/variables/0/value/controlPlane/nutanix/machineDetails/image/name
        value: nkp-rocky-9.6-release-1.34.1-20251225180234  # ← Update here for all

  - target: { kind: Cluster, name: dm-nkp-workload-2 }
    patch: |-
      - op: replace
        path: /spec/topology/variables/0/value/controlPlane/nutanix/machineDetails/image/name
        value: nkp-rocky-9.6-release-1.34.1-20251225180234  # ← Update here for all

  # CLUSTER-SPECIFIC PATCHES - Unique per cluster
  - target: { kind: Cluster, name: dm-nkp-workload-1 }
    patch: |-
      - op: replace
        path: /spec/topology/class
        value: nkp-nutanix-v2.17.0
      - op: add
        path: /spec/topology/workers/machineDeployments/0/replicas
        value: 3
```

### Updating for 100 Clusters

**Update image name for ALL clusters:**
```bash
# Option 1: Use helper script
./update-image-name.sh OLD_IMAGE NEW_IMAGE

# Option 2: Search & replace in kustomization.yaml
sed -i 's/OLD_IMAGE/NEW_IMAGE/g' kustomization.yaml
```

**Update specific cluster:**
- Edit only that cluster's patches in CLUSTER-SPECIFIC PATCHES section

### Pros
✅ Single place to update common values (image, version)
✅ Clear separation: base = identity, overlay = environment
✅ Easy to add new environments (staging, prod)
✅ Scales to 100+ clusters
✅ Helper scripts for bulk updates
✅ Can see what's different between environments

### Cons
❌ Requires understanding patches
❌ Slightly more complex structure
❌ Need to list all clusters in common patches

---

## Alternative Structure: Merged Bases (NOT RECOMMENDED)

### Directory Layout
```
nutanix-infra/
└── dev/                          # Renamed from "bases"
    ├── dm-nkp-workload-1.yaml    # Full config + dev values
    ├── dm-nkp-workload-2.yaml    # Full config + dev values (duplicated!)
    └── kustomization.yaml
```

### How It Works

**Base files** (`dev/`):
- Contain complete cluster configuration
- Include both cluster identity AND environment-specific values
- Each file is self-contained

### Example: dm-nkp-workload-1.yaml

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: dm-nkp-workload-1
spec:
  topology:
    class: nkp-nutanix-v2.17.0
    version: v1.34.1
    variables:
      - name: clusterConfig
        value:
          controlPlane:
            nutanix:
              machineDetails:
                image:
                  name: nkp-rocky-9.6-release-1.34.1-20251225180234  # ← In every file
          # ... rest of config
```

### Updating for 100 Clusters

**Update image name for ALL clusters:**
```bash
# Must update 100 files!
for file in dev/dm-nkp-workload-*.yaml; do
  sed -i 's/OLD_IMAGE/NEW_IMAGE/g' "$file"
done
```

**Update specific cluster:**
- Edit that cluster's file directly

### Pros
✅ Simpler structure (no patches)
✅ Direct editing of cluster config
✅ Easy to understand

### Cons
❌ **100 files to update for common changes**
❌ **Duplication of environment config**
❌ **Hard to maintain consistency**
❌ **No separation between cluster and environment**
❌ **Can't easily have multiple environments**
❌ **High risk of missing updates**
❌ **Violates DRY principle**

---

## Recommendation: Use Bases + Overlays

For 100+ clusters, **bases + overlays is the clear winner**:

1. **Single update point** for common values (image, version)
2. **Scalable** - adding clusters doesn't increase maintenance burden
3. **Multi-environment support** - easy to add staging/prod overlays
4. **Helper scripts** make bulk updates trivial
5. **Clear separation** of concerns

### When to Use Merged Bases

Only consider merged bases if:
- You have 1-2 clusters total
- Clusters are completely different (no shared config)
- You never plan to have multiple environments
- You prefer simplicity over scalability

---

## Migration Path

If you currently have merged bases and want to migrate:

1. **Extract common values** to overlay patches
2. **Keep cluster-specific config** in bases
3. **Create overlay** with common patches
4. **Test** with `kustomize build`
5. **Gradually migrate** clusters

---

## Quick Reference

### Current Structure (Bases + Overlays)
```bash
# Update image for all clusters
cd overlays/dev
./update-image-name.sh OLD NEW

# Update k8s version for all clusters
./update-k8s-version.sh v1.35.0

# Update specific cluster
# Edit kustomization.yaml → CLUSTER-SPECIFIC PATCHES section
```

### Alternative Structure (Merged Bases)
```bash
# Update image for all clusters (100 files!)
for file in dev/dm-nkp-workload-*.yaml; do
  sed -i 's/OLD_IMAGE/NEW_IMAGE/g' "$file"
done

# Update specific cluster
# Edit dev/dm-nkp-workload-N.yaml directly
```

---

## Conclusion

**For 100+ clusters: Always use bases + overlays.**

The slight complexity of patches is far outweighed by the benefits of:
- Single source of truth for common values
- Easy bulk updates
- Multi-environment support
- Better maintainability

