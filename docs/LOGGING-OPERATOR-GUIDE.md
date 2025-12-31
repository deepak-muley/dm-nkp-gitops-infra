# Logging Operator Guide

This document provides comprehensive guidance on the Logging Operator setup, current management cluster configuration, and how to configure logging for workload clusters.

## Table of Contents

1. [How Logging Operator Works](#how-logging-operator-works)
2. [Current Management Cluster Configuration](#current-management-cluster-configuration)
3. [Configuring Logging for Workload Cluster 1](#configuring-logging-for-workload-cluster-1)

---

## How Logging Operator Works

The Logging Operator (from [kube-logging.dev](https://kube-logging.dev/docs/)) automates the deployment and configuration of a Kubernetes logging pipeline. It simplifies log collection, processing, and forwarding within Kubernetes environments.

### Architecture Overview

The Logging Operator uses a three-tier architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    Logging Operator                          │
│              (Custom Resource Controller)                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Manages
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Tier 1: Log Collector (Fluent Bit)                         │
│  - Deployed as DaemonSet on each node                       │
│  - Collects logs from /var/log/containers/*.log             │
│  - Enriches logs with Kubernetes metadata (labels,          │
│    annotations, pod info) via Kubernetes API                │
│  - Forwards logs to Tier 2                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Forwards logs
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Tier 2: Log Forwarder (Fluentd or syslog-ng)              │
│  - Receives logs from Fluent Bit                            │
│  - Processes logs (filtering, transformation, enrichment)    │
│  - Routes logs based on Flow/ClusterFlow rules              │
│  - Forwards to Tier 3 (Output destinations)                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Routes via Flow/ClusterFlow
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Tier 3: Output Destinations                                │
│  - Loki, Elasticsearch, S3, Kafka, etc.                     │
│  - Defined via Output/ClusterOutput CRDs                    │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. Logging CRD
The `Logging` custom resource defines the overall logging infrastructure:
- **Fluent Bit configuration**: Collector settings, image, resources, TLS
- **Fluentd/syslog-ng configuration**: Forwarder settings, buffer storage, resources
- **Control namespace**: Where the operator manages resources
- **Watch namespaces**: Which namespaces to monitor (use `*` for all)

#### 2. Flow and ClusterFlow CRDs
These resources define **how logs are filtered and routed**:
- **Flow**: Namespace-scoped, applies to logs from pods in that namespace
- **ClusterFlow**: Cluster-scoped, applies to logs from all namespaces
- **Selectors**: Filter logs based on labels, namespaces, or other criteria
- **OutputRefs**: Reference Output/ClusterOutput resources to route logs

#### 3. Output and ClusterOutput CRDs
These resources define **where logs are sent**:
- **Output**: Namespace-scoped output destination
- **ClusterOutput**: Cluster-scoped output destination
- **Supported backends**: Loki, Elasticsearch, S3, Kafka, HTTP, etc.
- **Buffer configuration**: Retry logic, flush intervals, buffer size

### Log Flow Example

1. **Application writes logs** → Container runtime writes to `/var/log/containers/*.log`
2. **Fluent Bit collects** → DaemonSet reads log files, enriches with K8s metadata
3. **Fluent Bit forwards** → Sends logs to Fluentd (or syslog-ng) via forward protocol
4. **Fluentd processes** → Applies Flow/ClusterFlow filters and transformations
5. **Fluentd routes** → Sends logs to Output/ClusterOutput destinations (e.g., Loki)
6. **Loki stores** → Logs are stored and indexed for querying

### Key Features

- **Automatic log collection**: No manual configuration needed per pod
- **Kubernetes metadata enrichment**: Automatic addition of pod labels, annotations, namespace info
- **Flexible routing**: Route logs based on labels, namespaces, or log content
- **Multiple outputs**: Send logs to multiple destinations simultaneously
- **Buffer management**: Handle backpressure and retry failed deliveries
- **TLS encryption**: Secure communication between components

---

## Current Management Cluster Configuration

### Overview

The management cluster (`dm-nkp-mgmt-1`) has the Logging Operator installed with **Ultimate License** enabled. The configuration is managed via Kommander AppDeployments.

### Current Setup

#### 1. Logging Operator Installation

**Location**: `kommander` namespace
**AppDeployment**: `project-logging` in `dm-dev-project` namespace
**ClusterApp**: `project-logging-1.0.4`
**Target Cluster**: `host-cluster` (management cluster)

#### 2. Logging Infrastructure (Logging CR)

**Resource**: `Logging` CR named `logging-operator-logging`
**Namespace**: `kommander`
**Control Namespace**: `kommander`
**Watch Namespaces**: `*` (all namespaces)

**Fluent Bit Configuration**:
- **Image**: `ghcr.io/fluent/fluent-bit:4.1.1`
- **Collects from**: `/var/log/containers/*.log`
- **Parser**: `cri` (Container Runtime Interface)
- **Resources**:
  - Requests: 350m CPU, 350Mi memory
  - Limits: 750Mi memory
- **TLS**: Enabled with secret `logging-operator-logging-fluentbit-tls`
- **Metrics**: Exposed on port 2020 at `/api/v1/metrics/prometheus`

**Fluentd Configuration**:
- **Image**: `ghcr.io/kube-logging/logging-operator/fluentd:6.0.3-full`
- **Replicas**: 1 (StatefulSet)
- **Buffer Storage**: 10Gi PVC (`fluentd-buffer`)
- **Resources**:
  - Requests: 500m CPU, 100Mi memory
  - Limits: 1000m CPU, 1Gi memory
- **TLS**: Enabled with secret `logging-operator-logging-fluentd-tls`
- **Metrics**: Exposed on port 24231 at `/metrics`

#### 3. Log Routing (ClusterFlow)

**Resource**: `ClusterFlow` named `cluster-containers`
**Namespace**: `kommander`
**Status**: Active

```yaml
spec:
  globalOutputRefs:
  - loki
```

**Behavior**: Routes **all container logs** from all namespaces to the `loki` ClusterOutput.

#### 4. Log Destination (ClusterOutput)

**Resource**: `ClusterOutput` named `loki`
**Namespace**: `kommander`
**Status**: Active

**Configuration**:
```yaml
spec:
  loki:
    url: http://grafana-loki-loki-distributed-gateway.kommander.svc.cluster.local:80
    buffer:
      flush_interval: 10s
      flush_mode: interval
      flush_thread_count: 8
      retry_forever: false
      retry_max_times: 5
    configure_kubernetes_labels: true
    extract_kubernetes_labels: true
    extra_labels:
      log_source: kubernetes_container
```

**Target**: Loki service at `grafana-loki-loki-distributed-gateway.kommander.svc.cluster.local:80`

#### 5. Loki Installation

**Location**: `kommander` namespace
**AppDeployment**: `project-grafana-loki` in `dm-dev-project` namespace
**ClusterApp**: `project-grafana-loki-0.80.5`
**Target Cluster**: `host-cluster` (management cluster)
**ConfigMap Overrides**: `project-grafana-loki-overrides` (resource limits, ingestion limits)

### Current Log Flow on Management Cluster

```
┌─────────────────────────────────────────────────────────────┐
│  All Pods in All Namespaces                                 │
│  └─> Container logs written to /var/log/containers/*.log   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Fluent Bit DaemonSet (on each node)                        │
│  - Collects logs from /var/log/containers/*.log            │
│  - Enriches with Kubernetes metadata                        │
│  - Forwards to Fluentd                                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Fluentd StatefulSet (1 replica)                           │
│  - Receives logs from Fluent Bit                            │
│  - Applies ClusterFlow: cluster-containers                 │
│  - Routes all logs to loki ClusterOutput                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  ClusterOutput: loki                                        │
│  - Sends logs to Loki gateway                               │
│  - URL: grafana-loki-loki-distributed-gateway.kommander    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Grafana Loki (Distributed Mode)                            │
│  - Stores logs in kommander namespace                       │
│  - Queryable via Grafana                                    │
└─────────────────────────────────────────────────────────────┘
```

### Summary

- **Source**: All container logs from all namespaces, collected by Fluent Bit DaemonSets
- **Processing**: Fluentd StatefulSet processes and routes logs
- **Target**: Loki distributed deployment in `kommander` namespace
- **Routing**: ClusterFlow `cluster-containers` routes all logs to ClusterOutput `loki`

---

## Configuring Logging for Workload Cluster 1

This section describes how to configure the Logging Operator on workload cluster 1 (`dm-nkp-workload-1`) to collect logs from a new application and forward them to Loki.

### Prerequisites

1. **Workload cluster 1 is running and accessible**
   - Kubeconfig: `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig`
   - Verify: `kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig get nodes`

2. **Kommander access to workload cluster 1**
   - Cluster should be attached to Kommander
   - Cluster name: `dm-nkp-workload-1`

3. **GitOps infrastructure ready**
   - Bootstrap should be applied (see `workload-clusters/dm-nkp-workload-1/bootstrap.yaml`)

### Step-by-Step Configuration

#### Step 1: Deploy Logging Operator on Workload Cluster 1

**Option A: Via Kommander AppDeployment (Recommended)**

Create an AppDeployment in the management cluster that targets workload cluster 1:

**File**: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/applications/platform-applications/workload-logging/workload-logging.yaml`

```yaml
apiVersion: apps.kommander.d2iq.io/v1alpha3
kind: AppDeployment
metadata:
  name: workload-logging
  namespace: dm-dev-project
spec:
  appRef:
    kind: ClusterApp
    name: project-logging-1.0.4  # Same ClusterApp as management cluster
  clusterConfigOverrides:
    - appVersion: 1.0.4
      clusterSelector:
        matchExpressions:
          - key: kommander.d2iq.io/cluster-name
            operator: In
            values:
              - dm-nkp-workload-1  # Target workload cluster 1
      configMapName: ""
```

**Option B: Manual Installation**

If not using Kommander, install the Logging Operator manually:

```bash
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig

# Install via Helm (example)
helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
helm install logging-operator banzaicloud-stable/logging-operator \
  --namespace kommander \
  --create-namespace
```

#### Step 2: Create Logging Infrastructure Resource

Create a `Logging` CR to define the logging infrastructure on workload cluster 1.

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/logging.yaml`

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: workload-logging
  namespace: kommander  # Control namespace
spec:
  controlNamespace: kommander
  watchNamespaces:
    - '*'  # Watch all namespaces
  fluentbit:
    image:
      repository: ghcr.io/fluent/fluent-bit
      tag: 4.1.1
    inputTail:
      Path: /var/log/containers/*.log
      Parser: cri
      DB: /tail-db/kubernetes.db
      Mem_Buf_Limit: 5MB
      Refresh_Interval: "5"
      Rotate_Wait: "5"
      Skip_Long_Lines: "On"
      Tag: kubernetes.*
    filterKubernetes:
      Kube_URL: https://kubernetes.default.svc:443
      Kube_Tag_Prefix: kubernetes.var.log.containers
      Kube_CA_File: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      Kube_Token_File: /var/run/secrets/kubernetes.io/serviceaccount/token
      K8S-Logging.Exclude: "Off"
      K8S-Logging.Parser: "Off"
      Labels: "On"
      Annotations: "On"
      Merge_Log: "On"
      Keep_Log: "Off"
      K8S-Logging.Parser.Exclude: "Off"
      tls.verify: "On"
    resources:
      requests:
        cpu: 350m
        memory: 350Mi
      limits:
        memory: 750Mi
    metrics:
      port: 2020
      path: /api/v1/metrics/prometheus
      prometheusAnnotations: true
    tls:
      enabled: true
      secretName: workload-logging-fluentbit-tls
  fluentd:
    image:
      repository: ghcr.io/kube-logging/logging-operator/fluentd
      tag: 6.0.3-full
    scaling:
      replicas: 1
    bufferStorageVolume:
      pvc:
        source:
          claimName: fluentd-buffer
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
          volumeMode: Filesystem
    resources:
      requests:
        cpu: 500m
        memory: 100Mi
      limits:
        cpu: 1000m
        memory: 1Gi
    metrics:
      port: 24231
      path: /metrics
      prometheusAnnotations: true
    tls:
      enabled: true
      secretName: workload-logging-fluentd-tls
```

#### Step 3: Deploy Loki on Workload Cluster 1

**Option A: Via Kommander AppDeployment (Recommended)**

Create an AppDeployment for Loki:

**File**: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/applications/platform-applications/workload-grafana-loki/workload-grafana-loki.yaml`

```yaml
apiVersion: apps.kommander.d2iq.io/v1alpha3
kind: AppDeployment
metadata:
  name: workload-grafana-loki
  namespace: dm-dev-project
spec:
  appRef:
    kind: ClusterApp
    name: project-grafana-loki-0.80.5
  clusterConfigOverrides:
    - appVersion: 0.80.5
      clusterSelector:
        matchExpressions:
          - key: kommander.d2iq.io/cluster-name
            operator: In
            values:
              - dm-nkp-workload-1
      configMapName: workload-grafana-loki-overrides
```

**Option B: Manual Installation**

Install Loki via Helm or other methods. Ensure Loki is accessible at a service endpoint.

#### Step 4: Create ClusterOutput for Loki

Define where logs should be sent (Loki endpoint).

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/clusteroutput-loki.yaml`

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
  name: loki
  namespace: kommander
spec:
  loki:
    url: http://grafana-loki-loki-distributed-gateway.kommander.svc.cluster.local:80
    buffer:
      flush_interval: 10s
      flush_mode: interval
      flush_thread_count: 8
      retry_forever: false
      retry_max_times: 5
    configure_kubernetes_labels: true
    extract_kubernetes_labels: true
    extra_labels:
      log_source: kubernetes_container
      cluster: dm-nkp-workload-1
```

**Note**: Adjust the `url` based on your Loki service name and namespace. If Loki is in a different namespace, update accordingly.

#### Step 5: Create ClusterFlow to Route All Logs to Loki

Route all container logs to the Loki output.

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/clusterflow-all-logs.yaml`

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: cluster-containers
  namespace: kommander
spec:
  globalOutputRefs:
    - loki
```

#### Step 6: (Optional) Create Namespace-Specific Flow for Your Application

If you want to route logs from a specific application differently, create a Flow in that namespace.

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/flow-app-logs.yaml`

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: app-logs
  namespace: your-app-namespace  # Replace with your app namespace
spec:
  match:
    - select:
        labels:
          app: your-app-label  # Replace with your app label
  localOutputRefs:
    - loki  # Reference the ClusterOutput
```

**Note**: If using a ClusterOutput, you can reference it in `globalOutputRefs` instead of `localOutputRefs`.

#### Step 7: Update Kustomization Files

Add the logging resources to your GitOps kustomization.

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - logging/kustomization.yaml
  # ... other resources
```

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - logging.yaml
  - clusteroutput-loki.yaml
  - clusterflow-all-logs.yaml
  # - flow-app-logs.yaml  # Uncomment if using namespace-specific flow
```

### Verification Steps

1. **Check Logging Operator is installed**:
```bash
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
kubectl get logging -n kommander
```

2. **Check Fluent Bit DaemonSet**:
```bash
kubectl get daemonset -n kommander | grep fluent-bit
kubectl get pods -n kommander | grep fluent-bit
```

3. **Check Fluentd StatefulSet**:
```bash
kubectl get statefulset -n kommander | grep fluentd
kubectl get pods -n kommander | grep fluentd
```

4. **Check Flow and Output resources**:
```bash
kubectl get clusterflow,clusteroutput -n kommander
kubectl get flow -A
```

5. **Check Loki is running**:
```bash
kubectl get pods -n kommander | grep loki
kubectl get svc -n kommander | grep loki
```

6. **Verify logs are flowing**:
```bash
# Check Fluentd logs
kubectl logs -n kommander -l app.kubernetes.io/name=fluentd --tail=50

# Check if logs are reaching Loki
# Query Loki via Grafana or Loki API
```

### Troubleshooting

#### Fluent Bit not collecting logs
- Check DaemonSet is running on all nodes: `kubectl get pods -n kommander -l app.kubernetes.io/name=fluent-bit -o wide`
- Check node file system access: Ensure `/var/log/containers` is accessible
- Check Fluent Bit logs: `kubectl logs -n kommander -l app.kubernetes.io/name=fluent-bit`

#### Fluentd not receiving logs
- Check Fluentd StatefulSet is running: `kubectl get statefulset -n kommander`
- Check Fluentd logs: `kubectl logs -n kommander -l app.kubernetes.io/name=fluentd`
- Verify TLS configuration matches between Fluent Bit and Fluentd

#### Logs not reaching Loki
- Verify Loki service is accessible: `kubectl get svc -n kommander | grep loki`
- Check ClusterOutput URL is correct
- Check Fluentd logs for connection errors
- Verify network policies allow traffic to Loki

#### Flow/Output not active
- Check resource status: `kubectl describe clusterflow cluster-containers -n kommander`
- Check for validation errors: `kubectl get clusterflow cluster-containers -n kommander -o yaml`
- Verify Logging CR is in the same control namespace

### Summary

To enable logging for a new application on workload cluster 1:

1. ✅ Deploy Logging Operator (via Kommander AppDeployment or manually)
2. ✅ Create `Logging` CR to define infrastructure
3. ✅ Deploy Loki (via Kommander AppDeployment or manually)
4. ✅ Create `ClusterOutput` pointing to Loki
5. ✅ Create `ClusterFlow` to route logs to the output
6. ✅ (Optional) Create namespace-specific `Flow` for application-specific routing
7. ✅ Add resources to GitOps kustomization
8. ✅ Verify all components are running and logs are flowing

Once configured, all container logs from workload cluster 1 will be:
- Collected by Fluent Bit DaemonSets
- Processed by Fluentd
- Routed via ClusterFlow to Loki
- Stored and queryable in Loki

---

## RBAC (Role-Based Access Control) for Logging Operator

This section covers the RBAC setup required for the Logging Operator at both the management cluster level and project level.

### Overview

The Logging Operator requires several RBAC resources to function:
- **ClusterRoles**: Define permissions for cluster-scoped operations
- **ClusterRoleBindings**: Bind service accounts to ClusterRoles
- **Roles**: Define permissions for namespace-scoped operations
- **RoleBindings**: Bind service accounts to Roles

Additionally, you may want to grant users permissions to manage logging resources (Flow, Output, etc.) at the project level.

### Management Cluster RBAC

#### System-Level RBAC (Auto-Created by Logging Operator)

The Logging Operator automatically creates the following RBAC resources when deployed:

##### 1. Logging Operator Controller RBAC

**ClusterRole**: `logging-operator`
- **Purpose**: Permissions for the Logging Operator controller to manage logging resources
- **Bound to**: `logging-operator` service account in `kommander` namespace
- **Key Permissions**:
  - Full CRUD on Logging Operator CRDs (Logging, Flow, ClusterFlow, Output, ClusterOutput, etc.)
  - Create/manage DaemonSets, StatefulSets, Deployments
  - Create/manage ConfigMaps, Secrets, Services, PVCs
  - Create/manage RBAC resources (Roles, RoleBindings, ClusterRoles, ClusterRoleBindings)
  - Read nodes, namespaces, pods for metadata enrichment
  - Manage Prometheus ServiceMonitors and PrometheusRules

**ClusterRoleBinding**: `logging-operator`
- Binds `logging-operator` service account to `logging-operator` ClusterRole

##### 2. Fluent Bit RBAC

**ClusterRole**: `logging-operator-logging-fluentbit`
- **Purpose**: Permissions for Fluent Bit DaemonSet pods to read Kubernetes metadata
- **Bound to**: Fluent Bit DaemonSet service account
- **Key Permissions**:
  - `get`, `list`, `watch` on `pods` (to enrich logs with pod metadata)
  - `get`, `list`, `watch` on `namespaces` (to enrich logs with namespace info)

**ClusterRoleBinding**: `logging-operator-logging-fluentbit`
- Binds Fluent Bit service account to `logging-operator-logging-fluentbit` ClusterRole

##### 3. Fluentd RBAC

**ClusterRole**: `logging-operator-logging-fluentd`
- **Purpose**: Permissions for Fluentd StatefulSet pods to read Kubernetes resources
- **Bound to**: Fluentd StatefulSet service account
- **Key Permissions**:
  - `get`, `list`, `watch` on `pods`, `nodes`, `endpoints`, `services`, `configmaps`, `events`
  - `get`, `list`, `watch` on `daemonsets`, `deployments`, `replicasets`, `statefulsets`
  - Read events from `events.k8s.io` API group

**ClusterRoleBinding**: `logging-operator-logging-fluentd`
- Binds Fluentd service account to `logging-operator-logging-fluentd` ClusterRole

**Role**: `logging-operator-logging-fluentd` (in `kommander` namespace)
- **Purpose**: Namespace-specific permissions for Fluentd
- **Key Permissions**:
  - Full CRUD on `configmaps` and `secrets` in the control namespace
  - Used for storing Fluentd configuration and TLS certificates

**RoleBinding**: `logging-operator-logging-fluentd` (in `kommander` namespace)
- Binds Fluentd service account to the namespace Role

##### 4. User RBAC for Managing Logging Resources

**ClusterRole**: `logging-operator-edit`
- **Purpose**: Allows users to create and manage Flow, Output, ClusterFlow, and ClusterOutput resources
- **Aggregated Roles**: This ClusterRole is aggregated into `admin` and `edit` ClusterRoles
- **Key Permissions**:
  - Full CRUD on `flows`, `outputs` (namespace-scoped)
  - Full CRUD on `syslogngflows`, `syslogngoutputs` (namespace-scoped)
  - **Note**: Does NOT include ClusterFlow/ClusterOutput (requires cluster-admin or custom ClusterRole)

**Usage**: Users with `admin` or `edit` ClusterRole in a namespace automatically get permissions to manage Flow and Output resources in that namespace.

#### Viewing Current RBAC

```bash
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# List all logging-related RBAC resources
kubectl get clusterrole,clusterrolebinding | grep logging
kubectl get role,rolebinding -n kommander | grep logging

# View detailed permissions
kubectl describe clusterrole logging-operator
kubectl describe clusterrole logging-operator-edit
kubectl describe clusterrole logging-operator-logging-fluentbit
kubectl describe clusterrole logging-operator-logging-fluentd
```

### Project-Level RBAC for Logging Resources

To allow project-level users to manage logging resources (Flow, Output) for their applications, you need to grant them appropriate permissions.

#### Option 1: Grant Namespace-Scoped Permissions (Recommended for Projects)

This allows users to manage Flow and Output resources in their project namespace, but not ClusterFlow/ClusterOutput.

**File**: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/rbac/dm-dev-project-logging-rolebindings.yaml`

```yaml
# Project Logging Manager Role Bindings for dm-dev-project
# Grants permissions to manage Flow and Output resources in the project namespace
---
# 1. Grant Flow/Output management via aggregated ClusterRole
# Users with 'edit' or 'admin' role in the namespace automatically get this
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dm-dev-project-admins-logging-edit
  namespace: dm-dev-project
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: oidc:dm-dev-project-admins  # Replace with your VirtualGroup's group
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit  # Includes logging-operator-edit via aggregation
---
# 2. Alternative: Direct binding to logging-operator-edit
# Use this if you want explicit logging permissions without full 'edit' access
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dm-dev-project-admins-logging-only
  namespace: dm-dev-project
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: oidc:dm-dev-project-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-operator-edit
```

**What this grants**:
- ✅ Create, read, update, delete `Flow` resources in `dm-dev-project` namespace
- ✅ Create, read, update, delete `Output` resources in `dm-dev-project` namespace
- ❌ Cannot manage `ClusterFlow` or `ClusterOutput` (requires cluster-admin or custom ClusterRole)

#### Option 2: Grant Cluster-Wide Permissions (For Platform Admins)

If you need to grant permissions to manage ClusterFlow and ClusterOutput, create a custom ClusterRole:

**File**: `region-usa/az1/management-cluster/global/rbac/logging-cluster-admin-role.yaml`

```yaml
# ClusterRole for managing all logging resources (including cluster-scoped)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: logging-cluster-admin
  annotations:
    description: "Full access to all Logging Operator resources including ClusterFlow and ClusterOutput"
rules:
  - apiGroups:
      - logging.banzaicloud.io
    resources:
      - flows
      - outputs
      - clusterflows
      - clusteroutputs
      - loggings
      - fluentbitagents
      - fluentdconfigs
      - syslogngflows
      - syslogngoutputs
      - syslogngconfigs
    verbs:
      - create
      - delete
      - deletecollection
      - get
      - list
      - patch
      - update
      - watch
```

**File**: `region-usa/az1/management-cluster/global/rbac/logging-cluster-admin-rolebinding.yaml`

```yaml
# ClusterRoleBinding for platform admins
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dm-k8s-admins-logging-cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: dm-k8s-admin  # Replace with your admin user/group
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-cluster-admin
```

#### Option 3: Using NKP VirtualGroups (Recommended for NKP Environments)

For NKP/Kommander environments, use VirtualGroups and NKP RBAC CRDs:

**File**: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/rbac/dm-dev-project-logging-vg-rolebindings.yaml`

```yaml
# Project Logging Manager using NKP VirtualGroups
# This grants permissions via NKP's RBAC system
---
# 1. Create a ProjectRole for logging management
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: ProjectRole
metadata:
  name: project-logging-manager
  namespace: dm-dev-project
spec:
  rules:
    - apiGroups:
        - logging.banzaicloud.io
      resources:
        - flows
        - outputs
      verbs:
        - create
        - delete
        - get
        - list
        - patch
        - update
        - watch
---
# 2. Bind VirtualGroup to the ProjectRole
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupProjectRoleBinding
metadata:
  name: dm-dev-project-admins-logging-manager
  namespace: dm-dev-project
  finalizers:
    - workspaces.kommander.mesosphere.io/virtualgroupprojectrolebinding
spec:
  virtualGroupRef:
    name: dm-dev-project-admins
  projectRoleRef:
    name: project-logging-manager
```

### RBAC for Workload Cluster 1

When deploying the Logging Operator on workload cluster 1, the same RBAC resources will be automatically created. However, you may want to grant project-level users permissions to manage logging resources.

#### Creating Project-Level RBAC for Workload Cluster

**File**: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/rbac/logging-project-rolebindings.yaml`

```yaml
# Project Logging Manager for workload cluster applications
# This allows project users to manage Flow and Output in their namespaces
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: project-logging-manager
  namespace: your-app-namespace  # Replace with your application namespace
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: oidc:your-project-group  # Replace with your group
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-operator-edit
```

### RBAC Summary Table

| Resource | Scope | Purpose | Who Needs It |
|----------|-------|---------|--------------|
| `logging-operator` ClusterRole | Cluster | Operator controller permissions | Logging Operator controller (auto-created) |
| `logging-operator-logging-fluentbit` ClusterRole | Cluster | Read pod/namespace metadata | Fluent Bit DaemonSet (auto-created) |
| `logging-operator-logging-fluentd` ClusterRole | Cluster | Read K8s resources | Fluentd StatefulSet (auto-created) |
| `logging-operator-logging-fluentd` Role | Namespace | Manage configmaps/secrets | Fluentd StatefulSet (auto-created) |
| `logging-operator-edit` ClusterRole | Cluster | Manage Flow/Output | Users managing logging (aggregated into edit/admin) |
| Custom ClusterRole | Cluster | Manage ClusterFlow/ClusterOutput | Platform admins |
| Custom ProjectRole | Namespace | Manage Flow/Output in project | Project-level users |

### Best Practices

1. **Principle of Least Privilege**: Only grant the minimum permissions needed
   - For project-level apps: Use `logging-operator-edit` (Flow/Output only)
   - For platform admins: Use custom ClusterRole for ClusterFlow/ClusterOutput

2. **Use Namespace-Scoped Resources When Possible**:
   - Prefer `Flow` and `Output` over `ClusterFlow` and `ClusterOutput`
   - This allows better isolation and project-level management

3. **Leverage Aggregated Roles**:
   - `logging-operator-edit` is aggregated into `edit` and `admin` ClusterRoles
   - Users with `edit` or `admin` in a namespace automatically get Flow/Output permissions

4. **Use NKP VirtualGroups for NKP Environments**:
   - Prefer NKP RBAC CRDs (VirtualGroupProjectRoleBinding) over native K8s RBAC
   - Better integration with Kommander UI and workspace/project management

5. **Document RBAC Changes**:
   - Keep RBAC resources in GitOps repository
   - Document who has access and why

### Troubleshooting RBAC

#### User Cannot Create Flow/Output

**Symptoms**: User gets "forbidden" error when creating Flow or Output

**Solutions**:
1. Check if user has `edit` or `admin` role in the namespace:
   ```bash
   kubectl get rolebinding -n <namespace> | grep <user>
   ```

2. Verify `logging-operator-edit` ClusterRole exists:
   ```bash
   kubectl get clusterrole logging-operator-edit
   ```

3. Grant explicit permissions:
   ```bash
   kubectl create rolebinding <user>-logging-edit \
     --clusterrole=logging-operator-edit \
     --user=<user> \
     -n <namespace>
   ```

#### Fluent Bit Cannot Read Pod Metadata

**Symptoms**: Logs missing Kubernetes metadata (labels, namespace, etc.)

**Solutions**:
1. Check Fluent Bit ClusterRoleBinding:
   ```bash
   kubectl get clusterrolebinding logging-operator-logging-fluentbit
   ```

2. Verify Fluent Bit service account:
   ```bash
   kubectl get sa -n kommander | grep fluent-bit
   ```

3. Check Fluent Bit pod logs for RBAC errors:
   ```bash
   kubectl logs -n kommander -l app.kubernetes.io/name=fluent-bit | grep -i forbidden
   ```

#### User Cannot Manage ClusterFlow/ClusterOutput

**Symptoms**: User gets "forbidden" error when creating ClusterFlow or ClusterOutput

**Solutions**:
1. ClusterFlow/ClusterOutput require cluster-scoped permissions
2. Grant custom ClusterRole with ClusterFlow/ClusterOutput permissions (see Option 2 above)
3. Or grant `cluster-admin` (not recommended for regular users)

---

## Additional Resources

- [Logging Operator Documentation](https://kube-logging.dev/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [Fluentd Documentation](https://docs.fluentd.org/)
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [NKP RBAC Guide](./NKP-RBAC-GUIDE.md)

---

## Quick Reference

### Management Cluster Current Setup
- **Logging CR**: `logging-operator-logging` in `kommander` namespace
- **ClusterFlow**: `cluster-containers` routes all logs
- **ClusterOutput**: `loki` sends to `grafana-loki-loki-distributed-gateway.kommander.svc.cluster.local:80`
- **Loki**: Deployed via `project-grafana-loki` AppDeployment

### Workload Cluster 1 Setup (To Be Configured)
- **Logging CR**: `workload-logging` in `kommander` namespace
- **ClusterFlow**: `cluster-containers` routes all logs
- **ClusterOutput**: `loki` sends to Loki service
- **Loki**: Deployed via `workload-grafana-loki` AppDeployment (or manually)

### Key Files Location
- Management cluster logging: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/applications/platform-applications/`
- Workload cluster logging: `region-usa/az1/workload-clusters/dm-nkp-workload-1/apps/logging/`
- RBAC resources: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/projects/dm-dev-project/rbac/`

