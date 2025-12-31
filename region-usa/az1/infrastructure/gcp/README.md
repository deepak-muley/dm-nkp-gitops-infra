# GCP Infrastructure - AZ1

This folder contains GCP infrastructure configuration for hosting GKE clusters in AZ1.

## Components

### GCP Project
- Isolated environment for GKE resources
- Billing and IAM boundary

### VPC Network
- Custom mode VPC for GKE clusters
- Regional subnets with secondary ranges for pods/services

### GKE Prerequisites
- Service accounts
- Workload Identity
- Cloud NAT for private clusters

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCP Project                               │
│                   (az1-gke-project)                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   VPC (az1-gke-vpc)                        │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │              Subnet (az1-gke-subnet)                 │ │ │
│  │  │              Region: us-east1                        │ │ │
│  │  │                                                       │ │ │
│  │  │  Primary Range: 10.220.0.0/20 (nodes)               │ │ │
│  │  │  Secondary Range: 10.221.0.0/16 (pods)              │ │ │
│  │  │  Secondary Range: 10.222.0.0/20 (services)          │ │ │
│  │  │                                                       │ │ │
│  │  │  ┌───────────────────────────────────────────────┐  │ │ │
│  │  │  │              GKE Cluster                      │  │ │ │
│  │  │  │                                               │  │ │ │
│  │  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐        │  │ │ │
│  │  │  │  │ Node    │ │ Node    │ │ Node    │        │  │ │ │
│  │  │  │  │ Pool 1  │ │ Pool 2  │ │ Pool 3  │        │  │ │ │
│  │  │  │  └─────────┘ └─────────┘ └─────────┘        │  │ │ │
│  │  │  └───────────────────────────────────────────────┘  │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐                       │ │
│  │  │ Cloud NAT    │  │ Cloud Router │                       │ │
│  │  └──────────────┘  └──────────────┘                       │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `project-config.yaml` | Project, VPC, and IAM configuration |

## GCP Resources Required

| Resource | Purpose |
|----------|---------|
| Project | Resource isolation |
| VPC Network | Network isolation |
| Subnets | Node and pod placement |
| Firewall Rules | Traffic control |
| Cloud NAT | Private cluster egress |
| Cloud Router | NAT routing |
| Service Accounts | GKE permissions |
| Workload Identity | Pod authentication |

## Related Resources

- GKE cluster definitions: `../../management-cluster/workspaces/dm-dev-workspace/clusters/gke-infra/`



