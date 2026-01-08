#!/bin/bash
#
# Regenerate All Sealed Secrets
#
# This script:
# 1. Backs up the latest sealed-secrets controller keys to do-not-checkin-folder
# 2. Re-encrypts cluster credentials (dm-dev-common-sealed-secrets.yaml)
# 3. Generates NDK image pull sealed secret
# 4. Generates NAI image pull sealed secret
#
# All secrets are encrypted using the keys from do-not-checkin-folder
# which are always kept up to date with the management cluster.
#
# Usage:
#   ./scripts/regenerate-all-sealed-secrets.sh [options]
#
# Options:
#   -k, --kubeconfig PATH    Path to kubeconfig file (required)
#   --cluster-name NAME      Cluster name for key backup (default: dm-nkp-mgmt-1)
#   -h, --help               Show this help message

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEALED_SECRETS_SCRIPT="$SCRIPT_DIR/sealed-secrets.sh"
DO_NOT_CHECKIN_DIR="$REPO_ROOT/do-not-checkin-folder"
DEFAULT_CLUSTER_NAME="dm-nkp-mgmt-1"
KUBECONFIG=""
CLUSTER_NAME="$DEFAULT_CLUSTER_NAME"

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Regenerate All Sealed Secrets

This script regenerates all sealed secrets using the latest keys from the management cluster.

Steps:
  1. Backup sealed-secrets controller keys to do-not-checkin-folder
  2. Re-encrypt cluster credentials (reads from do-not-checkin-folder/dm-dev-common-secrets.yaml)
  3. Generate NDK image pull secret (reads from do-not-checkin-folder/ndk-image-pull-secret.yaml)
  4. Generate NAI image pull secret (reads from do-not-checkin-folder/nai-image-pull-secret.yaml)

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file (required)
    --cluster-name NAME      Cluster name for key backup (default: dm-nkp-mgmt-1)
    -h, --help               Show this help message

Examples:
    $0
    $0 -k /path/to/kubeconfig
    $0 --cluster-name my-cluster
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if sealed-secrets.sh exists
if [ ! -f "$SEALED_SECRETS_SCRIPT" ]; then
    echo -e "${RED}✗ sealed-secrets.sh not found: $SEALED_SECRETS_SCRIPT${NC}"
    exit 1
fi

# Make script executable
chmod +x "$SEALED_SECRETS_SCRIPT"

# Validate kubeconfig is provided
if [ -z "$KUBECONFIG" ]; then
    echo -e "${RED}✗ Error: --kubeconfig is required${NC}"
    echo -e "${YELLOW}  Usage: $0 -k /path/to/kubeconfig [options]${NC}"
    exit 1
fi

# Validate kubeconfig file exists
if [ ! -f "$KUBECONFIG" ]; then
    echo -e "${RED}✗ Error: Kubeconfig file not found: $KUBECONFIG${NC}"
    exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Regenerate All Sealed Secrets                                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Export kubeconfig
export KUBECONFIG

# Step 1: Backup keys directly to do-not-checkin-folder
echo -e "${CYAN}Step 1: Backing up sealed-secrets controller keys...${NC}"
echo ""
mkdir -p "$DO_NOT_CHECKIN_DIR"
"$SEALED_SECRETS_SCRIPT" backup -k "$KUBECONFIG" -o "$DO_NOT_CHECKIN_DIR" || {
    echo -e "${RED}✗ Failed to backup keys${NC}"
    exit 1
}

# Rename keys with cluster name suffix
if [ -f "$DO_NOT_CHECKIN_DIR/sealed-secrets-key-backup.yaml" ]; then
    mv "$DO_NOT_CHECKIN_DIR/sealed-secrets-key-backup.yaml" "$DO_NOT_CHECKIN_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml"
    echo -e "${GREEN}✓ Private key saved to: $DO_NOT_CHECKIN_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml${NC}"
fi

if [ -f "$DO_NOT_CHECKIN_DIR/sealed-secrets-public-key.pem" ]; then
    mv "$DO_NOT_CHECKIN_DIR/sealed-secrets-public-key.pem" "$DO_NOT_CHECKIN_DIR/sealed-secrets-public-key-${CLUSTER_NAME}.pem"
    echo -e "${GREEN}✓ Public key saved to: $DO_NOT_CHECKIN_DIR/sealed-secrets-public-key-${CLUSTER_NAME}.pem${NC}"
fi
echo ""

# Step 2: Re-encrypt cluster credentials
echo -e "${CYAN}Step 2: Re-encrypting cluster credentials...${NC}"
echo ""
"$SEALED_SECRETS_SCRIPT" re-encrypt -k "$KUBECONFIG" || {
    echo -e "${RED}✗ Failed to re-encrypt cluster credentials${NC}"
    exit 1
}
echo ""

# Step 3: Generate NDK sealed secret
echo -e "${CYAN}Step 3: Generating NDK image pull sealed secret...${NC}"
echo ""
# Read credentials from do-not-checkin-folder/ndk-image-pull-secret.yaml
NDK_SOURCE_FILE="$REPO_ROOT/do-not-checkin-folder/ndk-image-pull-secret.yaml"
if [ ! -f "$NDK_SOURCE_FILE" ]; then
    echo -e "${RED}✗ NDK source file not found: $NDK_SOURCE_FILE${NC}"
    echo -e "${YELLOW}  Skipping NDK secret generation${NC}"
else
    # Extract username and password from the YAML file
    NDK_USERNAME=$(grep -A 10 "stringData:" "$NDK_SOURCE_FILE" | grep "username:" | head -1 | cut -d'"' -f2)
    NDK_PASSWORD=$(grep -A 10 "stringData:" "$NDK_SOURCE_FILE" | grep "password:" | head -1 | cut -d'"' -f2)

    if [ -z "$NDK_USERNAME" ] || [ -z "$NDK_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ Could not extract NDK credentials from source file${NC}"
        echo -e "${YELLOW}  Skipping NDK secret generation${NC}"
    else
        "$SEALED_SECRETS_SCRIPT" generate-ndk-sealed-secrets \
            -k "$KUBECONFIG" \
            --cluster-name "$CLUSTER_NAME" \
            --username "$NDK_USERNAME" \
            --password "$NDK_PASSWORD" || {
            echo -e "${RED}✗ Failed to generate NDK sealed secret${NC}"
            exit 1
        }
    fi
fi
echo ""

# Step 4: Generate NAI sealed secret
echo -e "${CYAN}Step 4: Generating NAI image pull sealed secret...${NC}"
echo ""
# Read credentials from do-not-checkin-folder/nai-image-pull-secret.yaml
NAI_SOURCE_FILE="$REPO_ROOT/do-not-checkin-folder/nai-image-pull-secret.yaml"
if [ ! -f "$NAI_SOURCE_FILE" ]; then
    echo -e "${RED}✗ NAI source file not found: $NAI_SOURCE_FILE${NC}"
    echo -e "${YELLOW}  Skipping NAI secret generation${NC}"
else
    # Extract username and password from the YAML file
    NAI_USERNAME=$(grep -A 10 "stringData:" "$NAI_SOURCE_FILE" | grep "username:" | head -1 | cut -d'"' -f2)
    NAI_PASSWORD=$(grep -A 10 "stringData:" "$NAI_SOURCE_FILE" | grep "password:" | head -1 | cut -d'"' -f2)

    if [ -z "$NAI_USERNAME" ] || [ -z "$NAI_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ Could not extract NAI credentials from source file${NC}"
        echo -e "${YELLOW}  Skipping NAI secret generation${NC}"
    else
        "$SEALED_SECRETS_SCRIPT" generate-nai-sealed-secrets \
            -k "$KUBECONFIG" \
            --cluster-name "$CLUSTER_NAME" \
            --username "$NAI_USERNAME" \
            --password "$NAI_PASSWORD" || {
            echo -e "${RED}✗ Failed to generate NAI sealed secret${NC}"
            exit 1
        }
    fi
fi
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ All sealed secrets regenerated successfully!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "${YELLOW}  1. Review the generated sealed secret files${NC}"
echo -e "${YELLOW}  2. Commit and push the changes:${NC}"
echo -e "${GREEN}     git add region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/sealed-secrets/dm-dev-common-sealed-secrets.yaml${NC}"
echo -e "${GREEN}     git add region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/nkp-nutanix-products-catalog-applications/ndk/ndk-image-pull-secret.yaml${NC}"
echo -e "${GREEN}     git add region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/nkp-nutanix-products-catalog-applications/nutanix-ai/nai-image-pull-secret.yaml${NC}"
echo -e "${GREEN}     git commit -m 'Regenerate sealed secrets with latest keys'${NC}"
echo -e "${GREEN}     git push${NC}"
echo ""

