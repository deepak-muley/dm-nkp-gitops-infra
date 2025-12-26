# Scripts

Utility scripts for managing the NKP GitOps infrastructure.

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `sealed-secrets.sh` | Unified sealed-secrets management (backup, restore, encrypt, decrypt, re-encrypt, status) | `./scripts/sealed-secrets.sh <command>` |
| `bootstrap-capk.sh` | Install CAPK for Kubemark clusters | `./scripts/bootstrap-capk.sh mgmt` |
| `bootstrap-sealed-secrets-key-crs.sh` | Deploy sealed-secrets key via ClusterResourceSet | `./scripts/bootstrap-sealed-secrets-key-crs.sh` |
| `check-cluster-health.sh` | Check health of all NKP clusters | `./scripts/check-cluster-health.sh` |
| `check-violations.sh` | Check Gatekeeper policy violations | `./scripts/check-violations.sh mgmt` |
| `list-clusterapps-and-apps.sh` | List all ClusterApp and App CRs grouped by type | `./scripts/list-clusterapps-and-apps.sh` |
| `migrate-to-new-structure.sh` | Migrate repo structure safely | `./scripts/migrate-to-new-structure.sh` |

---

## bootstrap-sealed-secrets-key-crs.sh

Create a ClusterResourceSet to automatically deploy the sealed-secrets private key to all workload clusters.

### Why Is This Needed?

For SealedSecrets to work across multiple clusters, all clusters must share the same private key. This script:

1. **Reads** the sealed-secrets private key from a local file (NEVER stored in git!)
2. **Creates** a Kubernetes Secret in the management cluster containing the key
3. **Creates** a ClusterResourceSet that deploys the key to all matching workload clusters

### Security

⚠️ **IMPORTANT**: The private key is NEVER stored in git. The script reads it from:
```
/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml
```

This location is protected by `.gitignore` patterns to prevent accidental commits.

### Usage

```bash
# Apply to management cluster (uses default kubeconfig context)
./scripts/bootstrap-sealed-secrets-key-crs.sh

# Specify management cluster kubeconfig
./scripts/bootstrap-sealed-secrets-key-crs.sh -k /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Dry run (show what would be created without applying)
./scripts/bootstrap-sealed-secrets-key-crs.sh --dry-run

# Use a different key file location
./scripts/bootstrap-sealed-secrets-key-crs.sh -f /path/to/my-sealed-secrets-key.yaml

# Cleanup (remove the ClusterResourceSet and Secret)
./scripts/bootstrap-sealed-secrets-key-crs.sh --cleanup

# Help
./scripts/bootstrap-sealed-secrets-key-crs.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `-k, --kubeconfig PATH` | Path to kubeconfig file |
| `-f, --key-file PATH` | Path to sealed-secrets key backup (default: `/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml`) |
| `-n, --namespace NS` | Namespace for ClusterResourceSet (default: `dm-dev-workspace`) |
| `-d, --dry-run` | Show what would be created without applying |
| `-c, --cleanup` | Remove the ClusterResourceSet and Secret |
| `-h, --help` | Show help message |

### What Gets Created

The script creates two resources in the management cluster:

1. **Secret** (`sealed-secrets-key-resources`): Contains the sealed-secrets private key as YAML data
2. **ClusterResourceSet** (`sealed-secrets-key-crs`): Deploys the Secret content to matching clusters

### Cluster Selector

The ClusterResourceSet selects clusters with label:
```yaml
matchLabels:
  konvoy.d2iq.io/provider: nutanix
```

This automatically targets all Nutanix workload clusters.

### Verifying Deployment

After running the script:

```bash
# Check ClusterResourceSet status
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
  get clusterresourceset -n dm-dev-workspace

# Check ClusterResourceSetBindings (one per matching cluster)
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
  get clusterresourcesetbinding -n dm-dev-workspace

# Verify key was deployed to a workload cluster
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig \
  get secrets -n sealed-secrets-system -l sealedsecrets.bitnami.com/sealed-secrets-key
```

---

## bootstrap-capk.sh

Install Cluster API Provider Kubemark (CAPK) for creating hollow node clusters for scale testing.

### What is Kubemark?

Kubemark creates "hollow" nodes that simulate real Kubernetes nodes without actual compute resources. Each hollow node runs as a pod (~50Mi memory) inside the management cluster. This allows testing at scale (100s-1000s of nodes) without provisioning real infrastructure.

**Use Cases:**
- Scale testing (simulate 100-1000+ nodes)
- Performance benchmarking
- Testing cluster autoscaler behavior
- Validating controllers at scale
- Cost-effective load testing

### Usage

```bash
# Install CAPK on management cluster (default)
./scripts/bootstrap-capk.sh
./scripts/bootstrap-capk.sh mgmt

# Check CAPK installation status
./scripts/bootstrap-capk.sh --status mgmt

# Generate manifests for GitOps deployment (instead of direct install)
./scripts/bootstrap-capk.sh --generate-manifests

# Help
./scripts/bootstrap-capk.sh --help
```

### Installation Options

#### Option 1: Direct Installation (Recommended for first setup)

```bash
./scripts/bootstrap-capk.sh mgmt
```

This runs `clusterctl init --infrastructure kubemark` on your management cluster.

#### Option 2: GitOps Installation

```bash
# Generate manifests
./scripts/bootstrap-capk.sh --generate-manifests

# This creates:
# region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/kubemark-hollow-machines/capk-components.yaml

# Then uncomment capk-components.yaml in the kustomization.yaml and push to git
```

### After Installation

Once CAPK is installed, enable Kubemark cluster creation:

1. Edit `clusters/kustomization.yaml` and uncomment:
   ```yaml
   - kubemark-hollow-machines
   ```

2. Commit and push to git

3. Monitor cluster creation:
   ```bash
   kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
     get clusters -n dm-dev-workspace -w
   ```

### Kubeconfig Shortcuts

| Shortcut | Kubeconfig Path |
|----------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

---

## check-cluster-health.sh

Comprehensive health check for all NKP clusters (management and workload). Checks:
- Node status (Ready/NotReady)
- Pod health (Failed, Pending, CrashLoopBackOff, ImagePullBackOff)
- Flux Kustomizations status
- Flux HelmReleases status
- Flux GitRepositories status

### Usage

```bash
# Check all clusters (mgmt, workload1, workload2)
./scripts/check-cluster-health.sh

# Check specific cluster(s)
./scripts/check-cluster-health.sh mgmt
./scripts/check-cluster-health.sh workload1 workload2

# Summary only (no detailed problem lists)
./scripts/check-cluster-health.sh --summary

# Watch mode (refresh every 30 seconds)
./scripts/check-cluster-health.sh --watch

# Watch with custom interval
./scripts/check-cluster-health.sh --watch --interval 60

# Combine options
./scripts/check-cluster-health.sh --summary mgmt workload1

# Help
./scripts/check-cluster-health.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--summary, -s` | Show only summary table (no detailed problem lists) |
| `--watch, -w` | Continuously monitor (refreshes every 30s) |
| `--interval, -i N` | Set watch interval to N seconds (default: 30) |
| `--help, -h` | Show help message |

### Sample Output

```
╔══════════════════════════════════════════════════════════════════╗
║           NKP CLUSTER HEALTH CHECK                               ║
║           2024-12-17 10:30:45                                    ║
╚══════════════════════════════════════════════════════════════════╝

════════════════════════════════════════════════════════════════
  OVERALL HEALTH SUMMARY
════════════════════════════════════════════════════════════════

Cluster      | Nodes  | Pods   | KS   | HR   | GR   | HCP  | HRP  | AD   | ADI
-------------|--------|--------|------|------|------|------|------|------|-----
mgmt         | ✓      | ✓      | ✓    | ✓    | ✓    | ✓    | ✓    | ✓    | ✓
workload1    | ✓      | ✗      | ✓    | ✓    | ✓    | -    | -    | -    | -
workload2    | ✓      | ✓      | ✗    | ✓    | ✓    | -    | -    | -    | -

Legend: ✓ = Healthy, ✗ = Issues, - = N/A or Not Installed

Columns: KS=Kustomizations, HR=HelmReleases, GR=GitRepos, HCP=HelmChartProxies, HRP=HelmReleaseProxies,
         AD=AppDeployments, ADI=AppDeploymentInstances (HCP, HRP, AD, ADI are management cluster only)
```

### What It Checks

| Category | What's Checked | Clusters |
|----------|----------------|----------|
| **Nodes** | All nodes should be in Ready state | All |
| **Pods** | No Failed, Error, Pending, CrashLoopBackOff, or ImagePullBackOff pods | All |
| **Kustomizations (KS)** | All Flux Kustomizations should have Ready=True | All |
| **HelmReleases (HR)** | All Flux HelmReleases should have Ready=True | All |
| **GitRepositories (GR)** | All Flux GitRepositories should have Ready=True | All |
| **HelmChartProxies (HCP)** | All CAPI HelmChartProxies should have Ready=True | mgmt only |
| **HelmReleaseProxies (HRP)** | All CAPI HelmReleaseProxies should have Ready=True | mgmt only |
| **AppDeployments (AD)** | All Kommander AppDeployments should be synced to target clusters | mgmt only |
| **AppDeploymentInstances (ADI)** | All Kommander AppDeploymentInstances should have KustomizationReady=True and KustomizationHealthy=True | mgmt only |

### Kubeconfig Locations

| Cluster | Kubeconfig Path |
|---------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

---

## check-violations.sh

Check Gatekeeper policy violations across your NKP clusters with color-coded output.

### Usage

```bash
# Management cluster (default)
./scripts/check-violations.sh
./scripts/check-violations.sh mgmt

# Workload clusters
./scripts/check-violations.sh workload1
./scripts/check-violations.sh workload2

# Custom kubeconfig
./scripts/check-violations.sh /path/to/kubeconfig

# Summary only (no details)
./scripts/check-violations.sh --summary mgmt

# Filter by namespace
./scripts/check-violations.sh -n kube-system mgmt
./scripts/check-violations.sh --namespace kommander mgmt
./scripts/check-violations.sh -n flux-system workload1

# Combine options
./scripts/check-violations.sh --summary -n kommander mgmt

# Export to JSON file
./scripts/check-violations.sh --export mgmt

# Export violations for a specific namespace
./scripts/check-violations.sh --export -n dm-dev-workspace mgmt

# Help
./scripts/check-violations.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--summary` | Show only violation counts, skip detailed violations |
| `-n, --namespace NS` | Filter violations for a specific namespace |
| `--export` | Export violations to a JSON file |
| `--help` | Show help message |

### Output Sections

1. **Violations Summary** - All constraints with violation counts and severity
2. **By Namespace** - Which namespaces have the most violations (skipped when using `-n`)
3. **By Category** - Violations grouped by policy category (pod-security, rbac, etc.)
4. **Detailed Violations** - Specific resources violating each constraint (unless `--summary`)
5. **Quick Actions** - Helpful kubectl commands

### Understanding Detailed Violations

The detailed violations section shows exactly which resources are violating policies:

```
▶ block-privileged-containers                    ← Constraint name (policy violated)
  - kommander/Pod/rook-ceph-osd-3-64c56f849c-dd5p8    ← namespace/kind/resource-name
    → Privileged init container not allowed: activate  ← Why it's violating
```

| Component | Meaning |
|-----------|---------|
| **Constraint name** | The Gatekeeper policy that was violated |
| **Namespace** | Where the resource lives |
| **Kind** | The Kubernetes resource type (Pod, Deployment, Ingress, etc.) |
| **Resource name** | The specific resource violating the policy |
| **Message (→)** | The actual problem to fix |

### Sample Output

```
════════════════════════════════════════════════════════════════
  GATEKEEPER VIOLATIONS SUMMARY (namespace: kommander)
════════════════════════════════════════════════════════════════

Constraint                              | Violations | Severity
----------------------------------------|------------|----------
block-privileged-containers             | 20         | 🔴 CRITICAL
block-host-namespace                    | 18         | 🔴 CRITICAL
require-ingress-tls                     | 16         | 🟠 HIGH
...
----------------------------------------|------------|----------
TOTAL VIOLATIONS: 112
```

### Kubeconfig Shortcuts

The script knows your NKP kubeconfig locations:

| Shortcut | Kubeconfig Path |
|----------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

### Export to JSON

Generate a JSON report for further analysis or Jira tickets:

```bash
./scripts/check-violations.sh --export mgmt
# Creates: violations-report-20241214-200000.json

./scripts/check-violations.sh --export -n kommander mgmt
# Creates: violations-report-kommander-20241214-200000.json
```

### Advanced: Filter by Specific Component

For more granular filtering (specific pod, deployment, or resource), use kubectl + jq directly:

```bash
# Set kubeconfig first
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Violations for resources containing "rook-ceph" in kommander namespace
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $constraint |
  .status.violations[]? |
  select(.namespace == "kommander" and (.name | contains("rook-ceph"))) |
  "[\($constraint)] \(.namespace)/\(.kind)/\(.name)\n  → \(.message)\n"
'

# Violations for a specific pod
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select(.name == "my-pod-name-xyz") |
  "[\($c)] \(.kind)/\(.name): \(.message)"
'

# Only Ingress violations in a namespace
kubectl get constraints -o json | jq -r '
  .items[].status.violations[]? |
  select(.namespace == "kommander" and .kind == "Ingress") |
  "\(.kind)/\(.name): \(.message)"
'

# Violations for grafana components
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select(.namespace == "kommander" and (.name | contains("grafana"))) |
  "[\($c)] \(.kind)/\(.name)\n  → \(.message)\n"
'

# Violations for prometheus node-exporter
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select((.name | contains("node-exporter"))) |
  "[\($c)] \(.namespace)/\(.kind)/\(.name)\n  → \(.message)\n"
'
```

### jq Filter Quick Reference

| Filter By | jq Selection |
|-----------|--------------|
| Namespace | `select(.namespace == "kommander")` |
| Resource name contains | `select(.name \| contains("grafana"))` |
| Exact resource name | `select(.name == "my-pod-xyz")` |
| Resource kind | `select(.kind == "Ingress")` |
| Combine filters | `select(.namespace == "X" and .kind == "Y")` |

---

## list-clusterapps-and-apps.sh

List all ClusterApp and App custom resources from the management cluster, grouped by type with display names and scope information. Features beautiful colored terminal output and powerful filtering options.

### Usage

```bash
# Set kubeconfig to management cluster
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# List all resources
./scripts/list-clusterapps-and-apps.sh

# Filter by kind
./scripts/list-clusterapps-and-apps.sh --kind ClusterApp
./scripts/list-clusterapps-and-apps.sh --kind App

# Filter by scope
./scripts/list-clusterapps-and-apps.sh --scope workspace
./scripts/list-clusterapps-and-apps.sh --scope project

# Search by name (partial match, case-insensitive)
./scripts/list-clusterapps-and-apps.sh --name insights
./scripts/list-clusterapps-and-apps.sh --name kserve

# Filter by namespace (for App resources)
./scripts/list-clusterapps-and-apps.sh --namespace kommander-default-workspace

  # Filter by type
  ./scripts/list-clusterapps-and-apps.sh --type nkp-core-platform
  ./scripts/list-clusterapps-and-apps.sh --type custom

  # Filter by licensing
  ./scripts/list-clusterapps-and-apps.sh --licensing ultimate
  ./scripts/list-clusterapps-and-apps.sh --licensing pro

  # Filter by dependencies
  ./scripts/list-clusterapps-and-apps.sh --dependencies cert-manager
  ./scripts/list-clusterapps-and-apps.sh --dependencies traefik

  # Check deployment status (AppDeployment and AppDeploymentInstance)
  ./scripts/list-clusterapps-and-apps.sh --check-deployments
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --name cert-manager
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --kind ClusterApp

  # Combine multiple filters
  ./scripts/list-clusterapps-and-apps.sh --kind App --scope workspace --name kserve
  ./scripts/list-clusterapps-and-apps.sh --kind ClusterApp --type nkp-core-platform --scope workspace
  ./scripts/list-clusterapps-and-apps.sh --licensing ultimate --dependencies cert-manager
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --name cert-manager --scope workspace

  # Show only summary statistics
  ./scripts/list-clusterapps-and-apps.sh --summary

  # Disable colored output
  ./scripts/list-clusterapps-and-apps.sh --no-color

  # Show help
  ./scripts/list-clusterapps-and-apps.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--kind KIND` | Filter by kind (ClusterApp or App) |
| `--scope SCOPE` | Filter by scope (workspace or project) |
| `--name PATTERN` | Filter by name (partial match, case-insensitive) |
| `--namespace NS` | Filter by namespace (for App resources) |
| `--type TYPE` | Filter by type (custom, internal, nkp-catalog, nkp-core-platform) |
| `--licensing PATTERN` | Filter by licensing (partial match, e.g., "pro", "ultimate") |
| `--dependencies PATTERN` | Filter by dependencies (partial match, e.g., "cert-manager") |
| `--check-deployments` | Show AppDeployment status and cluster deployment information |
| `--no-color` | Disable colored output |
| `--summary` | Show only summary statistics (no detailed tables) |
| `-h, --help` | Show help message |

### Requirements

- `kubectl` - Must be installed and configured
- `jq` - JSON processor (install via `brew install jq` on macOS)
- `KUBECONFIG` environment variable set to management cluster kubeconfig

### Output

The script generates beautifully formatted tables with color-coded output:

- **Blue** - ClusterApp resources
- **Green** - App resources
- **Yellow** - Workspace scope
- **Magenta** - Project scope
- **Cyan** - Section headers

Tables are grouped by application type:

- **custom** - Custom applications
- **internal** - Internal Kommander applications
- **nkp-catalog** - Applications from NKP catalog
- **nkp-core-platform** - Core NKP platform applications

Each table includes:
- **Kind** - ClusterApp or App (color-coded)
- **Name** - Resource name
- **Version** - Application version
- **Display Name** - Human-readable name from annotations
- **Scope** - Workspace or project scope (color-coded)
- **Type** - Application type (custom, internal, nkp-catalog, nkp-core-platform)
- **Licensing** - Required licensing tiers (e.g., "pro,ultimate,essential,enterprise")
- **Dependencies** - Required dependencies (e.g., "cert-manager", "traefik")

When using `--check-deployments`, additional deployment information is shown:
- **Enabled Status** - Whether an AppDeployment exists (✓ Enabled or ○ Not enabled)
- **Target Clusters** - List of clusters where the app is configured to be deployed
- **Deployment Status** - Summary of healthy/total instances (e.g., "2/2 Healthy")
- **Instance Details** - Per-cluster status showing which clusters have successfully deployed instances (✓ = healthy, ○ = not healthy)

The output also includes a summary section with statistics:
- Total resource count
- Breakdown by type
- Breakdown by kind
- Breakdown by scope

### Sample Output

```
════════════════════════════════════════════════════════════════
  ClusterApp and App Resources
════════════════════════════════════════════════════════════════

Active Filters:
  Kind: App
  Scope: workspace
  Type: nkp-catalog

════════════════════════════════════════════════════════════════
  Type: nkp-catalog | Kind: App | Count: 5
════════════════════════════════════════════════════════════════

┌─────────────┬──────────────────────────────────────────┬─────────────┬──────────────────────────────────────┬────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
│ Kind        │ Name                                     │ Version     │ Display Name                         │ Scope      │ Licensing                            │ Dependencies                         │
├─────────────┼──────────────────────────────────────────┼─────────────┼──────────────────────────────────────┼────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
│ App         │ envoy-gateway-1.5.0                      │ 1.5.0       │ Envoy Gateway                        │ workspace  │ pro,ultimate,Essential,Enterprise    │ cert-manager                         │
│ App         │ kserve-0.15.0                            │ 0.15.0      │ Kserve                               │ workspace  │ pro,ultimate,Essential,Enterprise    │ cert-manager                         │
...
└─────────────┴──────────────────────────────────────────┴─────────────┴──────────────────────────────────────┴────────────┴──────────────────────────────────────┴──────────────────────────────────────┘

════════════════════════════════════════════════════════════════
  Summary Statistics
════════════════════════════════════════════════════════════════

Total Resources: 5

By Type:
  nkp-catalog         :   5

By Kind:
  App                 :   5

By Scope:
  workspace           :   5
```

### Use Cases

- **Audit applications** - See all available ClusterApps and Apps with beautiful formatting
- **Version tracking** - Check versions of deployed applications
- **Scope analysis** - Understand which apps are workspace vs project scoped
- **Type categorization** - Group applications by their type (custom, internal, catalog, platform)
- **Quick searches** - Find specific applications by name pattern
- **Namespace filtering** - See which Apps are in specific namespaces
- **Licensing analysis** - Find apps by required licensing tiers
- **Dependency tracking** - Identify apps that require specific dependencies (e.g., cert-manager, traefik)
- **Reporting** - Generate summary statistics for documentation

---

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
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

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
├── management-cluster/           # Management cluster resources
│   ├── bootstrap.yaml
│   ├── global/
│   │   └── sealed-secrets-controller/
│   ├── namespaces/
│   └── workspaces/
│       └── dm-dev-workspace/
│           ├── clusters/         # CAPI cluster definitions
│           ├── applications/
│           └── projects/
│
└── workload-clusters/            # Resources deployed INSIDE workload clusters
    ├── _base/
    │   └── infrastructure/
    │       └── sealed-secrets-controller/
    ├── dm-nkp-workload-1/
    │   ├── bootstrap.yaml        # Apply to workload cluster
    │   ├── infrastructure/
    │   │   └── sealed-secrets/
    │   └── apps/
    └── dm-nkp-workload-2/
        ├── bootstrap.yaml
        ├── infrastructure/
        │   └── sealed-secrets/
        └── apps/
```

The Flux Kustomization path changed from `./region-usa/az1` to `./region-usa/az1/management-cluster`.

Without disabling pruning first, Flux would see the old path as empty and **delete all resources** including your clusters!

### Bootstrapping Workload Clusters

After migration, bootstrap workload clusters (Flux is already installed by NKP):

```bash
# dm-nkp-workload-1
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml

# dm-nkp-workload-2
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml
```

---

## sealed-secrets.sh

Unified script for managing sealed-secrets operations: backup, restore, encrypt, decrypt, re-encrypt, and status checking.

### Why Is This Needed?

Sealed-secrets keys are critical for decrypting sealed secrets. This unified script provides all necessary operations:
- **Backup**: Save keys for disaster recovery
- **Restore**: Restore keys from backup
- **Encrypt**: Create new sealed secrets
- **Decrypt**: View plaintext secrets (requires keys)
- **Re-encrypt**: Fix decryption failures by re-encrypting with current keys
- **Status**: Check sealed secret sync status

### Security

⚠️ **IMPORTANT**: Both public and private keys are stored locally and NEVER committed to git. They are stored in:
```
/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml (private keys)
/Users/deepak.muley/ws/nkp/sealed-secrets-public-key.pem (public key)
```

These locations are protected by `.gitignore` patterns.

### Usage

```bash
# Show help
./scripts/sealed-secrets.sh --help

# Backup keys
./scripts/sealed-secrets.sh backup

# Restore keys
./scripts/sealed-secrets.sh restore

# Encrypt a secret
./scripts/sealed-secrets.sh encrypt -f secret.yaml -o sealed-secret.yaml

# Decrypt a sealed secret (requires keys)
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -o secret.yaml

# Re-encrypt secrets with current credentials
./scripts/sealed-secrets.sh re-encrypt

# Check status of sealed secrets
./scripts/sealed-secrets.sh status
```

### Commands

#### Backup

Backup sealed-secrets controller keys (public & private):

```bash
./scripts/sealed-secrets.sh backup
./scripts/sealed-secrets.sh backup -k /path/to/kubeconfig
./scripts/sealed-secrets.sh backup --help
```

#### Restore

Restore sealed-secrets keys from backup:

```bash
./scripts/sealed-secrets.sh restore
./scripts/sealed-secrets.sh restore -b /path/to/backup.yaml
./scripts/sealed-secrets.sh restore --force
./scripts/sealed-secrets.sh restore --help
```

#### Encrypt

Encrypt a plaintext Kubernetes Secret:

```bash
./scripts/sealed-secrets.sh encrypt -f secret.yaml -o sealed-secret.yaml
./scripts/sealed-secrets.sh encrypt -f secret.yaml -n my-namespace -o sealed-secret.yaml
./scripts/sealed-secrets.sh encrypt --help
```

#### Decrypt

Decrypt a SealedSecret (requires private keys):

```bash
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -o secret.yaml
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -b /path/to/backup.yaml -o secret.yaml
./scripts/sealed-secrets.sh decrypt --help
```

#### Re-encrypt

Re-encrypt secrets with new credentials. Automatically reads credentials from:
- PC credentials: `/Users/deepak.muley/ws/nkp/pc-creds.sh`
- DockerHub credentials: `/Users/deepak.muley/ws/nkp/nkp-mgmt-clusterctl.sh`

```bash
./scripts/sealed-secrets.sh re-encrypt
./scripts/sealed-secrets.sh re-encrypt -n dm-dev-workspace
./scripts/sealed-secrets.sh re-encrypt --help
```

This command:
1. Reads PC and DockerHub credentials from local files
2. Re-encrypts all 4 secrets using the current controller's public key:
   - `dm-dev-pc-credentials` (Prism Central JSON format)
   - `dm-dev-image-registry-credentials` (DockerHub)
   - `dm-dev-pc-credentials-for-csi` (Prism Central for CSI)
   - `dm-dev-pc-credentials-for-konnector-agent` (Prism Central for Konnector)
3. Applies the re-encrypted secrets to the cluster
4. Verifies they can be decrypted
5. Updates the sealed secrets file in git

#### Status

Check the sync status of sealed secrets:

```bash
./scripts/sealed-secrets.sh status
./scripts/sealed-secrets.sh status -n dm-dev-workspace
./scripts/sealed-secrets.sh status --help
```
