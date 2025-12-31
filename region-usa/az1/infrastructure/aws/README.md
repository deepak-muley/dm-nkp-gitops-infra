# AWS Infrastructure - AZ1

This folder contains AWS infrastructure configuration for hosting EKS clusters in AZ1.

## Components

### VPC (Virtual Private Cloud)
- Isolated network environment for EKS clusters
- Contains public and private subnets
- NAT Gateways for private subnet internet access

### EKS Prerequisites
- IAM roles and policies
- Security groups
- EKS cluster endpoint configuration

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Region                               │
│                      (e.g., us-east-1)                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      VPC (az1-vpc)                         │ │
│  │                                                            │ │
│  │  ┌──────────────────┐    ┌──────────────────┐             │ │
│  │  │  Public Subnet   │    │  Private Subnet  │             │ │
│  │  │   (az1-pub-1)    │    │   (az1-priv-1)   │             │ │
│  │  │                  │    │                  │             │ │
│  │  │  ┌────────────┐  │    │  ┌────────────┐  │             │ │
│  │  │  │ NAT GW     │  │    │  │ EKS Nodes  │  │             │ │
│  │  │  │ ALB/NLB    │  │    │  │            │  │             │ │
│  │  │  └────────────┘  │    │  └────────────┘  │             │ │
│  │  └──────────────────┘    └──────────────────┘             │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │              EKS Control Plane (Managed)             │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `vpc-config.yaml` | VPC, subnets, and networking configuration |

## AWS Resources Required

| Resource | Purpose |
|----------|---------|
| VPC | Network isolation |
| Subnets (public/private) | Node placement |
| Internet Gateway | Public internet access |
| NAT Gateway | Private subnet egress |
| Route Tables | Traffic routing |
| Security Groups | Network ACLs |
| IAM Roles | EKS service permissions |

## Related Resources

- EKS cluster definitions: `../../management-cluster/workspaces/dm-dev-workspace/clusters/eks-infra/`



