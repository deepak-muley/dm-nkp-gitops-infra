#!/bin/bash
# =============================================================================
# Create Kubernetes User with X.509 Certificate Authentication
# =============================================================================
#
# This script creates a Kubernetes user by:
#   1. Generating a private key
#   2. Creating a Certificate Signing Request (CSR)
#   3. Submitting and approving the CSR via Kubernetes API
#   4. Generating a kubeconfig file with the signed certificate
#
# The username (CN in certificate) MUST match the "name" in VirtualGroup subjects
#
# Usage:
#   ./create-k8s-user.sh <username> [validity-days] [group]
#
# Examples:
#   ./create-k8s-user.sh dm-k8s-admin
#   ./create-k8s-user.sh dm-dev-workspace-admin 365
#   ./create-k8s-user.sh dm-dev-project-admin 365 developers
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

# Configuration
USERNAME="${1:?Usage: $0 <username> [validity-days] [group]}"
VALIDITY_DAYS="${2:-365}"
GROUP="${3:-}"
OUTPUT_DIR="${OUTPUT_DIR:-./generated-kubeconfigs}"
CLUSTER_NAME="${CLUSTER_NAME:-$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')}"
API_SERVER="${API_SERVER:-$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Creating Kubernetes User: ${USERNAME}${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Cluster:      ${CLUSTER_NAME}"
echo -e "API Server:   ${API_SERVER}"
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

cat <<EOF | kubectl apply -f -
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
kubectl certificate approve "${CSR_NAME}"
echo -e "${GREEN}      CSR approved${NC}"

# Wait for certificate to be issued
echo -e "${YELLOW}      Waiting for certificate...${NC}"
for i in {1..30}; do
    CERT=$(kubectl get csr "${CSR_NAME}" -o jsonpath='{.status.certificate}' 2>/dev/null || true)
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
echo -e "${YELLOW}[6/6] Creating kubeconfig...${NC}"
KUBECONFIG_FILE="${OUTPUT_DIR}/${USERNAME}.kubeconfig"

# Get cluster CA
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "${OUTPUT_DIR}/ca.crt"

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
    client-certificate-data: $(cat "${OUTPUT_DIR}/${USERNAME}.crt" | base64 | tr -d '\n')
    client-key-data: $(cat "${OUTPUT_DIR}/${USERNAME}.key" | base64 | tr -d '\n')
EOF

echo -e "${GREEN}      Created: ${KUBECONFIG_FILE}${NC}"

# Cleanup temporary files
rm -f "${OUTPUT_DIR}/ca.crt"
rm -f "${OUTPUT_DIR}/${USERNAME}.csr"

# Cleanup CSR from cluster
kubectl delete csr "${CSR_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  User Created Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Files generated:"
echo -e "  - Private Key:  ${OUTPUT_DIR}/${USERNAME}.key"
echo -e "  - Certificate:  ${OUTPUT_DIR}/${USERNAME}.crt"
echo -e "  - Kubeconfig:   ${KUBECONFIG_FILE}"
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
echo -e "${RED}IMPORTANT:${NC}"
echo -e "  - Keep the private key (${USERNAME}.key) secure!"
echo -e "  - Certificate expires in ${VALIDITY_DAYS} days"
echo -e "  - The username '${USERNAME}' must match VirtualGroup subject name"
echo ""

