#!/bin/bash
# =============================================================================
# Kubernetes User Management Script
# =============================================================================
#
# This script manages Kubernetes users with X.509 Certificate Authentication
#
# Commands:
#   create          - Create a new Kubernetes user
#   delete          - Delete a user's CSR and optionally cleanup files
#   get kubeconfig  - Export kubeconfig for an existing user
#   export kubeconfig - Alias for 'get kubeconfig'
#
# Usage:
#   ./k8s-user.sh create --name <username> [--validity-days <days>] [--group <group>] [--kubeconfig <file>]
#   ./k8s-user.sh delete --name <username> [--cleanup-files] [--kubeconfig <file>]
#   ./k8s-user.sh get kubeconfig --name <username> [--kubeconfig <file>]
#   ./k8s-user.sh export kubeconfig --name <username> [--kubeconfig <file>]
#
# Examples:
#   ./k8s-user.sh create --name dm-k8s-admin
#   ./k8s-user.sh create --name dm-dev-workspace-admin --validity-days 365
#   ./k8s-user.sh create --name dm-dev-project-admin --validity-days 365 --group developers
#   ./k8s-user.sh create -u dm-k8s-admin -v 730
#   ./k8s-user.sh get kubeconfig --name dm-dev-project-admin
#   ./k8s-user.sh get kubeconfig -u dm-k8s-admin
#   ./k8s-user.sh export kubeconfig --name dm-k8s-admin
#   ./k8s-user.sh delete --name dm-k8s-admin --cleanup-files
#
# Prerequisites:
#   - kubectl configured with cluster-admin access
#   - openssl installed
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Common configuration
OUTPUT_DIR="${OUTPUT_DIR:-./generated-kubeconfigs}"
KUBECONFIG_ARG=""

# Function to show usage
show_usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 create --name <username> [--validity-days <days>] [--group <group>]"
    echo -e "  $0 delete --name <username> [--cleanup-files]"
    echo -e "  $0 get kubeconfig --name <username> [--key-dir <dir>]"
    echo -e "  $0 export kubeconfig --name <username> [--key-dir <dir>]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  --name, --user, -u        Username (required)"
    echo -e "  --validity-days, -v       Certificate validity in days (default: 365)"
    echo -e "  --group, -g               Kubernetes group (optional)"
    echo -e "  --kubeconfig, -k          Path to kubeconfig file (optional)"
    echo -e "  --key-dir, -d             Directory containing key/cert files (default: ./generated-kubeconfigs)"
    echo -e "  --cleanup-files           Delete local key/cert/kubeconfig files (delete command only)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 create --name dm-k8s-admin"
    echo -e "  $0 create --name dm-dev-workspace-admin --validity-days 365"
    echo -e "  $0 create --name dm-dev-project-admin --validity-days 365 --group developers"
    echo -e "  $0 create -u dm-k8s-admin -v 730"
    echo -e "  $0 get kubeconfig --name dm-dev-project-admin"
    echo -e "  $0 get kubeconfig -u dm-k8s-admin --kubeconfig /path/to/kubeconfig"
    echo -e "  $0 export kubeconfig --name dm-k8s-admin --key-dir /path/to/key/cert/files"
    echo -e "  $0 export kubeconfig --name dm-k8s-admin --kubeconfig /path/to/kubeconfig --key-dir /path/to/key/cert/files"
    echo -e "  $0 delete --name dm-k8s-admin --cleanup-files"
}

# Function to parse arguments for create command
parse_create_args() {
    USERNAME=""
    VALIDITY_DAYS="365"
    GROUP=""
    KUBECONFIG_ARG=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name|--user|-u)
                USERNAME="$2"
                shift 2
                ;;
            --validity-days|-v)
                VALIDITY_DAYS="$2"
                shift 2
                ;;
            --group|-g)
                GROUP="$2"
                shift 2
                ;;
            --kubeconfig|-k)
                KUBECONFIG_ARG="--kubeconfig=$2"
                export KUBECONFIG="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}ERROR: Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ -z "${USERNAME}" ]; then
        echo -e "${RED}ERROR: --name (or --user/-u) is required${NC}"
        show_usage
        exit 1
    fi
}

# Function to parse arguments for get/export kubeconfig command
parse_kubeconfig_args() {
    USERNAME=""
    KUBECONFIG_ARG=""
    OUTPUT_DIR="${OUTPUT_DIR:-./generated-kubeconfigs}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name|--user|-u)
                USERNAME="$2"
                shift 2
                ;;
            --kubeconfig|-k)
                KUBECONFIG_ARG="--kubeconfig=$2"
                export KUBECONFIG="$2"
                shift 2
                ;;
            --key-dir|-d)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}ERROR: Unknown option: $1${NC}"
                echo -e "${YELLOW}Usage: $0 get kubeconfig --name <username> [--kubeconfig <file>] [--key-dir <dir>]${NC}"
                exit 1
                ;;
        esac
    done

    if [ -z "${USERNAME}" ]; then
        echo -e "${RED}ERROR: --name (or --user/-u) is required${NC}"
        echo -e "${YELLOW}Usage: $0 get kubeconfig --name <username>${NC}"
        exit 1
    fi
}

# Function to parse arguments for delete command
parse_delete_args() {
    USERNAME=""
    CLEANUP_FILES=false
    KUBECONFIG_ARG=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name|--user|-u)
                USERNAME="$2"
                shift 2
                ;;
            --cleanup-files)
                CLEANUP_FILES=true
                shift
                ;;
            --kubeconfig|-k)
                KUBECONFIG_ARG="--kubeconfig=$2"
                export KUBECONFIG="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}ERROR: Unknown option: $1${NC}"
                echo -e "${YELLOW}Usage: $0 delete --name <username> [--cleanup-files] [--kubeconfig <file>]${NC}"
                exit 1
                ;;
        esac
    done

    if [ -z "${USERNAME}" ]; then
        echo -e "${RED}ERROR: --name (or --user/-u) is required${NC}"
        echo -e "${YELLOW}Usage: $0 delete --name <username> [--cleanup-files]${NC}"
        exit 1
    fi
}

# Function to get cluster info
get_cluster_info() {
    local KUBECTL_CMD="kubectl"
    if [ -n "${KUBECONFIG}" ]; then
        KUBECTL_CMD="kubectl --kubeconfig=${KUBECONFIG}"
    fi

    # Try to get from current context first, fallback to first cluster in config
    if [ -z "${CLUSTER_NAME}" ]; then
        CLUSTER_NAME=$(${KUBECTL_CMD} config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null || ${KUBECTL_CMD} config view -o jsonpath='{.clusters[0].name}' 2>/dev/null)
    fi

    if [ -z "${API_SERVER}" ]; then
        API_SERVER=$(${KUBECTL_CMD} config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || ${KUBECTL_CMD} config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
    fi

    if [ -z "${CLUSTER_NAME}" ] || [ -z "${API_SERVER}" ]; then
        echo -e "${RED}ERROR: Could not determine cluster information${NC}"
        echo -e "${YELLOW}Hint: Set CLUSTER_NAME and API_SERVER environment variables, or configure kubectl context${NC}"
        exit 1
    fi
}

# Function to create a new user
create_user() {
    parse_create_args "$@"

    get_cluster_info

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Creating Kubernetes User: ${USERNAME}${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "Cluster:      ${CLUSTER_NAME}"
    echo -e "API Server:   ${API_SERVER}"
    echo -e "Username:     ${USERNAME}"
    echo -e "Validity:     ${VALIDITY_DAYS} days"
    echo -e "Group:        ${GROUP:-<none>}"
    echo -e "Output Dir:   ${OUTPUT_DIR}"
    echo ""

    # Step 1: Generate private key
    echo -e "${YELLOW}[1/6] Generating private key...${NC}"
    openssl genrsa -out "${OUTPUT_DIR}/${USERNAME}.key" 2048 2>/dev/null
    echo -e "${GREEN}      Created: ${OUTPUT_DIR}/${USERNAME}.key${NC}"

    # Step 2: Create CSR configuration
    echo -e "${YELLOW}[2/6] Creating CSR...${NC}"
    if [ -n "${GROUP}" ]; then
        # With group (O= organization maps to K8s group)
        openssl req -new \
            -key "${OUTPUT_DIR}/${USERNAME}.key" \
            -out "${OUTPUT_DIR}/${USERNAME}.csr" \
            -subj "/CN=${USERNAME}/O=${GROUP}" 2>/dev/null
    else
        # Without group
        openssl req -new \
            -key "${OUTPUT_DIR}/${USERNAME}.key" \
            -out "${OUTPUT_DIR}/${USERNAME}.csr" \
            -subj "/CN=${USERNAME}" 2>/dev/null
    fi
    echo -e "${GREEN}      Created: ${OUTPUT_DIR}/${USERNAME}.csr${NC}"

    # Step 3: Create Kubernetes CSR resource
    echo -e "${YELLOW}[3/6] Submitting CSR to Kubernetes...${NC}"
    CSR_NAME="${USERNAME}-csr-$(date +%s)"
    CSR_BASE64=$(cat "${OUTPUT_DIR}/${USERNAME}.csr" | base64 | tr -d '\n')

    local KUBECTL_CMD="kubectl"
    if [ -n "${KUBECONFIG}" ]; then
        KUBECTL_CMD="kubectl --kubeconfig=${KUBECONFIG}"
    fi

    cat <<EOF | ${KUBECTL_CMD} apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $((VALIDITY_DAYS * 86400))
  usages:
    - client auth
EOF
    echo -e "${GREEN}      Submitted CSR: ${CSR_NAME}${NC}"

    # Step 4: Approve CSR
    echo -e "${YELLOW}[4/6] Approving CSR...${NC}"
    ${KUBECTL_CMD} certificate approve "${CSR_NAME}"
    echo -e "${GREEN}      CSR approved${NC}"

    # Wait for certificate to be issued
    echo -e "${YELLOW}      Waiting for certificate...${NC}"
    local CERT=""
    for i in {1..30}; do
        CERT=$(${KUBECTL_CMD} get csr "${CSR_NAME}" -o jsonpath='{.status.certificate}' 2>/dev/null || true)
        if [ -n "${CERT}" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "${CERT}" ]; then
        echo -e "${RED}ERROR: Certificate not issued after 30 seconds${NC}"
        exit 1
    fi

    # Step 5: Save the signed certificate
    echo -e "${YELLOW}[5/6] Saving signed certificate...${NC}"
    echo "${CERT}" | base64 -d > "${OUTPUT_DIR}/${USERNAME}.crt"
    echo -e "${GREEN}      Created: ${OUTPUT_DIR}/${USERNAME}.crt${NC}"

    # Step 6: Create kubeconfig
    create_kubeconfig "${USERNAME}"

    # Cleanup temporary files
    rm -f "${OUTPUT_DIR}/ca.crt"
    rm -f "${OUTPUT_DIR}/${USERNAME}.csr"

    # Cleanup CSR from cluster
    ${KUBECTL_CMD} delete csr "${CSR_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  User Created Successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "Files generated:"
    echo -e "  - Private Key:  ${OUTPUT_DIR}/${USERNAME}.key"
    echo -e "  - Certificate:  ${OUTPUT_DIR}/${USERNAME}.crt"
    echo -e "  - Kubeconfig:   ${OUTPUT_DIR}/${USERNAME}.kubeconfig"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  export KUBECONFIG=${OUTPUT_DIR}/${USERNAME}.kubeconfig"
    echo -e "  kubectl get pods"
    echo ""
    echo -e "${YELLOW}Or use directly:${NC}"
    echo -e "  kubectl --kubeconfig=${OUTPUT_DIR}/${USERNAME}.kubeconfig get pods"
    echo ""
    echo -e "${YELLOW}Test authentication:${NC}"
    echo -e "  kubectl --kubeconfig=${OUTPUT_DIR}/${USERNAME}.kubeconfig auth whoami"
    echo ""
    echo -e "${RED}IMPORTANT:${NC}"
    echo -e "  - Keep the private key (${USERNAME}.key) secure!"
    echo -e "  - Certificate expires in ${VALIDITY_DAYS} days"
    echo -e "  - The username '${USERNAME}' must match VirtualGroup subject name"
    echo ""
}

# Function to create kubeconfig from existing key and cert
create_kubeconfig() {
    local USERNAME="${1:?Username required}"

    get_cluster_info

    # Check if key and cert files exist
    local KEY_FILE="${OUTPUT_DIR}/${USERNAME}.key"
    local CERT_FILE="${OUTPUT_DIR}/${USERNAME}.crt"

    if [ ! -f "${KEY_FILE}" ]; then
        echo -e "${RED}ERROR: Private key not found: ${KEY_FILE}${NC}"
        echo -e "${YELLOW}Hint: Use 'create' command to generate a new user, or specify --key-dir if files are in a different location${NC}"
        echo -e "${YELLOW}Example: $0 export kubeconfig --name ${USERNAME} --key-dir /path/to/key/cert/files${NC}"
        exit 1
    fi

    if [ ! -f "${CERT_FILE}" ]; then
        echo -e "${RED}ERROR: Certificate not found: ${CERT_FILE}${NC}"
        echo -e "${YELLOW}Hint: Use 'create' command to generate a new user, or specify --key-dir if files are in a different location${NC}"
        echo -e "${YELLOW}Example: $0 export kubeconfig --name ${USERNAME} --key-dir /path/to/key/cert/files${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Creating kubeconfig...${NC}"
    local KUBECONFIG_FILE="${OUTPUT_DIR}/${USERNAME}.kubeconfig"

    local KUBECTL_CMD="kubectl"
    if [ -n "${KUBECONFIG}" ]; then
        KUBECTL_CMD="kubectl --kubeconfig=${KUBECONFIG}"
    fi

    # Get cluster CA (try with minify first, fallback to full config)
    CA_DATA=$(${KUBECTL_CMD} config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || \
              ${KUBECTL_CMD} config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null)

    if [ -z "${CA_DATA}" ]; then
        echo -e "${RED}ERROR: Could not extract cluster CA certificate${NC}"
        echo -e "${YELLOW}Hint: Ensure kubectl is configured with cluster access${NC}"
        exit 1
    fi

    echo "${CA_DATA}" | base64 -d > "${OUTPUT_DIR}/ca.crt"

    # Create kubeconfig
    cat > "${KUBECONFIG_FILE}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(cat "${OUTPUT_DIR}/ca.crt" | base64 | tr -d '\n')
    server: ${API_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${USERNAME}
  name: ${USERNAME}@${CLUSTER_NAME}
current-context: ${USERNAME}@${CLUSTER_NAME}
preferences: {}
users:
- name: ${USERNAME}
  user:
    client-certificate-data: $(cat "${CERT_FILE}" | base64 | tr -d '\n')
    client-key-data: $(cat "${KEY_FILE}" | base64 | tr -d '\n')
EOF

    # Cleanup temporary CA file
    rm -f "${OUTPUT_DIR}/ca.crt"

    echo -e "${GREEN}      Created: ${KUBECONFIG_FILE}${NC}"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Kubeconfig Exported Successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "Kubeconfig:   ${KUBECONFIG_FILE}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  export KUBECONFIG=${KUBECONFIG_FILE}"
    echo -e "  kubectl get pods"
    echo ""
    echo -e "${YELLOW}Or use directly:${NC}"
    echo -e "  kubectl --kubeconfig=${KUBECONFIG_FILE} get pods"
    echo ""
    echo -e "${YELLOW}Test authentication:${NC}"
    echo -e "  kubectl --kubeconfig=${KUBECONFIG_FILE} auth whoami"
    echo ""
}

# Function to get/export kubeconfig
get_kubeconfig() {
    parse_kubeconfig_args "$@"
    create_kubeconfig "${USERNAME}"
}

# Function to delete a user
delete_user() {
    parse_delete_args "$@"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Deleting Kubernetes User: ${USERNAME}${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    # Delete all CSRs for this user
    echo -e "${YELLOW}Deleting Certificate Signing Requests...${NC}"
    local KUBECTL_CMD="kubectl"
    if [ -n "${KUBECONFIG}" ]; then
        KUBECTL_CMD="kubectl --kubeconfig=${KUBECONFIG}"
    fi

    local CSR_COUNT=0
    while IFS= read -r csr; do
        if [ -n "${csr}" ]; then
            ${KUBECTL_CMD} delete csr "${csr}" --ignore-not-found=true >/dev/null 2>&1 || true
            echo -e "${GREEN}      Deleted CSR: ${csr}${NC}"
            CSR_COUNT=$((CSR_COUNT + 1))
        fi
    done < <(${KUBECTL_CMD} get csr -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep "^${USERNAME}-csr-" || true)

    if [ "${CSR_COUNT}" -eq 0 ]; then
        echo -e "${YELLOW}      No CSRs found for user: ${USERNAME}${NC}"
    fi

    # Optionally cleanup files
    if [ "${CLEANUP_FILES}" = "true" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up local files...${NC}"
        local FILES_DELETED=0

        for file in "${OUTPUT_DIR}/${USERNAME}.key" "${OUTPUT_DIR}/${USERNAME}.crt" "${OUTPUT_DIR}/${USERNAME}.kubeconfig" "${OUTPUT_DIR}/${USERNAME}.csr"; do
            if [ -f "${file}" ]; then
                rm -f "${file}"
                echo -e "${GREEN}      Deleted: ${file}${NC}"
                FILES_DELETED=$((FILES_DELETED + 1))
            fi
        done

        if [ "${FILES_DELETED}" -eq 0 ]; then
            echo -e "${YELLOW}      No local files found for user: ${USERNAME}${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}Note: Local files not deleted. Use --cleanup-files to remove them.${NC}"
    fi

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  User Deletion Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
}

# Main command dispatcher
COMMAND="${1:-}"

case "${COMMAND}" in
    create)
        shift
        create_user "$@"
        ;;
    delete)
        shift
        delete_user "$@"
        ;;
    get)
        SUBCOMMAND="${2:-}"
        if [ "${SUBCOMMAND}" = "kubeconfig" ]; then
            shift 2
            get_kubeconfig "$@"
        else
            echo -e "${RED}ERROR: Unknown subcommand '${SUBCOMMAND}'${NC}"
            echo -e "${YELLOW}Usage: $0 get kubeconfig --name <username>${NC}"
            exit 1
        fi
        ;;
    export)
        SUBCOMMAND="${2:-}"
        if [ "${SUBCOMMAND}" = "kubeconfig" ]; then
            shift 2
            get_kubeconfig "$@"
        else
            echo -e "${RED}ERROR: Unknown subcommand '${SUBCOMMAND}'${NC}"
            echo -e "${YELLOW}Usage: $0 export kubeconfig --name <username>${NC}"
            exit 1
        fi
        ;;
    "")
        echo -e "${RED}ERROR: No command specified${NC}"
        echo ""
        show_usage
        exit 1
        ;;
    *)
        echo -e "${RED}ERROR: Unknown command '${COMMAND}'${NC}"
        echo ""
        echo -e "${YELLOW}Available commands:${NC}"
        echo -e "  create          - Create a new Kubernetes user"
        echo -e "  delete          - Delete a user's CSR and optionally cleanup files"
        echo -e "  get kubeconfig  - Export kubeconfig for an existing user"
        echo -e "  export kubeconfig - Alias for 'get kubeconfig'"
        echo ""
        show_usage
        exit 1
        ;;
esac
