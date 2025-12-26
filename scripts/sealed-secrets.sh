#!/bin/bash
#
# Sealed Secrets Management Tool
#
# Unified script for managing sealed-secrets keys and secrets.
# Supports backup, restore, encrypt, decrypt, and re-encrypt operations.
#
# Usage:
#   ./scripts/sealed-secrets.sh <command> [options]
#
# Commands:
#   backup          Backup sealed-secrets controller keys (public & private)
#   restore         Restore sealed-secrets keys from backup
#   encrypt         Encrypt a plaintext secret YAML file
#   decrypt         Decrypt a sealed secret YAML file (requires keys)
#   re-encrypt      Re-encrypt secrets with new credentials
#   status          Check status of sealed secrets in cluster
#
# Use './scripts/sealed-secrets.sh <command> --help' for command-specific help

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_NAMESPACE="sealed-secrets-system"
DEFAULT_WORKSPACE_NAMESPACE="dm-dev-workspace"
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_BACKUP_DIR="/Users/deepak.muley/ws/nkp"
DEFAULT_BACKUP_FILE="$DEFAULT_BACKUP_DIR/sealed-secrets-key-backup.yaml"
DEFAULT_PUBLIC_KEY="$DEFAULT_BACKUP_DIR/sealed-secrets-public-key.pem"

# Global variables
KUBECONFIG=""
NAMESPACE=""
WORKSPACE_NAMESPACE=""

# Print header
print_header() {
    local title=$1
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $title${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not found${NC}"
        exit 1
    fi

    if ! command -v kubeseal &> /dev/null; then
        echo -e "${RED}✗ kubeseal not found. Please install it:${NC}"
        echo -e "${YELLOW}  brew install kubeseal${NC}"
        exit 1
    fi
}

# Set kubeconfig
set_kubeconfig() {
    if [ -z "$KUBECONFIG" ]; then
        if [ -f "$DEFAULT_MGMT_KUBECONFIG" ]; then
            KUBECONFIG="$DEFAULT_MGMT_KUBECONFIG"
        fi
    fi

    if [ -n "$KUBECONFIG" ]; then
        export KUBECONFIG
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}✗ Cannot connect to cluster${NC}"
        exit 1
    fi
}

# ============================================================================
# BACKUP COMMAND
# ============================================================================
cmd_backup() {
    local OUTPUT_DIR="$DEFAULT_BACKUP_DIR"
    local NAMESPACE="$DEFAULT_NAMESPACE"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Backup Sealed Secrets Controller Keys

Backs up both public and private keys from the sealed-secrets controller.

Usage:
    $0 backup [options]

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file
    -n, --namespace NAME     Namespace for sealed-secrets (default: $DEFAULT_NAMESPACE)
    -o, --output-dir PATH    Directory to save backups (default: $DEFAULT_BACKUP_DIR)
    -h, --help               Show this help message

Examples:
    $0 backup
    $0 backup -o /path/to/backup
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    print_header "Sealed Secrets Keys Backup"
    check_prerequisites
    set_kubeconfig

    echo -e "${CYAN}[1/4] Checking prerequisites...${NC}"
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}✗ Namespace '$NAMESPACE' does not exist${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' exists${NC}"

    mkdir -p "$OUTPUT_DIR"
    echo -e "${GREEN}✓ Output directory: $OUTPUT_DIR${NC}"
    echo ""

    echo -e "${CYAN}[2/4] Extracting keys from cluster...${NC}"
    KEY_SECRETS=$(kubectl get secrets -n "$NAMESPACE" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name 2>/dev/null || true)

    if [ -z "$KEY_SECRETS" ]; then
        echo -e "${RED}✗ No active keys found${NC}"
        exit 1
    fi

    KEY_COUNT=$(echo "$KEY_SECRETS" | wc -l | tr -d ' ')
    echo -e "${CYAN}  Found $KEY_COUNT active key(s)${NC}"

    BACKUP_FILE="$OUTPUT_DIR/sealed-secrets-keys-backup-$(date +%Y%m%d-%H%M%S).yaml"
    STANDARD_BACKUP="$OUTPUT_DIR/sealed-secrets-key-backup.yaml"

    echo "apiVersion: v1" > "$BACKUP_FILE"
    echo "kind: List" >> "$BACKUP_FILE"
    echo "items:" >> "$BACKUP_FILE"

    while IFS= read -r key_secret; do
        if [ -z "$key_secret" ]; then
            continue
        fi
        SECRET_NAME=$(echo "$key_secret" | cut -d/ -f2)
        echo -e "${CYAN}  Extracting: $SECRET_NAME${NC}"
        kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml | \
            sed 's/^/  - /' | \
            sed '1s/^  - apiVersion:/apiVersion:/' | \
            sed '1s/^  - kind:/kind:/' | \
            sed '1s/^  - metadata:/metadata:/' >> "$BACKUP_FILE"
        echo "---" >> "$BACKUP_FILE"
    done <<< "$KEY_SECRETS"

    sed -i '' '$ { /^---$/d; }' "$BACKUP_FILE" 2>/dev/null || sed -i '$ { /^---$/d; }' "$BACKUP_FILE" 2>/dev/null || true

    cp "$BACKUP_FILE" "$STANDARD_BACKUP"
    echo -e "${GREEN}✓ Keys backed up to: $STANDARD_BACKUP${NC}"
    echo ""

    echo -e "${CYAN}[3/4] Extracting public key...${NC}"
    PUBLIC_KEY_FILE="$OUTPUT_DIR/sealed-secrets-public-key-$(date +%Y%m%d-%H%M%S).pem"
    STANDARD_PUBLIC_KEY="$OUTPUT_DIR/sealed-secrets-public-key.pem"

    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$POD_NAME" ]; then
        if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /tmp/keys/publickey.pem > "$PUBLIC_KEY_FILE" 2>/dev/null; then
            cp "$PUBLIC_KEY_FILE" "$STANDARD_PUBLIC_KEY"
            echo -e "${GREEN}✓ Public key extracted: $STANDARD_PUBLIC_KEY${NC}"
        else
            FIRST_KEY=$(kubectl get secrets -n "$NAMESPACE" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name | head -1 | cut -d/ -f2)
            if kubectl get secret "$FIRST_KEY" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$PUBLIC_KEY_FILE" 2>/dev/null; then
                cp "$PUBLIC_KEY_FILE" "$STANDARD_PUBLIC_KEY"
                echo -e "${GREEN}✓ Public key extracted from secret: $STANDARD_PUBLIC_KEY${NC}"
            else
                echo -e "${YELLOW}⚠ Could not extract public key${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Controller pod not found, skipping public key extraction${NC}"
    fi
    echo ""

    echo -e "${CYAN}[4/4] Summary${NC}"
    echo -e "${GREEN}✓ Backup completed!${NC}"
    echo ""
    echo -e "${BLUE}Backup files:${NC}"
    echo -e "  ${CYAN}Private keys:${NC} $STANDARD_BACKUP"
    if [ -f "$STANDARD_PUBLIC_KEY" ]; then
        echo -e "  ${CYAN}Public key:${NC} $STANDARD_PUBLIC_KEY"
    fi
    echo ""
    echo -e "${YELLOW}⚠ SECURITY: These files are NEVER committed to git!${NC}"
}

# ============================================================================
# RESTORE COMMAND
# ============================================================================
cmd_restore() {
    local BACKUP_FILE="$DEFAULT_BACKUP_FILE"
    local NAMESPACE="$DEFAULT_NAMESPACE"
    local SKIP_VERIFY=false
    local FORCE=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP_FILE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Restore Sealed Secrets Keys

Restores sealed-secrets private keys from backup and verifies they can decrypt secrets.

Usage:
    $0 restore [options]

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file
    -b, --backup PATH        Path to backup file (default: $DEFAULT_BACKUP_FILE)
    -n, --namespace NAME     Namespace for sealed-secrets (default: $DEFAULT_NAMESPACE)
    --skip-verify            Skip verification step
    --force                  Force restore even if keys exist
    -h, --help               Show this help message

Examples:
    $0 restore
    $0 restore --force
    $0 restore -b /path/to/backup.yaml
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    print_header "Sealed Secrets Keys Restoration"
    check_prerequisites
    set_kubeconfig

    echo -e "${CYAN}[1/6] Checking prerequisites...${NC}"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}✗ Backup file not found: $BACKUP_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Backup file found${NC}"

    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE" || true
    fi
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' exists${NC}"
    echo ""

    echo -e "${CYAN}[2/6] Checking existing keys...${NC}"
    EXISTING_KEYS=$(kubectl get secrets -n "$NAMESPACE" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name 2>/dev/null | wc -l | tr -d ' ')

    if [ "$EXISTING_KEYS" -gt 0 ] && [ "$FORCE" = false ]; then
        echo -e "${YELLOW}⚠ Found $EXISTING_KEYS existing key(s)${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    echo ""

    echo -e "${CYAN}[3/6] Restoring keys...${NC}"
    KEY_COUNT=$(grep -c "kind: Secret" "$BACKUP_FILE" || echo "0")
    echo -e "${CYAN}  Found $KEY_COUNT key(s) in backup${NC}"

    kubectl apply -f "$BACKUP_FILE" > /dev/null 2>&1
    sleep 2

    RESTORED_KEYS=$(kubectl get secrets -n "$NAMESPACE" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ Keys restored ($RESTORED_KEYS active keys)${NC}"
    echo ""

    echo -e "${CYAN}[4/6] Restarting controller...${NC}"
    if kubectl get deployment sealed-secrets-controller -n "$NAMESPACE" &> /dev/null; then
        kubectl rollout restart deployment sealed-secrets-controller -n "$NAMESPACE" > /dev/null 2>&1
        kubectl rollout status deployment sealed-secrets-controller -n "$NAMESPACE" --timeout=60s > /dev/null 2>&1 || true
        echo -e "${GREEN}✓ Controller restarted${NC}"
    fi
    echo ""

    if [ "$SKIP_VERIFY" = false ]; then
        echo -e "${CYAN}[5/6] Verifying decryption...${NC}"
        sleep 5

        FAILED_COUNT=0
        SUCCESS_COUNT=0
        TOTAL_COUNT=0

        for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
            SEALED_SECRETS=$(kubectl get sealedsecrets -n "$ns" -o name 2>/dev/null || true)
            while IFS= read -r sealed_secret; do
                if [ -z "$sealed_secret" ]; then
                    continue
                fi
                TOTAL_COUNT=$((TOTAL_COUNT + 1))
                SECRET_NAME=$(echo "$sealed_secret" | cut -d/ -f2)
                STATUS=$(kubectl get sealedsecret "$SECRET_NAME" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null || echo "Unknown")

                if [ "$STATUS" = "True" ]; then
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    echo -e "${GREEN}  ✓ $ns/$SECRET_NAME${NC}"
                else
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    echo -e "${RED}  ✗ $ns/$SECRET_NAME${NC}"
                fi
            done <<< "$SEALED_SECRETS"
        done

        echo ""
        echo -e "${CYAN}Verification: $SUCCESS_COUNT/$TOTAL_COUNT succeeded${NC}"
        if [ $FAILED_COUNT -gt 0 ]; then
            echo -e "${YELLOW}⚠ $FAILED_COUNT secret(s) failed - may need re-encryption${NC}"
        fi
        echo ""
    fi

    echo -e "${CYAN}[6/6] Summary${NC}"
    echo -e "${GREEN}✓ Restoration complete!${NC}"
}

# ============================================================================
# ENCRYPT COMMAND
# ============================================================================
cmd_encrypt() {
    local INPUT_FILE=""
    local OUTPUT_FILE=""
    local NAMESPACE=""
    local NAME=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -f|--file)
                INPUT_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --name)
                NAME="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Encrypt a Plaintext Secret

Encrypts a plaintext Kubernetes Secret YAML file into a SealedSecret.

Usage:
    $0 encrypt [options]

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file
    -f, --file PATH          Path to plaintext secret YAML file
    -o, --output PATH        Output file (default: stdout)
    -n, --namespace NAME     Namespace (required if not in YAML)
    --name NAME              Secret name (required if not in YAML)
    -h, --help               Show this help message

Examples:
    # Encrypt from file
    $0 encrypt -f secret.yaml -o sealed-secret.yaml

    # Encrypt with namespace
    $0 encrypt -f secret.yaml -n my-namespace -o sealed-secret.yaml

    # Encrypt from stdin
    cat secret.yaml | $0 encrypt -n my-namespace --name my-secret -o sealed-secret.yaml
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    check_prerequisites
    set_kubeconfig

    if [ -z "$INPUT_FILE" ]; then
        # Read from stdin
        TEMP_INPUT=$(mktemp)
        cat > "$TEMP_INPUT"
        INPUT_FILE="$TEMP_INPUT"
    fi

    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}✗ Input file not found: $INPUT_FILE${NC}"
        exit 1
    fi

    # Encrypt
    if [ -n "$OUTPUT_FILE" ]; then
        kubeseal < "$INPUT_FILE" > "$OUTPUT_FILE"
        echo -e "${GREEN}✓ Encrypted secret saved to: $OUTPUT_FILE${NC}"
    else
        kubeseal < "$INPUT_FILE"
    fi

    [ -n "$TEMP_INPUT" ] && rm -f "$TEMP_INPUT"
}

# ============================================================================
# DECRYPT COMMAND
# ============================================================================
cmd_decrypt() {
    local INPUT_FILE=""
    local OUTPUT_FILE=""
    local BACKUP_FILE="$DEFAULT_BACKUP_FILE"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                INPUT_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP_FILE="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Decrypt a SealedSecret

Decrypts a SealedSecret YAML file to plaintext (requires private keys).

Usage:
    $0 decrypt [options]

Options:
    -f, --file PATH          Path to SealedSecret YAML file
    -o, --output PATH        Output file (default: stdout)
    -b, --backup PATH        Path to keys backup (default: $DEFAULT_BACKUP_FILE)
    -h, --help               Show this help message

Examples:
    $0 decrypt -f sealed-secret.yaml -o secret.yaml
    cat sealed-secret.yaml | $0 decrypt -o secret.yaml
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    check_prerequisites

    if [ -z "$INPUT_FILE" ]; then
        echo -e "${RED}✗ Input file required (use -f or pipe from stdin)${NC}"
        exit 1
    fi

    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}✗ Input file not found: $INPUT_FILE${NC}"
        exit 1
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}✗ Backup file not found: $BACKUP_FILE${NC}"
        echo -e "${YELLOW}  Run '$0 backup' first or specify with -b${NC}"
        exit 1
    fi

    # Use kubeseal to decrypt (requires keys to be in cluster or use --recovery-unseal)
    echo -e "${YELLOW}⚠ Decryption requires keys to be in the cluster${NC}"
    echo -e "${YELLOW}  Run '$0 restore' first, or use kubeseal --recovery-unseal${NC}"
    echo ""
    echo -e "${CYAN}Attempting decryption...${NC}"

    if [ -n "$OUTPUT_FILE" ]; then
        kubeseal --recovery-unseal < "$INPUT_FILE" > "$OUTPUT_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Decryption failed${NC}"
            echo -e "${YELLOW}  Make sure keys are restored or use kubeseal directly with --recovery-private-key${NC}"
            exit 1
        }
        echo -e "${GREEN}✓ Decrypted secret saved to: $OUTPUT_FILE${NC}"
    else
        kubeseal --recovery-unseal < "$INPUT_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Decryption failed${NC}"
            exit 1
        }
    fi
}

# ============================================================================
# RE-ENCRYPT COMMAND
# ============================================================================
cmd_re_encrypt() {
    local NAMESPACE="$DEFAULT_WORKSPACE_NAMESPACE"
    local PC_CREDS_FILE="/Users/deepak.muley/ws/nkp/pc-creds.sh"
    local DOCKERHUB_CREDS_FILE="/Users/deepak.muley/ws/nkp/nkp-mgmt-clusterctl.sh"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Re-encrypt Sealed Secrets with New Credentials

Re-encrypts sealed secrets with credentials from credential files.

Usage:
    $0 re-encrypt [options]

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file
    -n, --namespace NAME     Namespace (default: $DEFAULT_WORKSPACE_NAMESPACE)
    -h, --help               Show this help message

Credentials are read from:
    PC: $PC_CREDS_FILE
    DockerHub: $DOCKERHUB_CREDS_FILE

Examples:
    $0 re-encrypt
    $0 re-encrypt -n my-namespace
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    print_header "Re-encrypt Sealed Secrets"
    check_prerequisites
    set_kubeconfig

    echo -e "${CYAN}Reading credentials from files...${NC}"

    # Read PC credentials
    if [ ! -f "$PC_CREDS_FILE" ]; then
        echo -e "${RED}✗ PC credentials file not found: $PC_CREDS_FILE${NC}"
        exit 1
    fi

    # Source the PC credentials file to get variables (use bash to source properly)
    eval "$(bash -c "source $PC_CREDS_FILE 2>/dev/null; echo 'PC_USERNAME='\${NUTANIX_USERNAME:-\${NUTANIX_USER}}; echo 'PC_PASSWORD='\$NUTANIX_PASSWORD; echo 'PC_ENDPOINT='\$NUTANIX_ENDPOINT; echo 'PC_PORT='\${NUTANIX_PORT:-9440}")"

    if [ -z "$PC_USERNAME" ] || [ -z "$PC_PASSWORD" ] || [ -z "$PC_ENDPOINT" ]; then
        echo -e "${RED}✗ Failed to read PC credentials from $PC_CREDS_FILE${NC}"
        echo -e "${YELLOW}  Trying alternative method...${NC}"
        # Alternative: parse the file directly
        PC_USERNAME=$(grep "NUTANIX_USERNAME=" "$PC_CREDS_FILE" | cut -d'"' -f2 || grep "NUTANIX_USER=" "$PC_CREDS_FILE" | cut -d'"' -f2)
        PC_PASSWORD=$(grep "NUTANIX_PASSWORD=" "$PC_CREDS_FILE" | cut -d'"' -f2)
        PC_ENDPOINT=$(grep "NUTANIX_ENDPOINT=" "$PC_CREDS_FILE" | cut -d'"' -f2)
        PC_PORT=$(grep "NUTANIX_PORT=" "$PC_CREDS_FILE" | cut -d'"' -f2 || echo "9440")
    fi

    if [ -z "$PC_USERNAME" ] || [ -z "$PC_PASSWORD" ] || [ -z "$PC_ENDPOINT" ]; then
        echo -e "${RED}✗ Failed to read PC credentials${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ PC credentials loaded${NC}"

    # Read DockerHub credentials
    if [ ! -f "$DOCKERHUB_CREDS_FILE" ]; then
        echo -e "${RED}✗ DockerHub credentials file not found: $DOCKERHUB_CREDS_FILE${NC}"
        exit 1
    fi

    # Extract DockerHub credentials (parse the file directly)
    DOCKERHUB_USERNAME=$(grep "DOCKER_HUB_USERNAME=" "$DOCKERHUB_CREDS_FILE" | cut -d'=' -f2 | tr -d ' ' || echo "")
    DOCKERHUB_PASSWORD=$(grep "DOCKER_HUB_PASSWORD=" "$DOCKERHUB_CREDS_FILE" | cut -d'"' -f2 || echo "")

    if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_PASSWORD" ]; then
        echo -e "${RED}✗ Failed to read DockerHub credentials from $DOCKERHUB_CREDS_FILE${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ DockerHub credentials loaded${NC}"
    echo ""

    echo -e "${CYAN}This will re-encrypt secrets in namespace: $NAMESPACE${NC}"
    echo -e "${CYAN}PC Endpoint: $PC_ENDPOINT:$PC_PORT${NC}"
    echo -e "${CYAN}PC Username: $PC_USERNAME${NC}"
    echo -e "${CYAN}DockerHub Username: $DOCKERHUB_USERNAME${NC}"
    echo ""

    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    echo ""
    echo -e "${CYAN}Re-encrypting secrets...${NC}"
    echo ""

    # Always use controller service to get the current public key
    KUBESEAL_ARGS="--controller-name=sealed-secrets-controller --controller-namespace=sealed-secrets-system"
    echo -e "${CYAN}Using sealed-secrets-controller service to get public key${NC}"
    echo ""

    # Re-encrypt each secret
    # PC credentials must be in the format expected by Nutanix Cluster API:
    # [{"type": "basic_auth", "data": {"prismCentral": {"username": "...", "password": "..."}}}]
    # Use pretty-printed JSON format to match working workload cluster
    PC_CREDS_JSON=$(echo '[
    {
        "type": "basic_auth",
        "data": {
            "prismCentral": {
                "username": "'"$PC_USERNAME"'",
                "password": "'"$PC_PASSWORD"'"
            }
        }
    }
]' | base64)
    # CSI credentials format: pc.dev.nkp.sh:9440:username:password
    CSI_KEY=$(echo -n "$PC_ENDPOINT:$PC_PORT:$PC_USERNAME:$PC_PASSWORD" | base64)

    for secret_info in \
        "dm-dev-pc-credentials:--from-literal=credentials=$PC_CREDS_JSON" \
        "dm-dev-image-registry-credentials:--from-literal=username=$DOCKERHUB_USERNAME --from-literal=password=$DOCKERHUB_PASSWORD" \
        "dm-dev-pc-credentials-for-csi:--from-literal=key=$CSI_KEY" \
        "dm-dev-pc-credentials-for-konnector-agent:--from-literal=username=$PC_USERNAME --from-literal=password=$PC_PASSWORD"; do

        SECRET_NAME=$(echo "$secret_info" | cut -d: -f1)
        SECRET_ARGS=$(echo "$secret_info" | cut -d: -f2-)

        echo -e "${CYAN}Re-encrypting: $SECRET_NAME${NC}"
        kubectl create secret generic "$SECRET_NAME" -n "$NAMESPACE" $SECRET_ARGS \
            --dry-run=client -o yaml | kubeseal $KUBESEAL_ARGS -o yaml > "$TEMP_DIR/$SECRET_NAME.yaml"

        kubectl apply -f "$TEMP_DIR/$SECRET_NAME.yaml" > /dev/null 2>&1
        echo -e "${GREEN}✓ $SECRET_NAME${NC}"
    done

    echo ""
    echo -e "${GREEN}✓ Re-encryption complete!${NC}"
    echo ""
    echo -e "${CYAN}Verifying...${NC}"
    sleep 5

    for secret in dm-dev-pc-credentials dm-dev-image-registry-credentials dm-dev-pc-credentials-for-csi dm-dev-pc-credentials-for-konnector-agent; do
        STATUS=$(kubectl get sealedsecret "$secret" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
            echo -e "${GREEN}✓ $secret: Synced${NC}"
        else
            ERROR=$(kubectl get sealedsecret "$secret" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Synced")].message}' 2>/dev/null || echo "")
            echo -e "${YELLOW}⚠ $secret: Not synced yet${NC}"
            if [ -n "$ERROR" ]; then
                echo -e "${YELLOW}    $ERROR${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${CYAN}Updating sealed secrets file in git...${NC}"
    SECRETS_FILE="region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/sealed-secrets/dm-dev-common-sealed-secrets.yaml"

    if [ -f "$SECRETS_FILE" ]; then
        # Get updated sealed secrets from cluster
        kubectl get sealedsecrets -n "$NAMESPACE" -o yaml > "$TEMP_DIR/all-sealed-secrets.yaml"

        # Extract only the 4 secrets we care about
        for secret in dm-dev-pc-credentials dm-dev-image-registry-credentials dm-dev-pc-credentials-for-csi dm-dev-pc-credentials-for-konnector-agent; do
            kubectl get sealedsecret "$secret" -n "$NAMESPACE" -o yaml >> "$TEMP_DIR/updated-secrets.yaml"
            echo "---" >> "$TEMP_DIR/updated-secrets.yaml"
        done

        # Remove trailing ---
        sed -i '' '$ { /^---$/d; }' "$TEMP_DIR/updated-secrets.yaml" 2>/dev/null || sed -i '$ { /^---$/d; }' "$TEMP_DIR/updated-secrets.yaml" 2>/dev/null || true

        # Create new file with header (clean YAML without metadata)
        {
            echo "# Common Sealed Secrets for all dev clusters"
            echo "# These secrets are shared across all dev clusters since they use the same infrastructure"
            echo "---"
            kubectl get sealedsecret dm-dev-pc-credentials -n "$NAMESPACE" -o yaml | \
                grep -v "creationTimestamp\|resourceVersion\|uid\|generation\|last-applied-configuration\|status:" | \
                sed '/^status:/,$d' | sed '/^  conditions:/,/^  observedGeneration:/d' | sed '/^  observedGeneration:/d'
            echo "---"
            kubectl get sealedsecret dm-dev-pc-credentials-for-csi -n "$NAMESPACE" -o yaml | \
                grep -v "creationTimestamp\|resourceVersion\|uid\|generation\|last-applied-configuration\|status:" | \
                sed '/^status:/,$d' | sed '/^  conditions:/,/^  observedGeneration:/d' | sed '/^  observedGeneration:/d'
            echo "---"
            kubectl get sealedsecret dm-dev-pc-credentials-for-konnector-agent -n "$NAMESPACE" -o yaml | \
                grep -v "creationTimestamp\|resourceVersion\|uid\|generation\|last-applied-configuration\|status:" | \
                sed '/^status:/,$d' | sed '/^  conditions:/,/^  observedGeneration:/d' | sed '/^  observedGeneration:/d'
            echo "---"
            kubectl get sealedsecret dm-dev-image-registry-credentials -n "$NAMESPACE" -o yaml | \
                grep -v "creationTimestamp\|resourceVersion\|uid\|generation\|last-applied-configuration\|status:" | \
                sed '/^status:/,$d' | sed '/^  conditions:/,/^  observedGeneration:/d' | sed '/^  observedGeneration:/d'
        } > "$SECRETS_FILE"

        echo -e "${GREEN}✓ Updated: $SECRETS_FILE${NC}"
        echo ""
        echo -e "${CYAN}Next step: Review and commit the updated file${NC}"
        echo -e "${YELLOW}  git add $SECRETS_FILE${NC}"
        echo -e "${YELLOW}  git commit -m 'Re-encrypt sealed secrets with current keys'${NC}"
    else
        echo -e "${YELLOW}⚠ Secrets file not found: $SECRETS_FILE${NC}"
        echo -e "${CYAN}  You can manually update it with:${NC}"
        echo -e "${GREEN}    kubectl get sealedsecrets -n $NAMESPACE -o yaml > $SECRETS_FILE${NC}"
    fi
}

# ============================================================================
# STATUS COMMAND
# ============================================================================
cmd_status() {
    local NAMESPACE=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Check Sealed Secrets Status

Shows the status of all sealed secrets in the cluster.

Usage:
    $0 status [options]

Options:
    -k, --kubeconfig PATH    Path to kubeconfig file
    -n, --namespace NAME     Namespace to check (default: all namespaces)
    -h, --help               Show this help message

Examples:
    $0 status
    $0 status -n dm-dev-workspace
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    check_prerequisites
    set_kubeconfig

    print_header "Sealed Secrets Status"

    NS_FILTER=""
    if [ -n "$NAMESPACE" ]; then
        NS_FILTER="-n $NAMESPACE"
    fi

    echo -e "${CYAN}Checking sealed secrets...${NC}"
    echo ""

    FAILED_COUNT=0
    SUCCESS_COUNT=0
    TOTAL_COUNT=0

    for ns in $(kubectl get namespaces $NS_FILTER -o name 2>/dev/null | cut -d/ -f2); do
        SEALED_SECRETS=$(kubectl get sealedsecrets -n "$ns" -o name 2>/dev/null || true)

        if [ -n "$SEALED_SECRETS" ]; then
            echo -e "${BLUE}Namespace: $ns${NC}"
            while IFS= read -r sealed_secret; do
                if [ -z "$sealed_secret" ]; then
                    continue
                fi
                TOTAL_COUNT=$((TOTAL_COUNT + 1))
                SECRET_NAME=$(echo "$sealed_secret" | cut -d/ -f2)
                STATUS=$(kubectl get sealedsecret "$SECRET_NAME" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null || echo "Unknown")
                ERROR=$(kubectl get sealedsecret "$SECRET_NAME" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Synced")].message}' 2>/dev/null || echo "")

                if [ "$STATUS" = "True" ]; then
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    echo -e "  ${GREEN}✓ $SECRET_NAME${NC}"
                else
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    echo -e "  ${RED}✗ $SECRET_NAME${NC}"
                    if [ -n "$ERROR" ]; then
                        echo -e "    ${YELLOW}  $ERROR${NC}"
                    fi
                fi
            done <<< "$SEALED_SECRETS"
            echo ""
        fi
    done

    echo -e "${CYAN}Summary:${NC}"
    echo -e "  Total: $TOTAL_COUNT"
    echo -e "  ${GREEN}Synced: $SUCCESS_COUNT${NC}"
    echo -e "  ${RED}Failed: $FAILED_COUNT${NC}"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    if [ $# -eq 0 ]; then
        cat << EOF
Sealed Secrets Management Tool

Usage:
    $0 <command> [options]

Commands:
    backup          Backup sealed-secrets controller keys (public & private)
    restore         Restore sealed-secrets keys from backup
    encrypt         Encrypt a plaintext secret YAML file
    decrypt         Decrypt a sealed secret YAML file (requires keys)
    re-encrypt      Re-encrypt secrets with new credentials
    status          Check status of sealed secrets in cluster

Use '$0 <command> --help' for command-specific help.

Examples:
    $0 backup
    $0 restore
    $0 encrypt -f secret.yaml -o sealed-secret.yaml
    $0 decrypt -f sealed-secret.yaml -o secret.yaml
    $0 re-encrypt
    $0 status
EOF
        exit 0
    fi

    COMMAND=$1
    shift

    case $COMMAND in
        backup)
            cmd_backup "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        encrypt)
            cmd_encrypt "$@"
            ;;
        decrypt)
            cmd_decrypt "$@"
            ;;
        re-encrypt)
            cmd_re_encrypt "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        -h|--help)
            main
            ;;
        *)
            echo -e "${RED}Error: Unknown command: $COMMAND${NC}"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"

