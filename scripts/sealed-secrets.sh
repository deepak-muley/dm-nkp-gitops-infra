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
#   backup                        Backup sealed-secrets controller keys (public & private)
#   restore                       Restore sealed-secrets keys from backup
#   generate-cluster-sealed-secrets  Generate SealedSecrets for cluster credentials (PC, Konnector, CSI, Image Registry)
#   generate-ndk-sealed-secrets    Generate SealedSecret for NDK image pull credentials
#   generate-nai-sealed-secrets    Generate SealedSecret for NAI image pull credentials
#   decrypt                       Decrypt a sealed secret YAML file (requires keys)
#   re-encrypt                    Re-encrypt secrets with new credentials
#   status                        Check status of sealed secrets in cluster
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
# Get repo root (assuming script is in scripts/ directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_DO_NOT_CHECKIN_DIR="$REPO_ROOT/do-not-checkin-folder"
# Use do-not-checkin-folder as default backup directory (all within repo)
DEFAULT_BACKUP_DIR="$DEFAULT_DO_NOT_CHECKIN_DIR"
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
# DECRYPT COMMAND
# ============================================================================
cmd_decrypt() {
    local INPUT_FILE=""
    local OUTPUT_FILE=""
    local BACKUP_FILE=""
    local KEY_STORAGE_DIR="$DEFAULT_DO_NOT_CHECKIN_DIR"
    local CLUSTER_NAME=""
    local PRIVATE_KEY_FILE=""
    local SEALED_SECRETS_NS="sealed-secrets-system"

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
Decrypt a SealedSecret

Decrypts a SealedSecret YAML file to plaintext using private keys from the cluster.

Usage:
    $0 decrypt [options]

Options:
    -f, --file PATH          Path to SealedSecret YAML file
    -o, --output PATH        Output file (default: stdout)
    -b, --backup PATH        Path to keys backup file (optional, will fetch from cluster if not provided)
    -k, --kubeconfig PATH    Path to kubeconfig file (required if not using default)
    --cluster-name NAME      Cluster name for key file naming (default: auto-detect from kubeconfig)
    -h, --help               Show this help message

Examples:
    $0 decrypt -f sealed-secret.yaml -o secret.yaml
    $0 decrypt -f sealed-secret.yaml -k /path/to/kubeconfig -o secret.yaml
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
    set_kubeconfig

    if [ -z "$INPUT_FILE" ]; then
        echo -e "${RED}✗ Input file required (use -f or pipe from stdin)${NC}"
        exit 1
    fi

    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}✗ Input file not found: $INPUT_FILE${NC}"
        exit 1
    fi

    print_header "Decrypt Sealed Secret"

    # If backup file not provided, fetch from cluster
    if [[ -z "$BACKUP_FILE" ]]; then
        # Determine cluster name for key file naming
        if [[ -z "$CLUSTER_NAME" ]]; then
            CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "default")
            CLUSTER_NAME=$(echo "$CLUSTER_NAME" | sed 's|https\?://||' | sed 's|:.*||' | sed 's|[^a-zA-Z0-9-]|-|g' | head -c 50)
            if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
                CLUSTER_NAME="cluster-$(date +%Y%m%d-%H%M%S)"
            fi
        fi

        PRIVATE_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml"

        # Check if key file exists locally
        if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
            echo -e "${CYAN}Private key not found locally. Fetching from cluster...${NC}"

            if ! kubectl get namespace "$SEALED_SECRETS_NS" &> /dev/null; then
                echo -e "${RED}✗ Namespace $SEALED_SECRETS_NS does not exist${NC}"
                exit 1
            fi

            mkdir -p "$KEY_STORAGE_DIR"

            # Fetch the active private key from cluster
            local ACTIVE_KEY_NAME=$(kubectl get secret -n "$SEALED_SECRETS_NS" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

            if [[ -z "$ACTIVE_KEY_NAME" ]]; then
                echo -e "${RED}✗ No active sealed-secrets key found in cluster${NC}"
                exit 1
            fi

            echo -e "${YELLOW}  Using active key: $ACTIVE_KEY_NAME${NC}"
            echo -e "${YELLOW}  Fetching private key to: $PRIVATE_KEY_FILE${NC}"
            kubectl get secret "$ACTIVE_KEY_NAME" -n "$SEALED_SECRETS_NS" -o yaml > "$PRIVATE_KEY_FILE" 2>/dev/null || {
                echo -e "${RED}✗ Failed to fetch private key${NC}"
                exit 1
            }
            echo -e "${GREEN}✓ Private key fetched successfully${NC}"
        else
            echo -e "${CYAN}Using existing private key: $PRIVATE_KEY_FILE${NC}"
        fi

        BACKUP_FILE="$PRIVATE_KEY_FILE"
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}✗ Private key file not found: $BACKUP_FILE${NC}"
        exit 1
    fi

    echo -e "${CYAN}Decrypting using private key: $BACKUP_FILE${NC}"
    echo ""

    # Extract private key from the backup file and use it for decryption
    local TEMP_KEY_DIR=$(mktemp -d)
    local TEMP_KEY_FILE="$TEMP_KEY_DIR/tls.key"

    # Extract tls.key from the backup YAML
    # First try if it's a single Secret
    kubectl get secret -f "$BACKUP_FILE" -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > "$TEMP_KEY_FILE" 2>/dev/null || {
        # Try parsing as YAML List (items array)
        yq eval '.items[0].data."tls.key"' "$BACKUP_FILE" 2>/dev/null | base64 -d > "$TEMP_KEY_FILE" 2>/dev/null || {
            # Try parsing as single Secret YAML
            yq eval '.data."tls.key"' "$BACKUP_FILE" 2>/dev/null | base64 -d > "$TEMP_KEY_FILE" 2>/dev/null || {
                echo -e "${RED}✗ Failed to extract private key from backup file${NC}"
                echo -e "${YELLOW}  File format may be incorrect. Expected Secret YAML with tls.key in data field.${NC}"
                rm -rf "$TEMP_KEY_DIR"
                exit 1
            }
        }
    }

    if [ ! -s "$TEMP_KEY_FILE" ]; then
        echo -e "${RED}✗ Extracted private key is empty${NC}"
        rm -rf "$TEMP_KEY_DIR"
        exit 1
    fi

    echo -e "${CYAN}Decrypting using private key from: $BACKUP_FILE${NC}"

    if [ -n "$OUTPUT_FILE" ]; then
        kubeseal --recovery-unseal --recovery-private-key="$TEMP_KEY_FILE" < "$INPUT_FILE" > "$OUTPUT_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Decryption failed${NC}"
            echo -e "${YELLOW}  Make sure the private key matches the sealed secret${NC}"
            echo -e "${YELLOW}  Private key used: $BACKUP_FILE${NC}"
            rm -rf "$TEMP_KEY_DIR"
            exit 1
        }
        echo -e "${GREEN}✓ Decrypted secret saved to: $OUTPUT_FILE${NC}"
        echo -e "${CYAN}  Used private key: $BACKUP_FILE${NC}"
    else
        kubeseal --recovery-unseal --recovery-private-key="$TEMP_KEY_FILE" < "$INPUT_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Decryption failed${NC}"
            echo -e "${YELLOW}  Private key used: $BACKUP_FILE${NC}"
            rm -rf "$TEMP_KEY_DIR"
            exit 1
        }
    fi

    rm -rf "$TEMP_KEY_DIR"
}

# ============================================================================
# RE-ENCRYPT COMMAND
# ============================================================================
cmd_re_encrypt() {
    local NAMESPACE="$DEFAULT_WORKSPACE_NAMESPACE"
    local SOURCE_SECRETS_FILE="do-not-checkin-folder/dm-dev-common-secrets.yaml"
    local PC_USERNAME=""
    local PC_PASSWORD=""
    local PC_ENDPOINT=""
    local PC_PORT="9440"
    local DOCKERHUB_USERNAME=""
    local DOCKERHUB_PASSWORD=""

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
            --pc-username)
                PC_USERNAME="$2"
                shift 2
                ;;
            --pc-password)
                PC_PASSWORD="$2"
                shift 2
                ;;
            --pc-endpoint)
                PC_ENDPOINT="$2"
                shift 2
                ;;
            --pc-port)
                PC_PORT="$2"
                shift 2
                ;;
            --dockerhub-username)
                DOCKERHUB_USERNAME="$2"
                shift 2
                ;;
            --dockerhub-password)
                DOCKERHUB_PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Re-encrypt Sealed Secrets with New Credentials

Re-encrypts sealed secrets with credentials from do-not-checkin-folder or user input.

Usage:
    $0 re-encrypt [options]

Options:
    -k, --kubeconfig PATH         Path to kubeconfig file
    -n, --namespace NAME          Namespace (default: $DEFAULT_WORKSPACE_NAMESPACE)
    --pc-username USER            Prism Central username (optional, overrides file)
    --pc-password PASS            Prism Central password (optional, overrides file)
    --pc-endpoint ENDPOINT        Prism Central endpoint (optional, overrides file)
    --pc-port PORT                Prism Central port (default: 9440)
    --dockerhub-username USER     DockerHub username (optional, overrides file)
    --dockerhub-password PASS     DockerHub password (optional, overrides file)
    -h, --help                    Show this help message

Credentials are read from:
    $SOURCE_SECRETS_FILE (decodes base64 from Secret YAML)

    Or provide credentials via command-line options (--pc-username, --pc-password, etc.)

Examples:
    $0 re-encrypt
    $0 re-encrypt -n my-namespace
    $0 re-encrypt --pc-username "user" --pc-password "pass" --pc-endpoint "pc.example.com"
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

    echo -e "${CYAN}Reading credentials...${NC}"

    # Read from source secrets file if credentials not provided via command line
    if [ -z "$PC_USERNAME" ] || [ -z "$PC_PASSWORD" ] || [ -z "$PC_ENDPOINT" ]; then
        if [ ! -f "$SOURCE_SECRETS_FILE" ]; then
            echo -e "${RED}✗ Source secrets file not found: $SOURCE_SECRETS_FILE${NC}"
            echo -e "${YELLOW}  Please provide credentials via command-line options or ensure file exists${NC}"
            exit 1
        fi

        echo -e "${CYAN}  Reading from source secrets file: $SOURCE_SECRETS_FILE${NC}"
        # Decode credentials from the source file
        # The file has secrets separated by ---, credentials field comes before name
        # Get the first credentials field (for dm-dev-pc-credentials)
        PC_CREDS_B64=$(grep "^  credentials:" "$SOURCE_SECRETS_FILE" | head -1 | awk '{print $2}')
        if [ -n "$PC_CREDS_B64" ]; then
            PC_CREDS_JSON_DECODED=$(echo "$PC_CREDS_B64" | base64 -d 2>/dev/null)
            if [ -n "$PC_CREDS_JSON_DECODED" ]; then
                if [ -z "$PC_USERNAME" ]; then
                    PC_USERNAME=$(echo "$PC_CREDS_JSON_DECODED" | jq -r '.[0].data.prismCentral.username' 2>/dev/null)
                fi
                if [ -z "$PC_PASSWORD" ]; then
                    PC_PASSWORD=$(echo "$PC_CREDS_JSON_DECODED" | jq -r '.[0].data.prismCentral.password' 2>/dev/null)
                fi
                # Extract endpoint from CSI key (first key field)
                if [ -z "$PC_ENDPOINT" ]; then
                    CSI_KEY_B64=$(grep "^  key:" "$SOURCE_SECRETS_FILE" | head -1 | awk '{print $2}')
                    if [ -n "$CSI_KEY_B64" ]; then
                        CSI_KEY_DECODED=$(echo "$CSI_KEY_B64" | base64 -d 2>/dev/null)
                        if [ -n "$CSI_KEY_DECODED" ]; then
                            PC_ENDPOINT=$(echo "$CSI_KEY_DECODED" | cut -d: -f1)
                            if [ -z "$PC_PORT" ] || [ "$PC_PORT" = "9440" ]; then
                                PC_PORT=$(echo "$CSI_KEY_DECODED" | cut -d: -f2)
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    # Read DockerHub credentials from source file if not provided
    if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_PASSWORD" ]; then
        if [ -f "$SOURCE_SECRETS_FILE" ]; then
            # DockerHub credentials are in dm-dev-image-registry-credentials secret
            DOCKERHUB_USERNAME_B64=$(grep -A 5 "name: dm-dev-image-registry-credentials" "$SOURCE_SECRETS_FILE" | grep "^  username:" | awk '{print $2}')
            DOCKERHUB_PASSWORD_B64=$(grep -A 5 "name: dm-dev-image-registry-credentials" "$SOURCE_SECRETS_FILE" | grep "^  password:" | awk '{print $2}')
            if [ -n "$DOCKERHUB_USERNAME_B64" ] && [ -z "$DOCKERHUB_USERNAME" ]; then
                DOCKERHUB_USERNAME=$(echo "$DOCKERHUB_USERNAME_B64" | base64 -d 2>/dev/null)
            fi
            if [ -n "$DOCKERHUB_PASSWORD_B64" ] && [ -z "$DOCKERHUB_PASSWORD" ]; then
                DOCKERHUB_PASSWORD=$(echo "$DOCKERHUB_PASSWORD_B64" | base64 -d 2>/dev/null)
            fi
        fi
    fi

    if [ -z "$PC_USERNAME" ] || [ -z "$PC_PASSWORD" ] || [ -z "$PC_ENDPOINT" ]; then
        echo -e "${RED}✗ Failed to read PC credentials${NC}"
        echo -e "${YELLOW}  Please provide via --pc-username, --pc-password, --pc-endpoint options${NC}"
        echo -e "${YELLOW}  Or ensure $SOURCE_SECRETS_FILE exists and contains valid credentials${NC}"
        exit 1
    fi

    if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_PASSWORD" ]; then
        echo -e "${RED}✗ Failed to read DockerHub credentials${NC}"
        echo -e "${YELLOW}  Please provide via --dockerhub-username, --dockerhub-password options${NC}"
        echo -e "${YELLOW}  Or ensure $SOURCE_SECRETS_FILE exists and contains valid credentials${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ PC credentials loaded${NC}"
    echo -e "${GREEN}✓ DockerHub credentials loaded${NC}"

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

    # Use public key from do-not-checkin-folder (always up to date with mgmt cluster)
    PUBLIC_KEY_FILE="do-not-checkin-folder/sealed-secrets-public-key-dm-nkp-mgmt-1.pem"
    if [ ! -f "$PUBLIC_KEY_FILE" ]; then
        echo -e "${RED}✗ Public key file not found: $PUBLIC_KEY_FILE${NC}"
        echo -e "${YELLOW}  Falling back to controller service...${NC}"
        KUBESEAL_ARGS="--controller-name=sealed-secrets-controller --controller-namespace=sealed-secrets-system"
    else
        KUBESEAL_ARGS="--cert=$PUBLIC_KEY_FILE"
        echo -e "${CYAN}Using public key from: $PUBLIC_KEY_FILE${NC}"
        echo -e "${GREEN}✓ This ensures secrets are encrypted with the latest mgmt cluster keys${NC}"
    fi
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
# GENERATE-CLUSTER-SEALED-SECRETS COMMAND
# ============================================================================
cmd_generate_cluster_sealed_secrets() {
    # Default paths
    local INPUT_FILE="${INPUT_FILE:-/Users/deepak.muley/go/src/github.com/deepak-muley/dm-nkp-gitops-infra/do-not-checkin-folder/dm-dev-common-secrets.yaml}"
    local OUTPUT_FILE="${OUTPUT_FILE:-/Users/deepak.muley/go/src/github.com/deepak-muley/dm-nkp-gitops-infra/region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/sealed-secrets/dm-dev-common-sealed-secrets.yaml}"
    local SEALED_SECRETS_NS="sealed-secrets-system"
    local SEALED_SECRETS_CTRL="sealed-secrets-controller"
    local KEY_STORAGE_DIR="$DEFAULT_DO_NOT_CHECKIN_DIR"
    local CLUSTER_NAME=""
    local PRIVATE_KEY_FILE=""
    local PUBLIC_KEY_FILE=""

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
            --pc-credentials.username)
                PC_CREDS_USERNAME="$2"
                shift 2
                ;;
            --pc-credentials.password)
                PC_CREDS_PASSWORD="$2"
                shift 2
                ;;
            --konnector-agent.username)
                KONNECTOR_USERNAME="$2"
                shift 2
                ;;
            --konnector-agent.password)
                KONNECTOR_PASSWORD="$2"
                shift 2
                ;;
            --csi.key)
                CSI_KEY="$2"
                shift 2
                ;;
            --image-registry.username)
                IMAGE_REGISTRY_USERNAME="$2"
                shift 2
                ;;
            --image-registry.password)
                IMAGE_REGISTRY_PASSWORD="$2"
                shift 2
                ;;
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
Generate Cluster Sealed Secrets

Generates SealedSecrets for cluster credentials (PC, Konnector, CSI, Image Registry) from plain text inputs or processes a file containing Secrets.
All inputs are in plain text - the script handles base64 encoding internally.

Usage:
    $0 generate-cluster-sealed-secrets [options]

Options:
    -f, --file PATH                    Input file with Secret YAMLs (Option 1)
    -o, --output PATH                  Output file for SealedSecrets (default: region-usa/az1/.../dm-dev-common-sealed-secrets.yaml)

    Option 2 - Plain text credentials (all values are plain text):
    --pc-credentials.username USER    Prism Central username (plain text)
    --pc-credentials.password PASS    Prism Central password (plain text)
    --konnector-agent.username USER   Konnector agent username (plain text)
    --konnector-agent.password PASS   Konnector agent password (plain text)
    --csi.key KEY                      CSI key in format: endpoint:port:username:password (plain text)
    --image-registry.username USER    Image registry username (plain text)
    --image-registry.password PASS    Image registry password (plain text)

    -k, --kubeconfig PATH             Path to kubeconfig file
    --cluster-name NAME               Cluster name for key file naming (default: auto-detect from kubeconfig)
    -h, --help                        Show this help message

Modes:
    Option 1: Process file
        Reads a file containing Secret YAMLs (separated by ---), seals each Secret,
        and writes SealedSecrets to output file.

        Example:
            $0 generate-cluster-sealed-secrets -f secrets.yaml -o sealed-secrets.yaml

    Option 2: Create from arguments
        Reads the default input file structure, updates secrets with provided
        plain text values, seals them, and writes to output file.

        Example:
            $0 generate-cluster-sealed-secrets \\
                --pc-credentials.username "user" \\
                --pc-credentials.password "pass" \\
                --output sealed-secrets.yaml

Note: All input values should be in plain text. The script will:
  - For pc-credentials: Create JSON structure and base64 encode it
  - For other secrets: Base64 encode the plain text values
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

    if ! command -v yq &> /dev/null; then
        echo -e "${RED}✗ yq not found. Please install it:${NC}"
        echo -e "${YELLOW}  brew install yq${NC}"
        exit 1
    fi

    if ! kubectl get namespace "$SEALED_SECRETS_NS" &> /dev/null; then
        echo -e "${RED}✗ Namespace $SEALED_SECRETS_NS does not exist${NC}"
        exit 1
    fi

    print_header "Generate Sealed Secrets"

    # Determine cluster name for key file naming
    if [[ -z "$CLUSTER_NAME" ]]; then
        # Try to extract cluster name from kubeconfig context
        CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "default")
        # Clean up cluster name (remove protocol, port, etc.)
        CLUSTER_NAME=$(echo "$CLUSTER_NAME" | sed 's|https\?://||' | sed 's|:.*||' | sed 's|[^a-zA-Z0-9-]|-|g' | head -c 50)
        if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
            CLUSTER_NAME="cluster-$(date +%Y%m%d-%H%M%S)"
        fi
    fi

    # Set key file paths - use keys from do-not-checkin-folder (always up to date)
    # Default to dm-nkp-mgmt-1 if cluster name not specified
    if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
        CLUSTER_NAME="dm-nkp-mgmt-1"
    fi
    PRIVATE_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml"
    PUBLIC_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-public-key-${CLUSTER_NAME}.pem"

    # Ensure do-not-checkin-folder exists
    mkdir -p "$KEY_STORAGE_DIR"

    # Use public key from do-not-checkin-folder (always up to date with mgmt cluster)
    if [ ! -f "$PUBLIC_KEY_FILE" ]; then
        echo -e "${RED}✗ Public key file not found: $PUBLIC_KEY_FILE${NC}"
        echo -e "${YELLOW}  Falling back to fetching from cluster...${NC}"
        # Fetch the active private key from cluster
        ACTIVE_KEY_NAME=$(kubectl get secret -n "$SEALED_SECRETS_NS" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$ACTIVE_KEY_NAME" ]]; then
            echo -e "${RED}✗ No active sealed-secrets key found in cluster${NC}"
            exit 1
        fi
        echo -e "${YELLOW}  Fetching public key from cluster...${NC}"
        kubeseal --fetch-cert \
            --controller-name="$SEALED_SECRETS_CTRL" \
            --controller-namespace="$SEALED_SECRETS_NS" \
            > "$PUBLIC_KEY_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Failed to fetch public key${NC}"
            exit 1
        }
    else
        echo -e "${CYAN}Using public key from: $PUBLIC_KEY_FILE${NC}"
        echo -e "${GREEN}✓ This ensures secrets are encrypted with the latest mgmt cluster keys${NC}"
    fi
    echo ""

    # Function to seal a secret from YAML using the fetched public key
    seal_secret_from_yaml() {
        local secret_yaml="$1"
        local temp_file=$(mktemp)
        echo "$secret_yaml" > "$temp_file"
        kubeseal \
            --format=yaml \
            --cert="$PUBLIC_KEY_FILE" \
            < "$temp_file"
        rm -f "$temp_file"
    }

    # Option 1: Process file
    if [[ -n "${INPUT_FILE:-}" ]] && [[ -f "$INPUT_FILE" ]] && [[ -z "${PC_CREDS_USERNAME:-}" ]]; then
        echo -e "${CYAN}Processing file: $INPUT_FILE${NC}"
        local temp_yaml=$(mktemp)
        local sealed_secrets=()
        local doc=""

        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "---" ]]; then
                if [[ -n "$doc" ]]; then
                    echo "$doc" > "$temp_yaml"
                    local kind=$(yq '.kind // ""' "$temp_yaml" 2>/dev/null || echo "")
                    if [[ "$kind" == "Secret" ]]; then
                        local secret_name=$(yq '.metadata.name // ""' "$temp_yaml" 2>/dev/null || echo "")
                        if [[ -n "$secret_name" ]]; then
                            echo -e "${YELLOW}  Sealing secret: $secret_name${NC}"
                            local sealed=$(seal_secret_from_yaml "$doc")
                            sealed_secrets+=("$sealed")
                        fi
                    fi
                fi
                doc=""
            else
                if [[ -n "$doc" ]]; then
                    doc+=$'\n'"$line"
                else
                    doc="$line"
                fi
            fi
        done < "$INPUT_FILE"

        # Process last document
        if [[ -n "$doc" ]]; then
            echo "$doc" > "$temp_yaml"
            local kind=$(yq '.kind // ""' "$temp_yaml" 2>/dev/null || echo "")
            if [[ "$kind" == "Secret" ]]; then
                local secret_name=$(yq '.metadata.name // ""' "$temp_yaml" 2>/dev/null || echo "")
                if [[ -n "$secret_name" ]]; then
                    echo -e "${YELLOW}  Sealing secret: $secret_name${NC}"
                    local sealed=$(seal_secret_from_yaml "$doc")
                    sealed_secrets+=("$sealed")
                fi
            fi
        fi

        rm -f "$temp_yaml"

        > "$OUTPUT_FILE"
        for i in "${!sealed_secrets[@]}"; do
            echo "${sealed_secrets[$i]}"
            if [[ $i -lt $((${#sealed_secrets[@]} - 1)) ]]; then
                echo "---"
            fi
        done > "$OUTPUT_FILE"

        echo -e "${GREEN}✓ Sealed secrets written to: $OUTPUT_FILE${NC}"
        echo ""
        echo -e "${CYAN}Key Information:${NC}"
        echo -e "  Private key: $PRIVATE_KEY_FILE"
        echo -e "  Public key: $PUBLIC_KEY_FILE"
        echo -e "  Active key name: $ACTIVE_KEY_NAME"
        return 0
    fi

    # Option 2: Create from arguments
    echo -e "${CYAN}Creating secrets from command-line arguments${NC}"

    local DEFAULT_INPUT_FILE="/Users/deepak.muley/go/src/github.com/deepak-muley/dm-nkp-gitops-infra/do-not-checkin-folder/dm-dev-common-secrets.yaml"
    if [[ ! -f "$DEFAULT_INPUT_FILE" ]]; then
        echo -e "${RED}✗ Input file does not exist: $DEFAULT_INPUT_FILE${NC}"
        exit 1
    fi

    local temp_yaml=$(mktemp)
    local temp_updated=$(mktemp)
    local secrets_yaml=""
    local doc=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "---" ]]; then
            if [[ -n "$doc" ]]; then
                echo "$doc" > "$temp_yaml"
                local kind=$(yq '.kind // ""' "$temp_yaml" 2>/dev/null || echo "")
                if [[ "$kind" == "Secret" ]]; then
                    local secret_name=$(yq '.metadata.name // ""' "$temp_yaml" 2>/dev/null || echo "")
                    if [[ -n "$secret_name" ]]; then
                        cp "$temp_yaml" "$temp_updated"

                        case "$secret_name" in
                            dm-dev-pc-credentials)
                                if [[ -n "${PC_CREDS_USERNAME:-}" ]] && [[ -n "${PC_CREDS_PASSWORD:-}" ]]; then
                                    local creds_json=$(echo -n "[{\"type\":\"basic_auth\",\"data\":{\"prismCentral\":{\"username\":\"${PC_CREDS_USERNAME}\",\"password\":\"${PC_CREDS_PASSWORD}\"}}}]" | base64 | tr -d '\n')
                                    yq eval ".data.credentials = \"$creds_json\"" -i "$temp_updated"
                                    echo -e "${YELLOW}  Updated $secret_name${NC}"
                                fi
                                ;;
                            dm-dev-pc-credentials-for-konnector-agent)
                                if [[ -n "${KONNECTOR_USERNAME:-}" ]] && [[ -n "${KONNECTOR_PASSWORD:-}" ]]; then
                                    local user_b64=$(echo -n "${KONNECTOR_USERNAME}" | base64 | tr -d '\n')
                                    local pass_b64=$(echo -n "${KONNECTOR_PASSWORD}" | base64 | tr -d '\n')
                                    yq eval ".data.username = \"$user_b64\" | .data.password = \"$pass_b64\"" -i "$temp_updated"
                                    echo -e "${YELLOW}  Updated $secret_name${NC}"
                                fi
                                ;;
                            dm-dev-pc-credentials-for-csi)
                                if [[ -n "${CSI_KEY:-}" ]]; then
                                    local key_b64=$(echo -n "${CSI_KEY}" | base64 | tr -d '\n')
                                    yq eval ".data.key = \"$key_b64\"" -i "$temp_updated"
                                    echo -e "${YELLOW}  Updated $secret_name${NC}"
                                fi
                                ;;
                            dm-dev-image-registry-credentials)
                                if [[ -n "${IMAGE_REGISTRY_USERNAME:-}" ]] && [[ -n "${IMAGE_REGISTRY_PASSWORD:-}" ]]; then
                                    local user_b64=$(echo -n "${IMAGE_REGISTRY_USERNAME}" | base64 | tr -d '\n')
                                    local pass_b64=$(echo -n "${IMAGE_REGISTRY_PASSWORD}" | base64 | tr -d '\n')
                                    yq eval ".data.username = \"$user_b64\" | .data.password = \"$pass_b64\"" -i "$temp_updated"
                                    echo -e "${YELLOW}  Updated $secret_name${NC}"
                                fi
                                ;;
                        esac

                        echo -e "${YELLOW}  Sealing secret: $secret_name${NC}"
                        local sealed=$(seal_secret_from_yaml "$(cat "$temp_updated")")
                        secrets_yaml+="$sealed"$'\n'"---"$'\n'
                    fi
                fi
            fi
            doc=""
        else
            if [[ -n "$doc" ]]; then
                doc+=$'\n'"$line"
            else
                doc="$line"
            fi
        fi
    done < "$DEFAULT_INPUT_FILE"

    # Process last document
    if [[ -n "$doc" ]]; then
        echo "$doc" > "$temp_yaml"
        local kind=$(yq '.kind // ""' "$temp_yaml" 2>/dev/null || echo "")
        if [[ "$kind" == "Secret" ]]; then
            local secret_name=$(yq '.metadata.name // ""' "$temp_yaml" 2>/dev/null || echo "")
            if [[ -n "$secret_name" ]]; then
                cp "$temp_yaml" "$temp_updated"

                case "$secret_name" in
                    dm-dev-pc-credentials)
                        if [[ -n "${PC_CREDS_USERNAME:-}" ]] && [[ -n "${PC_CREDS_PASSWORD:-}" ]]; then
                            local creds_json=$(echo -n "[{\"type\":\"basic_auth\",\"data\":{\"prismCentral\":{\"username\":\"${PC_CREDS_USERNAME}\",\"password\":\"${PC_CREDS_PASSWORD}\"}}}]" | base64 | tr -d '\n')
                            yq eval ".data.credentials = \"$creds_json\"" -i "$temp_updated"
                            echo -e "${YELLOW}  Updated $secret_name${NC}"
                        fi
                        ;;
                    dm-dev-pc-credentials-for-konnector-agent)
                        if [[ -n "${KONNECTOR_USERNAME:-}" ]] && [[ -n "${KONNECTOR_PASSWORD:-}" ]]; then
                            local user_b64=$(echo -n "${KONNECTOR_USERNAME}" | base64 | tr -d '\n')
                            local pass_b64=$(echo -n "${KONNECTOR_PASSWORD}" | base64 | tr -d '\n')
                            yq eval ".data.username = \"$user_b64\" | .data.password = \"$pass_b64\"" -i "$temp_updated"
                            echo -e "${YELLOW}  Updated $secret_name${NC}"
                        fi
                        ;;
                    dm-dev-pc-credentials-for-csi)
                        if [[ -n "${CSI_KEY:-}" ]]; then
                            local key_b64=$(echo -n "${CSI_KEY}" | base64 | tr -d '\n')
                            yq eval ".data.key = \"$key_b64\"" -i "$temp_updated"
                            echo -e "${YELLOW}  Updated $secret_name${NC}"
                        fi
                        ;;
                    dm-dev-image-registry-credentials)
                        if [[ -n "${IMAGE_REGISTRY_USERNAME:-}" ]] && [[ -n "${IMAGE_REGISTRY_PASSWORD:-}" ]]; then
                            local user_b64=$(echo -n "${IMAGE_REGISTRY_USERNAME}" | base64 | tr -d '\n')
                            local pass_b64=$(echo -n "${IMAGE_REGISTRY_PASSWORD}" | base64 | tr -d '\n')
                            yq eval ".data.username = \"$user_b64\" | .data.password = \"$pass_b64\"" -i "$temp_updated"
                            echo -e "${YELLOW}  Updated $secret_name${NC}"
                        fi
                        ;;
                esac

                echo -e "${YELLOW}  Sealing secret: $secret_name${NC}"
                local sealed=$(seal_secret_from_yaml "$(cat "$temp_updated")")
                secrets_yaml+="$sealed"
            fi
        fi
    fi

    rm -f "$temp_yaml" "$temp_updated"

    # Remove trailing ---
    secrets_yaml=$(echo -n "$secrets_yaml" | sed '$ { /^---$/d; }')

    echo -e "${CYAN}Writing SealedSecrets to: $OUTPUT_FILE${NC}"
    echo -n "$secrets_yaml" > "$OUTPUT_FILE"

    echo -e "${GREEN}✓ Sealed secrets written to: $OUTPUT_FILE${NC}"
    echo ""
    echo -e "${CYAN}Key Information:${NC}"
    echo -e "  Private key: $PRIVATE_KEY_FILE"
    echo -e "  Public key: $PUBLIC_KEY_FILE"
    echo -e "  Active key name: $ACTIVE_KEY_NAME"
}

# ============================================================================
# GENERATE-NDK-SEALED-SECRETS COMMAND
# ============================================================================
cmd_generate_ndk_sealed_secrets() {
    local USERNAME=""
    local PASSWORD=""
    local REGISTRY_URL="${REGISTRY_URL:-registry.nutanix.com}"
    local INPUT_FILE=""
    local OUTPUT_FILE="/Users/deepak.muley/go/src/github.com/deepak-muley/dm-nkp-gitops-infra/region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/nkp-nutanix-products-catalog-applications/ndk/ndk-image-pull-secret.yaml"
    local SEALED_SECRETS_NS="sealed-secrets-system"
    local SEALED_SECRETS_CTRL="sealed-secrets-controller"
    local KEY_STORAGE_DIR="$DEFAULT_DO_NOT_CHECKIN_DIR"
    local CLUSTER_NAME=""
    local PRIVATE_KEY_FILE=""
    local PUBLIC_KEY_FILE=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --from-file|--file|-f)
                INPUT_FILE="$2"
                shift 2
                ;;
            --username)
                USERNAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --registry-url)
                REGISTRY_URL="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
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
Generate NDK Image Pull Sealed Secret

Generates a SealedSecret for NDK image pull credentials with cluster-wide scope.

Usage:
    $0 generate-ndk-sealed-secrets [options]

Options:
    --from-file, -f PATH      Read from existing plaintext secret file (recommended)
                              If provided, registry URL, username, and password are auto-detected
    --username USER           Registry username (required if --from-file not used)
    --password PASS           Registry password (required if --from-file not used)
    --registry-url URL        Registry URL (default: registry-1.docker.io, auto-detected from file)
    -o, --output PATH         Output file (default: region-usa/az1/.../ndk/ndk-image-pull-secret.yaml)
    -k, --kubeconfig PATH     Path to kubeconfig file
    --cluster-name NAME       Cluster name for key file naming (default: auto-detect)
    -h, --help                Show this help message

Examples:
    # Recommended: Read from existing plaintext secret file
    $0 generate-ndk-sealed-secrets --from-file do-not-checkin-folder/ndk-image-pull-secret.yaml

    # Alternative: Provide credentials directly
    $0 generate-ndk-sealed-secrets \\
        --username "myuser" \\
        --password "mypass" \\
        --registry-url "registry.nutanix.com"
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    # If input file is provided, extract credentials from it
    if [[ -n "$INPUT_FILE" ]]; then
        if [[ ! -f "$INPUT_FILE" ]]; then
            echo -e "${RED}✗ Input file not found: $INPUT_FILE${NC}"
            exit 1
        fi
        
        # Extract registry URL, username, and password from the file
        # Handle both stringData and data formats
        if grep -q "stringData:" "$INPUT_FILE"; then
            # Extract from stringData (plaintext)
            if command -v yq &> /dev/null; then
                REGISTRY_URL=$(yq eval '.stringData.".dockerconfigjson" | fromjson | .auths | keys[0]' "$INPUT_FILE" 2>/dev/null || echo "registry.nutanix.com")
                USERNAME=$(yq eval '.stringData.".dockerconfigjson" | fromjson | .auths | to_entries[0].value.username' "$INPUT_FILE" 2>/dev/null || echo "")
                PASSWORD=$(yq eval '.stringData.".dockerconfigjson" | fromjson | .auths | to_entries[0].value.password' "$INPUT_FILE" 2>/dev/null || echo "")
            else
                # Fallback: use grep and sed to extract
                REGISTRY_URL=$(grep -A 10 'stringData:' "$INPUT_FILE" | grep -o '"[^"]*":' | head -1 | tr -d '":' || echo "registry.nutanix.com")
                USERNAME=$(grep -A 10 'stringData:' "$INPUT_FILE" | grep '"username"' | sed 's/.*"username": *"\([^"]*\)".*/\1/' || echo "")
                PASSWORD=$(grep -A 10 'stringData:' "$INPUT_FILE" | grep '"password"' | sed 's/.*"password": *"\([^"]*\)".*/\1/' || echo "")
            fi
        else
            # If it's already a data field (base64), we can't extract easily, so just seal it directly
            echo -e "${CYAN}Reading secret from file (will seal directly)...${NC}"
            INPUT_FILE_MODE="direct"
        fi
        
        # Default registry if not detected
        if [[ -z "$REGISTRY_URL" ]] || [[ "$REGISTRY_URL" == "null" ]]; then
            REGISTRY_URL="registry-1.docker.io"
        fi
    fi

    # Validate required parameters
    if [[ -z "$INPUT_FILE" ]] && ([[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]); then
        echo -e "${RED}✗ Either --from-file or both --username and --password are required${NC}"
        exit 1
    fi

    check_prerequisites
    set_kubeconfig

    if ! kubectl get namespace "$SEALED_SECRETS_NS" &> /dev/null; then
        echo -e "${RED}✗ Namespace $SEALED_SECRETS_NS does not exist${NC}"
        exit 1
    fi

    print_header "Generate NDK Image Pull Sealed Secret"

    # Determine cluster name for key file naming
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "default")
        CLUSTER_NAME=$(echo "$CLUSTER_NAME" | sed 's|https\?://||' | sed 's|:.*||' | sed 's|[^a-zA-Z0-9-]|-|g' | head -c 50)
        if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
            CLUSTER_NAME="cluster-$(date +%Y%m%d-%H%M%S)"
        fi
    fi

    # Set key file paths - use keys from do-not-checkin-folder (always up to date)
    # Default to dm-nkp-mgmt-1 if cluster name not specified
    if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
        CLUSTER_NAME="dm-nkp-mgmt-1"
    fi
    PRIVATE_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml"
    PUBLIC_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-public-key-${CLUSTER_NAME}.pem"

    # Ensure do-not-checkin-folder exists
    mkdir -p "$KEY_STORAGE_DIR"

    # Use public key from do-not-checkin-folder (always up to date with mgmt cluster)
    if [ ! -f "$PUBLIC_KEY_FILE" ]; then
        echo -e "${RED}✗ Public key file not found: $PUBLIC_KEY_FILE${NC}"
        echo -e "${YELLOW}  Falling back to fetching from cluster...${NC}"
        # Fetch the active private key from cluster
        ACTIVE_KEY_NAME=$(kubectl get secret -n "$SEALED_SECRETS_NS" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$ACTIVE_KEY_NAME" ]]; then
            echo -e "${RED}✗ No active sealed-secrets key found in cluster${NC}"
            exit 1
        fi
        echo -e "${YELLOW}  Fetching public key from cluster...${NC}"
        kubeseal --fetch-cert \
            --controller-name="$SEALED_SECRETS_CTRL" \
            --controller-namespace="$SEALED_SECRETS_NS" \
            > "$PUBLIC_KEY_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Failed to fetch public key${NC}"
            exit 1
        }
    else
        echo -e "${CYAN}Using public key from: $PUBLIC_KEY_FILE${NC}"
        echo -e "${GREEN}✓ This ensures secrets are encrypted with the latest mgmt cluster keys${NC}"
    fi
    echo ""

    # Handle direct file sealing (if file has data field instead of stringData)
    if [[ -n "$INPUT_FILE" ]] && grep -q "^data:" "$INPUT_FILE" && ! grep -q "stringData:" "$INPUT_FILE"; then
        echo -e "${CYAN}Sealing secret directly from file (contains base64 data)...${NC}"
        kubeseal \
            --format=yaml \
            --cert="$PUBLIC_KEY_FILE" \
            --scope cluster-wide \
            < "$INPUT_FILE" > "$OUTPUT_FILE" || {
            echo -e "${RED}✗ Failed to seal secret${NC}"
            exit 1
        }
    else
        # Create dockerconfigjson from extracted or provided credentials
        echo -e "${CYAN}Creating dockerconfigjson secret...${NC}"
        if [[ -n "$INPUT_FILE" ]]; then
            echo -e "${GREEN}✓ Extracted registry: $REGISTRY_URL${NC}"
            echo -e "${GREEN}✓ Extracted username: $USERNAME${NC}"
        fi
        
        local AUTH=$(echo -n "$USERNAME:$PASSWORD" | base64 | tr -d '\n')

        # Create dockerconfigjson - use jq if available, otherwise construct manually
        local DOCKERCONFIGJSON=""
        if command -v jq &> /dev/null; then
            DOCKERCONFIGJSON=$(cat <<EOF | jq -c .
{
  "auths": {
    "$REGISTRY_URL": {
      "username": "$USERNAME",
      "password": "$PASSWORD",
      "auth": "$AUTH"
    }
  }
}
EOF
)
        else
            # Manual JSON construction (no jq dependency)
            DOCKERCONFIGJSON="{\"auths\":{\"$REGISTRY_URL\":{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"auth\":\"$AUTH\"}}}"
        fi

        # Create Secret YAML
        local TEMP_SECRET=$(mktemp)
        local DOCKERCONFIGJSON_B64=$(echo -n "$DOCKERCONFIGJSON" | base64 | tr -d '\n')
        cat > "$TEMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ndk-image-pull-secret
  namespace: ntnx-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $DOCKERCONFIGJSON_B64
EOF

        # Seal the secret with cluster-wide scope
        echo -e "${CYAN}Sealing secret with cluster-wide scope...${NC}"
        kubeseal \
            --format=yaml \
            --cert="$PUBLIC_KEY_FILE" \
            --scope cluster-wide \
            < "$TEMP_SECRET" > "$OUTPUT_FILE" || {
            echo -e "${RED}✗ Failed to seal secret${NC}"
            rm -f "$TEMP_SECRET"
            exit 1
        }
        
        rm -f "$TEMP_SECRET"
    fi

    # Add header comment and ensure annotations
    {
        echo "# SealedSecret for NDK image registry credentials"
        echo "# This sealed secret uses cluster-wide scope so it can be used from any namespace"
        echo "# NOTE: This requires all target clusters to have the same sealed-secrets controller private key."
        echo "---"
        cat "$OUTPUT_FILE"
    } > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

    # Ensure the template has the correct annotations using yq if available
    if command -v yq &> /dev/null; then
        yq eval '.metadata.annotations."sealedsecrets.bitnami.com/cluster-wide" = "true"' -i "$OUTPUT_FILE" 2>/dev/null || true
        yq eval '.spec.template.metadata.annotations."sealedsecrets.bitnami.com/cluster-wide" = "true"' -i "$OUTPUT_FILE" 2>/dev/null || true
    fi

    rm -f "$TEMP_SECRET"

    echo -e "${GREEN}✓ Sealed secret written to: $OUTPUT_FILE${NC}"
    echo ""
    echo -e "${CYAN}Key Information:${NC}"
    echo -e "  Private key: $PRIVATE_KEY_FILE"
    echo -e "  Public key: $PUBLIC_KEY_FILE"
    echo -e "  Active key name: $ACTIVE_KEY_NAME"
    echo -e "  Registry URL: $REGISTRY_URL"
}

# ============================================================================
# GENERATE-NAI-SEALED-SECRETS COMMAND
# ============================================================================
cmd_generate_nai_sealed_secrets() {
    local USERNAME=""
    local PASSWORD=""
    local REGISTRY_URL="${REGISTRY_URL:-registry.nutanix.com}"
    local OUTPUT_FILE="/Users/deepak.muley/go/src/github.com/deepak-muley/dm-nkp-gitops-infra/region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/nkp-nutanix-products-catalog-applications/nutanix-ai/nai-image-pull-secret.yaml"
    local SEALED_SECRETS_NS="sealed-secrets-system"
    local SEALED_SECRETS_CTRL="sealed-secrets-controller"
    local KEY_STORAGE_DIR="$DEFAULT_DO_NOT_CHECKIN_DIR"
    local CLUSTER_NAME=""
    local PRIVATE_KEY_FILE=""
    local PUBLIC_KEY_FILE=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username)
                USERNAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --registry-url)
                REGISTRY_URL="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
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
Generate NAI Image Pull Sealed Secret

Generates a SealedSecret for NAI image pull credentials with cluster-wide scope.

Usage:
    $0 generate-nai-sealed-secrets [options]

Options:
    --username USER           Registry username (plain text, required)
    --password PASS           Registry password (plain text, required)
    --registry-url URL        Registry URL (default: registry.nutanix.com)
    -o, --output PATH         Output file (default: region-usa/az1/.../nutanix-ai/nai-image-pull-secret.yaml)
    -k, --kubeconfig PATH     Path to kubeconfig file
    --cluster-name NAME       Cluster name for key file naming (default: auto-detect)
    -h, --help                Show this help message

Example:
    $0 generate-nai-sealed-secrets \\
        --username "myuser" \\
        --password "mypass" \\
        --registry-url "registry.nutanix.com"
EOF
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}✗ Username and password are required${NC}"
        exit 1
    fi

    check_prerequisites
    set_kubeconfig

    if ! kubectl get namespace "$SEALED_SECRETS_NS" &> /dev/null; then
        echo -e "${RED}✗ Namespace $SEALED_SECRETS_NS does not exist${NC}"
        exit 1
    fi

    print_header "Generate NAI Image Pull Sealed Secret"

    # Determine cluster name for key file naming
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "default")
        CLUSTER_NAME=$(echo "$CLUSTER_NAME" | sed 's|https\?://||' | sed 's|:.*||' | sed 's|[^a-zA-Z0-9-]|-|g' | head -c 50)
        if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
            CLUSTER_NAME="cluster-$(date +%Y%m%d-%H%M%S)"
        fi
    fi

    # Set key file paths - use keys from do-not-checkin-folder (always up to date)
    # Default to dm-nkp-mgmt-1 if cluster name not specified
    if [[ -z "$CLUSTER_NAME" ]] || [[ "$CLUSTER_NAME" == "default" ]]; then
        CLUSTER_NAME="dm-nkp-mgmt-1"
    fi
    PRIVATE_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-key-backup-${CLUSTER_NAME}.yaml"
    PUBLIC_KEY_FILE="$KEY_STORAGE_DIR/sealed-secrets-public-key-${CLUSTER_NAME}.pem"

    # Ensure do-not-checkin-folder exists
    mkdir -p "$KEY_STORAGE_DIR"

    # Use public key from do-not-checkin-folder (always up to date with mgmt cluster)
    if [ ! -f "$PUBLIC_KEY_FILE" ]; then
        echo -e "${RED}✗ Public key file not found: $PUBLIC_KEY_FILE${NC}"
        echo -e "${YELLOW}  Falling back to fetching from cluster...${NC}"
        # Fetch the active private key from cluster
        ACTIVE_KEY_NAME=$(kubectl get secret -n "$SEALED_SECRETS_NS" -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$ACTIVE_KEY_NAME" ]]; then
            echo -e "${RED}✗ No active sealed-secrets key found in cluster${NC}"
            exit 1
        fi
        echo -e "${YELLOW}  Fetching public key from cluster...${NC}"
        kubeseal --fetch-cert \
            --controller-name="$SEALED_SECRETS_CTRL" \
            --controller-namespace="$SEALED_SECRETS_NS" \
            > "$PUBLIC_KEY_FILE" 2>/dev/null || {
            echo -e "${RED}✗ Failed to fetch public key${NC}"
            exit 1
        }
    else
        echo -e "${CYAN}Using public key from: $PUBLIC_KEY_FILE${NC}"
        echo -e "${GREEN}✓ This ensures secrets are encrypted with the latest mgmt cluster keys${NC}"
    fi
    echo ""

    # Create dockerconfigjson
    echo -e "${CYAN}Creating dockerconfigjson secret...${NC}"
    local AUTH=$(echo -n "$USERNAME:$PASSWORD" | base64 | tr -d '\n')

    # Create dockerconfigjson - use jq if available, otherwise construct manually
    local DOCKERCONFIGJSON=""
    if command -v jq &> /dev/null; then
        DOCKERCONFIGJSON=$(cat <<EOF | jq -c .
{
  "auths": {
    "$REGISTRY_URL": {
      "username": "$USERNAME",
      "password": "$PASSWORD",
      "auth": "$AUTH"
    }
  }
}
EOF
)
    else
        # Manual JSON construction (no jq dependency)
        DOCKERCONFIGJSON="{\"auths\":{\"$REGISTRY_URL\":{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"auth\":\"$AUTH\"}}}"
    fi

    # Create Secret YAML
    local TEMP_SECRET=$(mktemp)
    local DOCKERCONFIGJSON_B64=$(echo -n "$DOCKERCONFIGJSON" | base64 | tr -d '\n')
    cat > "$TEMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: nai-image-pull-secret
  namespace: nai-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $DOCKERCONFIGJSON_B64
EOF

    # Seal the secret with cluster-wide scope
    echo -e "${CYAN}Sealing secret with cluster-wide scope...${NC}"
    kubeseal \
        --format=yaml \
        --cert="$PUBLIC_KEY_FILE" \
        --scope cluster-wide \
        < "$TEMP_SECRET" > "$OUTPUT_FILE" || {
        echo -e "${RED}✗ Failed to seal secret${NC}"
        rm -f "$TEMP_SECRET"
        exit 1
    }

    # Add header comment
    {
        echo "# SealedSecret for NAI image registry credentials"
        echo "# This sealed secret uses cluster-wide scope so it can be used from any namespace"
        echo "# NOTE: This requires all target clusters to have the same sealed-secrets controller private key."
        echo "---"
        cat "$OUTPUT_FILE"
    } > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

    # Ensure the template has the correct annotations using yq if available
    if command -v yq &> /dev/null; then
        yq eval '.metadata.annotations."sealedsecrets.bitnami.com/cluster-wide" = "true"' -i "$OUTPUT_FILE" 2>/dev/null || true
        yq eval '.spec.template.metadata.annotations."sealedsecrets.bitnami.com/cluster-wide" = "true"' -i "$OUTPUT_FILE" 2>/dev/null || true
    fi

    rm -f "$TEMP_SECRET"

    echo -e "${GREEN}✓ Sealed secret written to: $OUTPUT_FILE${NC}"
    echo ""
    echo -e "${CYAN}Key Information:${NC}"
    echo -e "  Private key: $PRIVATE_KEY_FILE"
    echo -e "  Public key: $PUBLIC_KEY_FILE"
    echo -e "  Active key name: $ACTIVE_KEY_NAME"
    echo -e "  Registry URL: $REGISTRY_URL"
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
    backup                        Backup sealed-secrets controller keys (public & private)
    restore                       Restore sealed-secrets keys from backup
    generate-cluster-sealed-secrets  Generate SealedSecrets for cluster credentials (PC, Konnector, CSI, Image Registry)
    generate-ndk-sealed-secrets    Generate SealedSecret for NDK image pull credentials
    generate-nai-sealed-secrets    Generate SealedSecret for NAI image pull credentials
    decrypt                       Decrypt a sealed secret YAML file (requires keys)
    re-encrypt                    Re-encrypt secrets with new credentials
    status                        Check status of sealed secrets in cluster

Use '$0 <command> --help' for command-specific help.

Examples:
    $0 backup
    $0 restore
    $0 generate-cluster-sealed-secrets -f secrets.yaml -o sealed-secrets.yaml
    $0 generate-cluster-sealed-secrets --pc-credentials.username "user" --pc-credentials.password "pass"
    $0 generate-ndk-sealed-secrets --username "user" --password "pass"
    $0 generate-nai-sealed-secrets --username "user" --password "pass"
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
        generate-cluster-sealed-secrets)
            cmd_generate_cluster_sealed_secrets "$@"
            ;;
        generate-ndk-sealed-secrets)
            cmd_generate_ndk_sealed_secrets "$@"
            ;;
        generate-nai-sealed-secrets)
            cmd_generate_nai_sealed_secrets "$@"
            ;;
        generate-sealed-secrets)
            # Alias for generate-cluster-sealed-secrets (backward compatibility)
            echo -e "${YELLOW}Note: 'generate-sealed-secrets' is deprecated. Use 'generate-cluster-sealed-secrets' instead.${NC}"
            echo ""
            cmd_generate_cluster_sealed_secrets "$@"
            ;;
        encrypt)
            # Alias for generate-cluster-sealed-secrets -f (backward compatibility)
            echo -e "${YELLOW}Note: 'encrypt' is deprecated. Use 'generate-cluster-sealed-secrets' instead.${NC}"
            echo ""
            cmd_generate_cluster_sealed_secrets "$@"
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

