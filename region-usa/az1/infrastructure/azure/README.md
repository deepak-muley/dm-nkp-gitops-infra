# Azure Infrastructure - AZ1

This folder contains Azure infrastructure configuration for hosting AKS clusters in AZ1.

## Components

### Resource Group
- Logical container for Azure resources
- Defines region and access policies

### Virtual Network (VNet)
- Isolated network for AKS clusters
- Contains subnets for nodes and services

### AKS Prerequisites
- Azure AD integration
- Managed identities
- Network security groups

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Azure Subscription                         │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Resource Group (az1-aks-rg)                   │ │
│  │              Region: East US                               │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │              VNet (az1-aks-vnet)                      │ │ │
│  │  │                                                       │ │ │
│  │  │  ┌───────────────┐    ┌───────────────┐             │ │ │
│  │  │  │ AKS Subnet    │    │ Services      │             │ │ │
│  │  │  │ (nodes)       │    │ Subnet        │             │ │ │
│  │  │  │               │    │ (endpoints)   │             │ │ │
│  │  │  │ ┌───────────┐ │    │               │             │ │ │
│  │  │  │ │ AKS Nodes │ │    │               │             │ │ │
│  │  │  │ └───────────┘ │    │               │             │ │ │
│  │  │  └───────────────┘    └───────────────┘             │ │ │
│  │  │                                                       │ │ │
│  │  │  ┌──────────────────────────────────────────────────┐│ │ │
│  │  │  │          AKS Control Plane (Managed)             ││ │ │
│  │  │  └──────────────────────────────────────────────────┘│ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `resource-config.yaml` | Resource group, VNet, and identity configuration |

## Azure Resources Required

| Resource | Purpose |
|----------|---------|
| Resource Group | Logical grouping |
| Virtual Network | Network isolation |
| Subnets | Node and service placement |
| Network Security Groups | Traffic filtering |
| Managed Identity | AKS authentication |
| Azure AD Integration | RBAC |
| Azure Container Registry | Image storage |

## Related Resources

- AKS cluster definitions: `../../management-cluster/workspaces/dm-dev-workspace/clusters/aks-infra/`



