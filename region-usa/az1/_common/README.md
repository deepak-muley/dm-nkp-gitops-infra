# Common / Shared Resources

This folder contains resources that are **shared across multiple clusters** (management and workload clusters).

## Structure

```
_common/
├── policies/
│   ├── gatekeeper/                  # Gatekeeper policies
│   │   ├── constraint-templates/    # Policy logic (Rego)
│   │   ├── constraints/             # Policy instances
│   │   ├── network-tests/           # Connectivity testing
│   │   └── README.md                # Policy documentation
│   └── kyverno/                     # Kyverno policies
│       └── README.md                # Policy documentation
└── policy-tests/                    # Policy validation tests
    ├── namespace.yaml               # policy-tests namespace
    ├── kustomization.yaml           # Main kustomization
    ├── README.md                    # Test documentation
    ├── pod-security/                # Pod security policy tests
    ├── rbac/                        # RBAC policy tests
    └── ... (more test categories)
```

## How It Works

### Single Source of Truth

All Gatekeeper policies are defined **once** in `_common/policies/gatekeeper/`.

Both management and workload clusters reference these shared policies:

```
┌─────────────────────────────────────────────────────────────────┐
│                    _common/policies/gatekeeper/                 │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │ constraint-templates │    │     constraints     │            │
│  │  (Policy Logic)      │    │  (Policy Instances) │            │
│  └──────────┬──────────┘    └──────────┬──────────┘            │
└─────────────┼──────────────────────────┼────────────────────────┘
              │                          │
     ┌────────┴────────┐        ┌────────┴────────┐
     ▼                 ▼        ▼                 ▼
┌─────────┐    ┌─────────────┐  ┌─────────────┐
│  Mgmt   │    │ Workload-1  │  │ Workload-2  │
│ Cluster │    │   Cluster   │  │   Cluster   │
└─────────┘    └─────────────┘  └─────────────┘
```

### Management Cluster

References via Flux Kustomization in:
`management-cluster/global/policies/flux-ks-gatekeeper.yaml`

### Workload Clusters

References via Flux Kustomization in each cluster's `bootstrap.yaml`:
- `workload-clusters/dm-nkp-workload-1/bootstrap.yaml`
- `workload-clusters/dm-nkp-workload-2/bootstrap.yaml`

## Benefits

1. **No Duplication** - Single copy of all policies
2. **Consistency** - All clusters get the same security policies
3. **Easy Updates** - Change once, applies everywhere
4. **Clear Ownership** - `_common` indicates shared resources

## Customization

If a cluster needs different settings:

1. **Option A: Namespace Exclusions** - The shared constraints already have configurable `excludedNamespaces`
2. **Option B: Kustomize Patches** - Create overlays in cluster-specific folders to patch constraints
3. **Option C: Separate Constraint** - Create cluster-specific constraint files alongside shared ones

## Adding New Policies

1. Add ConstraintTemplate to `_common/policies/gatekeeper/constraint-templates/<category>/`
2. Add Constraint to `_common/policies/gatekeeper/constraints/<category>/`
3. Update the kustomization.yaml files in those directories
4. Commit and push - all clusters will receive the new policy
5. **Add a test**: Create a test resource in `_common/policy-tests/<category>/test-<policy-name>.yaml` to verify the policy works

## Policy Tests

Test resources for validating policies are located in `_common/policy-tests/`. These tests intentionally violate policies to ensure they are being detected and enforced.

See `_common/policy-tests/README.md` for details on:
- How to run tests
- How to verify policy violations
- How to add tests for new policies

