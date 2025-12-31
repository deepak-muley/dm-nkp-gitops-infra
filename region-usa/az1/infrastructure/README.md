# AZ1 Infrastructure

This folder contains definitions and documentation for the underlying non-Kubernetes infrastructure that constitutes Availability Zone 1 (az1) in the USA region.

## Purpose

While the `management-cluster/` and `workload-clusters/` folders contain Kubernetes resources managed via GitOps, this `infrastructure/` folder documents the foundational cloud/on-prem infrastructure that hosts those clusters.

## Directory Structure

```
infrastructure/
├── README.md                          # This file
├── nutanix/                           # Nutanix infrastructure
│   ├── README.md
│   ├── prism-central.yaml             # Prism Central configuration
│   └── prism-elements/                # Prism Element clusters
│       └── pe-cluster-az1.yaml
├── aws/                               # AWS infrastructure (for EKS)
│   ├── README.md
│   └── vpc-config.yaml
├── azure/                             # Azure infrastructure (for AKS)
│   ├── README.md
│   └── resource-config.yaml
└── gcp/                               # GCP infrastructure (for GKE)
    ├── README.md
    └── project-config.yaml
```

## Infrastructure Types

| Provider | Description | Use Case |
|----------|-------------|----------|
| Nutanix | On-premises HCI platform | NKP on Nutanix clusters |
| AWS | Amazon Web Services | EKS clusters |
| Azure | Microsoft Azure | AKS clusters |
| GCP | Google Cloud Platform | GKE clusters |

## Security Note

⚠️ **IMPORTANT**: These files should contain only non-sensitive configuration metadata (endpoints, names, identifiers). Sensitive data like credentials, tokens, or private keys should NEVER be stored here. Use sealed-secrets or external secret management for sensitive data.

## Relationship to Kubernetes Clusters

```
infrastructure/nutanix/    → Hosts → management-cluster/, workload-clusters/ (nutanix-infra)
infrastructure/aws/        → Hosts → clusters/eks-infra/
infrastructure/azure/      → Hosts → clusters/aks-infra/
infrastructure/gcp/        → Hosts → clusters/gke-infra/
```



