# Nutanix Infrastructure - AZ1

This folder contains the Nutanix infrastructure configuration that forms the foundation for AZ1.

## Current Configuration

| Component | Value |
|-----------|-------|
| **Prism Central** | `pc.dev.nkp.sh:9440` |
| **PE Cluster** | `ncn-dev-sandbox` |
| **Subnet** | `vlan173` |
| **Storage Container** | `default-container-92034737804854` |
| **VM Image** | `nkp-rocky-9.6-release-1.34.1-20251126174702` |

## Kubernetes Clusters Hosted

| Cluster | Type | VIP | MetalLB Range | Nodes |
|---------|------|-----|---------------|-------|
| dm-nkp-workload-1 | Workload | 10.23.130.62 | 10.23.130.71-75 | 4 (1 CP + 3 Workers) |
| dm-nkp-workload-2 | Workload | 10.23.130.63 | 10.23.130.76-80 | 4 (1 CP + 3 Workers) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Prism Central (pc.dev.nkp.sh:9440)                       │
│                         (Management Plane)                                  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    PE Cluster: ncn-dev-sandbox                        │ │
│  │                                                                        │ │
│  │   Network: vlan173                                                    │ │
│  │   Storage: default-container-92034737804854                           │ │
│  │                                                                        │ │
│  │   ┌─────────────────────────────┐  ┌─────────────────────────────┐   │ │
│  │   │    dm-nkp-workload-1        │  │    dm-nkp-workload-2        │   │ │
│  │   │                             │  │                             │   │ │
│  │   │  VIP: 10.23.130.62          │  │  VIP: 10.23.130.63          │   │ │
│  │   │  K8s: v1.34.1               │  │  K8s: v1.34.1               │   │ │
│  │   │  NKP: v2.17.0-rc.1          │  │  NKP: v2.17.0-rc.1          │   │ │
│  │   │                             │  │                             │   │ │
│  │   │  ┌─────────────────────┐   │  │  ┌─────────────────────┐   │   │ │
│  │   │  │ Control Plane (1)   │   │  │  │ Control Plane (1)   │   │   │ │
│  │   │  │ 4 vCPU, 16Gi, 80Gi │   │  │  │ 4 vCPU, 16Gi, 80Gi │   │   │ │
│  │   │  └─────────────────────┘   │  │  └─────────────────────┘   │   │ │
│  │   │                             │  │                             │   │ │
│  │   │  ┌─────────────────────┐   │  │  ┌─────────────────────┐   │   │ │
│  │   │  │ Workers (3)         │   │  │  │ Workers (3)         │   │   │ │
│  │   │  │ 8 vCPU, 32Gi, 80Gi │   │  │  │ 8 vCPU, 32Gi, 80Gi │   │   │ │
│  │   │  │ each               │   │  │  │ each               │   │   │ │
│  │   │  └─────────────────────┘   │  │  └─────────────────────┘   │   │ │
│  │   │                             │  │                             │   │ │
│  │   │  MetalLB: .71-.75 (5 IPs)  │  │  MetalLB: .76-.80 (5 IPs)  │   │ │
│  │   └─────────────────────────────┘  └─────────────────────────────┘   │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Resource Summary

| Resource | Per Cluster | Total (2 clusters) |
|----------|-------------|-------------------|
| Nodes | 4 | 8 |
| vCPUs | 28 | 56 |
| Memory | 112Gi | 224Gi |
| Storage | 320Gi | 640Gi |
| MetalLB IPs | 5 | 10 |

## Files

| File | Description |
|------|-------------|
| `prism-central.yaml` | PC endpoint, IP allocations, common config |
| `prism-elements/pe-cluster-az1.yaml` | PE cluster details and K8s cluster specs |

## IP Address Allocation

```
Subnet: vlan173 (10.23.130.0/24)

Control Plane VIPs:
├── 10.23.130.62  → dm-nkp-workload-1
└── 10.23.130.63  → dm-nkp-workload-2

MetalLB Load Balancer IPs:
├── 10.23.130.71-75  → dm-nkp-workload-1 (5 IPs)
└── 10.23.130.76-80  → dm-nkp-workload-2 (5 IPs)
```

## Common Configuration

All clusters use:
- **NKP Topology Class**: `nkp-nutanix-v2.17.0-rc.1`
- **Kubernetes Version**: `v1.34.1`
- **OS Image**: `nkp-rocky-9.6-release-1.34.1-20251126174702`
- **CNI**: Cilium
- **VIP Provider**: KubeVIP
- **Load Balancer**: MetalLB
- **CSI**: Nutanix Volumes

## Related Resources

| Resource | Path |
|----------|------|
| Cluster definitions | `../../management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/bases/` |
| Version overlays | `../../management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/` |
| Sealed secrets | `../../management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/sealed-secrets/` |
| Workload cluster configs | `../../workload-clusters/dm-nkp-workload-*/` |
