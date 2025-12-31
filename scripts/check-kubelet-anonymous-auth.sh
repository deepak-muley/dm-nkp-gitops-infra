#!/bin/bash
# Script to check kubelet anonymous-auth setting on management and workload clusters
# This setting controls whether anonymous requests to kubelet are allowed
# Security best practice: anonymous-auth should be disabled (false)

set -e

MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf}"
WORKLOAD1_KUBECONFIG="${WORKLOAD1_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig}"
WORKLOAD2_KUBECONFIG="${WORKLOAD2_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig}"

echo "=========================================="
echo "Kubelet Anonymous-Auth Check"
echo "=========================================="
echo ""
echo "NOTE: The most reliable method is to SSH into nodes and check directly."
echo "This script provides multiple methods to check the setting."
echo ""

check_cluster() {
    local cluster_name=$1
    local kubeconfig=$2

    if [ ! -f "$kubeconfig" ]; then
        echo "⚠️  Kubeconfig not found: $kubeconfig"
        return
    fi

    echo "=========================================="
    echo "Cluster: $cluster_name"
    echo "=========================================="
    export KUBECONFIG="$kubeconfig"

    # Method 1: Check kubelet ConfigMap (if using dynamic config)
    echo ""
    echo "Method 1: Checking kubelet ConfigMap..."
    if kubectl get configmap kubelet-config -n kube-system &>/dev/null; then
        local result=$(kubectl get configmap kubelet-config -n kube-system -o yaml 2>/dev/null | grep -i "anonymousAuth" || echo "")
        if [ -n "$result" ]; then
            echo "  ✅ Found in ConfigMap: $result"
        else
            echo "  ⚠️  ConfigMap exists but anonymousAuth not set (defaults to true)"
        fi
    else
        echo "  ⚠️  kubelet-config ConfigMap not found (may not be using dynamic config)"
    fi

    # Method 2: List nodes for manual SSH check
    echo ""
    echo "Method 2: Node list (SSH into these to check directly)..."
    kubectl get nodes -o custom-columns=NAME:.metadata.name,INTERNAL-IP:.status.addresses[0].address --no-headers | head -3

    # Method 3: Try to get kubelet configuration via API (if accessible)
    echo ""
    echo "Method 3: Attempting to check kubelet config endpoint..."
    local first_node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$first_node" ]; then
        local node_ip=$(kubectl get node "$first_node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        if [ -n "$node_ip" ]; then
            echo "  Node: $first_node ($node_ip)"
            echo "  Run on node: curl -k https://localhost:10250/configz 2>/dev/null | grep -i anonymous || echo 'Endpoint not accessible'"
        fi
    fi

    echo ""
}

# Check management cluster
check_cluster "Management Cluster" "$MGMT_KUBECONFIG"

# Check workload cluster 1
check_cluster "Workload Cluster 1" "$WORKLOAD1_KUBECONFIG"

# Check workload cluster 2 if exists
if [ -f "$WORKLOAD2_KUBECONFIG" ]; then
    check_cluster "Workload Cluster 2" "$WORKLOAD2_KUBECONFIG"
fi

echo ""
echo "=========================================="
echo "Manual Commands to Run on Nodes"
echo "=========================================="
echo ""
echo "SSH into any node and run these commands:"
echo ""
echo "# Method A: Check kubelet process arguments (MOST RELIABLE)"
echo "ps aux | grep kubelet | grep -E 'anonymous-auth|--anonymous-auth'"
echo ""
echo "# Method B: Check kubelet config file"
echo "cat /var/lib/kubelet/config.yaml 2>/dev/null | grep -i anonymousAuth"
echo "cat /etc/kubernetes/kubelet.conf 2>/dev/null | grep -i anonymousAuth"
echo ""
echo "# Method C: Check kubelet config endpoint (from node itself)"
echo "curl -k https://localhost:10250/configz 2>/dev/null | grep -i anonymousAuth"
echo ""
echo "# Method D: Test anonymous access to health endpoint"
echo "# If this returns 200, anonymous-auth is ENABLED"
echo "# If this returns 401, anonymous-auth is DISABLED"
echo "curl -k -w '\nHTTP Status: %{http_code}\n' https://localhost:10250/healthz 2>/dev/null"
echo ""
echo "=========================================="
echo "Expected Results"
echo "=========================================="
echo ""
echo "✅ SECURE (anonymous-auth disabled):"
echo "   - Process args: --anonymous-auth=false"
echo "   - Config file: authentication.anonymous.enabled: false"
echo "   - Health endpoint: HTTP Status: 401"
echo ""
echo "⚠️  INSECURE (anonymous-auth enabled - DEFAULT):"
echo "   - Process args: --anonymous-auth=true (or flag not present)"
echo "   - Config file: authentication.anonymous.enabled: true (or not set)"
echo "   - Health endpoint: HTTP Status: 200"
echo ""
echo "=========================================="

