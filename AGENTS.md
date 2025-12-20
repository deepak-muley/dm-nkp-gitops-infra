# AGENTS.md - AI Agent Guide

This document provides essential context and guidelines for AI agents working with this GitOps infrastructure repository.

## Repository Overview

This is a **GitOps infrastructure repository** for managing **NKP (Nutanix Kubernetes Platform)** resources across multiple regions and availability zones using **Flux CD** and **Kustomize**.

### Key Technologies

- **Flux CD**: GitOps operator for Kubernetes
- **Kustomize**: Configuration management and patching
- **NKP/Kommander**: Nutanix Kubernetes Platform management layer
- **CAPI (Cluster API)**: Declarative cluster lifecycle management
- **Sealed Secrets**: Encrypted secrets management
- **Gatekeeper/Kyverno**: Policy enforcement engines

---

## Repository Structure

### High-Level Organization

```
dm-nkp-gitops-infra/
├── region-{name}/              # Multi-region support (usa, india)
│   └── az{n}/                 # Multi-AZ support (az1, az2, az3)
│       ├── management-cluster/ # Resources for NKP management cluster
│       ├── workload-clusters/  # Resources deployed INSIDE workload clusters
│       ├── infrastructure/     # Cloud provider configs (AWS, Azure, GCP, Nutanix)
│       └── _common/            # Shared resources (policies, etc.)
├── docs/                       # Documentation
├── scripts/                    # Automation scripts
└── tools/                      # Utility tools and workarounds
```

### Key Paths

- **Management Cluster Bootstrap**: `region-{region}/az{n}/management-cluster/bootstrap.yaml`
- **Workload Cluster Bootstrap**: `region-{region}/az{n}/workload-clusters/{cluster-name}/bootstrap.yaml`
- **Shared Policies**: `region-{region}/az{n}/_common/policies/`
- **CAPI Clusters**: `region-{region}/az{n}/management-cluster/workspaces/{workspace}/clusters/`

---

## Critical Conventions

### 1. Naming Conventions

- **GitRepository**: `gitops-{region}-{az}` (e.g., `gitops-usa-az1`)
- **Kustomization**: `clusterops-{region}-{az}` or `clusterops-{category}` (e.g., `clusterops-clusters`)
- **Namespaces**:
  - Management cluster GitOps: `dm-nkp-gitops-infra`
  - Workload cluster GitOps: `dm-nkp-gitops-workload`
  - Kommander: `kommander`
- **Workspaces**: `{prefix}-{purpose}-workspace` (e.g., `dm-dev-workspace`)
- **Clusters**: `dm-nkp-{purpose}-{number}` (e.g., `dm-nkp-workload-1`)

### 2. Flux Kustomization Dependencies

**CRITICAL**: Kustomizations have explicit dependencies. Always respect the dependency chain:

```
Level 0 (no dependencies):
  - clusterops-global
  - clusterops-workspaces
  - clusterops-sealed-secrets-controller

Level 1 (depends on Level 0):
  - clusterops-workspace-rbac
  - clusterops-workspace-resourcequotas
  - clusterops-workspace-application-catalogs
  - clusterops-project-definitions
  - clusterops-sealed-secrets

Level 2 (depends on Level 1):
  - clusterops-clusters (depends on: workspaces + sealed-secrets)

Level 3 (depends on Level 2):
  - clusterops-workspace-applications (depends on: workspaces + clusters)

Level 4 (depends on Level 3):
  - clusterops-project-applications (depends on: project-definitions + workspace-applications)
```

**When adding new Kustomizations:**
- Always specify `dependsOn` in the Flux Kustomization spec
- Ensure dependencies are listed in the correct order
- Test dependency resolution before committing

### 3. Kustomize Patching Strategy

**JSON Patches (RFC 6902)** are used for cluster overlays, NOT strategic merge patches.

**Why?** Strategic merge patches replace entire nested objects. JSON patches surgically modify specific fields, preserving base fields like `imageRegistries`, `dns`, `users`.

**Example:**
```yaml
# overlays/2.17.0/kustomization.yaml
patches:
  - target:
      kind: Cluster
      name: dm-nkp-workload-1
    patch: |-
      - op: replace
        path: /spec/topology/class
        value: nkp-nutanix-v2.17.0-rc.4
      - op: add
        path: /spec/topology/workers/machineDeployments/0/replicas
        value: 3
```

### 4. Sealed Secrets

**CRITICAL SECURITY RULE**:
- **NEVER** commit plaintext passwords, credentials, tokens, or API keys
- **ALWAYS** use Sealed Secrets for sensitive data
- Sealed secrets are stored in `.../sealed-secrets/` directories
- The sealed-secrets controller private key backup is at `/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml` (NEVER commit this!)

**When creating secrets:**
1. Create plaintext secret locally (never commit)
2. Seal it using `kubeseal`
3. Commit only the SealedSecret YAML
4. Delete the plaintext secret immediately

### 5. Multi-Region/Multi-AZ Pattern

Each region and AZ is completely independent:
- Separate bootstrap files
- Separate Kustomizations
- Separate namespaces (if needed)
- Shared `_common` resources are referenced, not duplicated

**When adding a new region/AZ:**
1. Copy structure from an active AZ
2. Update ALL names, paths, and references
3. Regenerate sealed secrets for new clusters
4. Update bootstrap files with correct paths

---

## Common Tasks

### Adding a New Application

1. **Determine scope**: Platform-level (workspace) or project-level?
2. **Create application YAML** in appropriate directory:
   - Workspace: `workspaces/{workspace}/applications/{category}/{app-name}/`
   - Project: `workspaces/{workspace}/projects/{project}/applications/{category}/{app-name}/`
3. **Add to kustomization.yaml** in the parent directory
4. **Update Flux Kustomization** if needed (usually auto-discovered)

### Adding a New CAPI Cluster

1. **Choose provider**: `nutanix-infra`, `docker-infra`, `eks-infra`, etc.
2. **Create base cluster YAML** in `clusters/{provider}-infra/bases/`
3. **Create overlay** in `clusters/{provider}-infra/overlays/{version}/`
4. **Create sealed secrets** in `clusters/{provider}-infra/sealed-secrets/`
5. **Update kustomization.yaml** files
6. **Create workload cluster GitOps** folder: `workload-clusters/{cluster-name}/`

### Adding a New Policy

1. **Choose engine**: Gatekeeper or Kyverno
2. **Add ConstraintTemplate/Policy** to `_common/policies/{engine}/{category}/`
3. **Add Constraint/Policy** to `_common/policies/{engine}/constraints/{category}/` (Gatekeeper) or appropriate directory (Kyverno)
4. **Update kustomization.yaml** files
5. Policies are automatically applied to all clusters referencing `_common`

### Modifying Cluster Configuration

1. **Identify the cluster**: Check `clusters/{provider}-infra/` directories
2. **Find the base**: Usually in `bases/{cluster-name}.yaml`
3. **Modify via overlay**: Use JSON patches in `overlays/{version}/kustomization.yaml`
4. **Test locally**: `kustomize build overlays/{version}/`
5. **Validate**: `kustomize build overlays/{version}/ | kubectl apply --dry-run=server -f -`

---

## Security Guidelines

### Secrets Management

- ✅ **DO**: Use Sealed Secrets for all credentials
- ✅ **DO**: Store sealed secrets in `sealed-secrets/` directories
- ✅ **DO**: Reference the sealed-secrets controller key backup location when needed
- ❌ **DON'T**: Commit plaintext secrets
- ❌ **DON'T**: Commit the sealed-secrets private key
- ❌ **DON'T**: Store credentials in ConfigMaps

### Policy Enforcement

- Gatekeeper policies are defined in `_common/policies/gatekeeper/`
- Kyverno policies are defined in `_common/policies/kyverno/`
- Policies apply to all clusters by default
- System namespaces are excluded (see policy definitions)

### RBAC

- Global RBAC: `management-cluster/global/rbac/`
- Workspace RBAC: `workspaces/{workspace}/rbac/`
- See `docs/NKP-RBAC-GUIDE.md` for detailed RBAC patterns

---

## File Patterns

### Bootstrap Files

Bootstrap files create the initial Flux GitRepository and Kustomization:

```yaml
# GitRepository
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-{region}-{az}
  namespace: kommander  # or dm-nkp-gitops-workload for workload clusters

# Kustomization
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-{region}-{az}
  namespace: kommander
spec:
  path: ./region-{region}/az{n}/management-cluster
  dependsOn: [...]  # If dependencies exist
```

### Flux Kustomization Files

Flux Kustomizations (`flux-ks.yaml`) define what gets deployed:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-{category}
  namespace: dm-nkp-gitops-infra
spec:
  sourceRef:
    kind: GitRepository
    name: gitops-{region}-{az}
  path: ./region-{region}/az{n}/management-cluster/{path}
  dependsOn:
    - name: clusterops-{dependency}
  interval: 5m
  prune: true
```

### Kustomization Files

Standard Kustomize files (`kustomization.yaml`) list resources:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - resource1.yaml
  - resource2.yaml
patches:
  - patch: |-
      - op: replace
        path: /spec/someField
        value: newValue
```

---

## Debugging

### Quick Health Checks

```bash
# Check Flux Kustomizations
kubectl get kustomization -n dm-nkp-gitops-infra -o wide

# Check GitRepository
kubectl get gitrepository -n kommander

# Check Sealed Secrets
kubectl get sealedsecrets -n dm-dev-workspace

# Check CAPI Clusters
kubectl get clusters -A
```

### Common Issues

1. **Dependency not ready**: Check dependency Kustomization status
2. **Sealed secret not decrypting**: Verify sealed-secrets controller key matches
3. **Path not found**: Verify GitRepository is up to date and path exists
4. **Dry-run failed**: Check Cluster spec validity and required fields

See `docs/DEBUGGING-GITOPS.md` for comprehensive debugging guide.

---

## Important Paths and Locations

### Kubeconfig Files
- Management cluster: `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf`
- Workload cluster 1: `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig`
- Workload cluster 2: `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig`

### Sealed Secrets Key Backup
- Location: `/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml`
- **NEVER** commit this file
- Apply to clusters when sealed-secrets controller is installed

### Active Configuration
- **Region**: `region-usa`
- **AZ**: `az1`
- **Management Cluster**: `dm-nkp-mgmt-1`
- **Workspace**: `dm-dev-workspace`
- **Project**: `dm-dev-project`

---

## Scripts Reference

Key scripts in `scripts/`:

- `bootstrap-capd.sh`: Install CAPD provider for Docker clusters
- `bootstrap-capk.sh`: Install CAPK provider for Kubemark clusters
- `bootstrap-sealed-secrets-key-crs.sh`: Deploy sealed-secrets key via ClusterResourceSet
- `check-cluster-health.sh`: Health check for all clusters
- `check-violations.sh`: Check Gatekeeper policy violations
- `list-clusterapps-and-apps.sh`: List all ClusterApp and App CRs

See `scripts/README.md` for detailed usage.

---

## Documentation

- `README.md`: Main repository overview and quick start
- `docs/DEBUGGING-GITOPS.md`: Comprehensive GitOps debugging guide
- `docs/NKP-RBAC-GUIDE.md`: Complete RBAC guide for NKP
- `docs/SCALE-TESTING.md`: Scale testing documentation
- `region-{region}/az{n}/README.md`: Region/AZ specific docs
- `scripts/README.md`: Scripts documentation

---

## Best Practices

### When Making Changes

1. **Test locally first**: Use `kustomize build` to validate changes
2. **Check dependencies**: Ensure dependent Kustomizations are ready
3. **Validate YAML**: Use `kubectl apply --dry-run=server`
4. **Follow naming conventions**: Use consistent naming patterns
5. **Update documentation**: Keep README files current
6. **Commit atomic changes**: One logical change per commit

### When Adding Resources

1. **Use appropriate directory**: Follow the existing structure
2. **Update kustomization.yaml**: Add new resources to parent kustomization
3. **Consider dependencies**: Add `dependsOn` if needed
4. **Test in isolation**: Build and validate before committing
5. **Document changes**: Add comments or update README if needed

### When Troubleshooting

1. **Check Flux status first**: `kubectl get kustomization -A`
2. **Review logs**: Check Flux controller logs
3. **Verify GitRepository**: Ensure it's synced and up to date
4. **Check dependencies**: Verify all dependencies are ready
5. **Use debugging guide**: Refer to `docs/DEBUGGING-GITOPS.md`

---

## Common Mistakes to Avoid

1. ❌ **Forgetting dependencies**: Always specify `dependsOn` in Flux Kustomizations
2. ❌ **Using strategic merge for overlays**: Use JSON patches for cluster overlays
3. ❌ **Committing plaintext secrets**: Always use Sealed Secrets
4. ❌ **Breaking the dependency chain**: Don't create circular dependencies
5. ❌ **Modifying base files directly**: Use overlays for version-specific changes
6. ❌ **Forgetting to update kustomization.yaml**: Always add new resources to parent kustomization
7. ❌ **Hardcoding paths**: Use relative paths, not absolute
8. ❌ **Ignoring namespace conventions**: Use correct namespaces for each resource type

---

## Quick Reference

### Flux Commands

```bash
# Reconcile GitRepository
flux reconcile source git gitops-usa-az1 -n kommander

# Reconcile Kustomization
flux reconcile kustomization clusterops-clusters -n dm-nkp-gitops-infra

# Suspend reconciliation
flux suspend kustomization clusterops-clusters -n dm-nkp-gitops-infra

# Resume reconciliation
flux resume kustomization clusterops-clusters -n dm-nkp-gitops-infra
```

### Kustomize Commands

```bash
# Build kustomization
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0

# Validate with dry-run
kustomize build <path> | kubectl apply --dry-run=server -f -
```

### kubectl Shortcuts

```bash
# Get all Flux resources
kubectl get gitrepository,kustomization -A

# Watch Kustomizations
watch kubectl get kustomization -n dm-nkp-gitops-infra

# Check cluster status
kubectl get clusters -A -o wide
```

---

## Additional Context

### NKP/Kommander Concepts

- **Workspace**: Top-level organizational unit (like a tenant)
- **Project**: Sub-unit within a workspace (like a namespace)
- **Cluster**: Kubernetes cluster managed by NKP
- **Application**: App deployed via Kommander (ClusterApp or App CR)
- **VirtualGroup**: NKP RBAC group for workspace/project access

### CAPI Concepts

- **Cluster**: CAPI Cluster resource (declarative cluster definition)
- **Machine**: Individual node in a cluster
- **MachineDeployment**: Manages a set of machines
- **ClusterClass**: Template for cluster creation
- **Infrastructure Provider**: Provider-specific implementation (CAPX for Nutanix, CAPD for Docker)

---

## Questions?

- Check `docs/DEBUGGING-GITOPS.md` for troubleshooting
- Review `docs/NKP-RBAC-GUIDE.md` for RBAC questions
- See `scripts/README.md` for script usage
- Refer to main `README.md` for repository overview

