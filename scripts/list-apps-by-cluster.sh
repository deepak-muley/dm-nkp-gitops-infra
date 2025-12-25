#!/bin/bash
#
# Script to list enabled and disabled apps for a specific management or workload cluster
#
# Usage:
#   export KUBECONFIG=/path/to/management-cluster/kubeconfig
#   ./scripts/list-apps-by-cluster.sh <cluster-name> [OPTIONS]
#
# Options:
#   --kind KIND          Filter by kind (ClusterApp or App)
#   --scope SCOPE        Filter by scope (workspace or project)
#   --type TYPE          Filter by type (custom, internal, nkp-catalog, nkp-core-platform)
#   --enabled-only       Show only enabled apps
#   --disabled-only      Show only disabled apps
#   -h, --help           Show this help message
#
# Requirements:
#   - kubectl
#   - jq
#   - KUBECONFIG environment variable set to management cluster kubeconfig
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME=""
FILTER_KIND=""
FILTER_SCOPE=""
FILTER_TYPE=""
ENABLED_ONLY=false
DISABLED_ONLY=false

# Parse command line arguments
if [ $# -eq 0 ]; then
  echo "Error: Cluster name is required"
  echo "Usage: $0 <cluster-name> [OPTIONS]"
  echo "Use --help for more information"
  exit 1
fi

CLUSTER_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --kind)
      FILTER_KIND="$2"
      shift 2
      ;;
    --scope)
      FILTER_SCOPE="$2"
      shift 2
      ;;
    --type)
      FILTER_TYPE="$2"
      shift 2
      ;;
    --enabled-only)
      ENABLED_ONLY=true
      shift
      ;;
    --disabled-only)
      DISABLED_ONLY=true
      shift
      ;;
    -h|--help)
      cat << EOF
List enabled and disabled apps for a specific cluster.

Usage:
  $0 <cluster-name> [OPTIONS]

Arguments:
  cluster-name           Name of the cluster to check (e.g., dm-nkp-workload-1)

Options:
  --kind KIND          Filter by kind (ClusterApp or App)
  --scope SCOPE        Filter by scope (workspace or project)
  --type TYPE          Filter by type (custom, internal, nkp-catalog, nkp-core-platform)
  --enabled-only       Show only enabled apps
  --disabled-only      Show only disabled apps
  -h, --help           Show this help message

Examples:
  # List all apps for a cluster
  $0 dm-nkp-workload-1

  # List only enabled apps
  $0 dm-nkp-workload-1 --enabled-only

  # List only disabled ClusterApps
  $0 dm-nkp-workload-1 --disabled-only --kind ClusterApp

  # List workspace-scoped apps
  $0 dm-nkp-workload-1 --scope workspace
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if KUBECONFIG is set
if [ -z "${KUBECONFIG:-}" ]; then
  echo -e "${RED}Error: KUBECONFIG environment variable is not set${NC}"
  echo "Please set it to your management cluster kubeconfig:"
  echo "  export KUBECONFIG=/path/to/kubeconfig"
  exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
  exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_SCRIPT="${SCRIPT_DIR}/list-clusterapps-and-apps.sh"

if [ ! -f "$LIST_SCRIPT" ]; then
  echo -e "${RED}Error: Cannot find list-clusterapps-and-apps.sh at $LIST_SCRIPT${NC}"
  exit 1
fi

# Build command for list-clusterapps-and-apps.sh
LIST_CMD="$LIST_SCRIPT --check-deployments --no-color"

if [ -n "$FILTER_KIND" ]; then
  LIST_CMD="$LIST_CMD --kind $FILTER_KIND"
fi

if [ -n "$FILTER_SCOPE" ]; then
  LIST_CMD="$LIST_CMD --scope $FILTER_SCOPE"
fi

if [ -n "$FILTER_TYPE" ]; then
  LIST_CMD="$LIST_CMD --type $FILTER_TYPE"
fi

# Run the list script and capture output
echo -e "${BOLD}${CYAN}Checking apps for cluster: ${CLUSTER_NAME}${NC}"
echo ""

# Temporary files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

ENABLED_FILE="$TEMP_DIR/enabled.txt"
DISABLED_FILE="$TEMP_DIR/disabled.txt"

# Parse output from list-clusterapps-and-apps.sh
# The script outputs apps with deployment status like:
# "  ✓ Enabled on clusters: cluster1,cluster2 | Status: ..."
# "  ○ Not enabled"

CURRENT_APP=""
CURRENT_KIND=""
CURRENT_SCOPE=""
CURRENT_TYPE=""

while IFS= read -r line; do
  # Skip empty lines and section headers
  if [[ -z "$line" ]] || [[ "$line" =~ ^[═║┌├└] ]] || [[ "$line" =~ ^Type: ]] || [[ "$line" =~ ^Summary ]]; then
    continue
  fi

  # Check if this is a table header row
  if [[ "$line" =~ ^Kind.*Name.*Version ]]; then
    continue
  fi

  # Check if this is a table separator row
  if [[ "$line" =~ ^[│├└] ]]; then
    # Parse table row - format: | Kind | Name | Version | Display Name | Scope | Type | Licensing | Dependencies |
    if [[ "$line" =~ \│[[:space:]]*([^│]+)[│][[:space:]]*([^│]+)[│][[:space:]]*([^│]+)[│][[:space:]]*([^│]+)[│][[:space:]]*([^│]+)[│][[:space:]]*([^│]+) ]]; then
      CURRENT_KIND=$(echo "${BASH_REMATCH[1]}" | xargs)
      CURRENT_APP=$(echo "${BASH_REMATCH[2]}" | xargs)
      CURRENT_SCOPE=$(echo "${BASH_REMATCH[5]}" | xargs)
      CURRENT_TYPE=$(echo "${BASH_REMATCH[6]}" | xargs)
    fi
    continue
  fi

  # Check for enabled/disabled status
  if [[ "$line" =~ ✓[[:space:]]*Enabled[[:space:]]*on[[:space:]]*clusters: ]]; then
    # Extract cluster list
    if [[ "$line" =~ clusters:[[:space:]]*([^|]+) ]]; then
      CLUSTERS=$(echo "${BASH_REMATCH[1]}" | xargs)
      # Check if our cluster is in the list
      if echo "$CLUSTERS" | grep -q "$CLUSTER_NAME"; then
        if [ -n "$CURRENT_APP" ]; then
          echo "$CURRENT_KIND|$CURRENT_APP|$CURRENT_SCOPE|$CURRENT_TYPE" >> "$ENABLED_FILE"
        fi
      fi
    fi
  elif [[ "$line" =~ ○[[:space:]]*Not[[:space:]]*enabled ]]; then
    if [ -n "$CURRENT_APP" ]; then
      echo "$CURRENT_KIND|$CURRENT_APP|$CURRENT_SCOPE|$CURRENT_TYPE" >> "$DISABLED_FILE"
    fi
  fi
done < <($LIST_CMD 2>/dev/null || true)

# Alternative method: directly query AppDeploymentInstances for the cluster
# This is more reliable than parsing the output
echo "" > "$ENABLED_FILE"
echo "" > "$DISABLED_FILE"

# Get all AppDeployments and check which ones target this cluster
APP_DEPLOYMENTS=$(kubectl get appdeployment -A -o json 2>/dev/null | \
  jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.spec.appRef.kind)|\(.spec.appRef.name)"' 2>/dev/null || true)

ENABLED_APPS=()
DISABLED_APPS=()

# Get all ClusterApps and Apps
ALL_CLUSTERAPPS=$(kubectl get clusterapps -A -o json 2>/dev/null | \
  jq -r '.items[] | "\(.kind)|\(.metadata.name)|\(.metadata.annotations."apps.kommander.d2iq.io/scope" // "N/A")|\(.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A")"' 2>/dev/null || true)

ALL_APPS=$(kubectl get apps -A -o json 2>/dev/null | \
  jq -r '.items[] | "\(.kind)|\(.metadata.name)|\(.metadata.namespace)|\(.metadata.annotations."apps.kommander.d2iq.io/scope" // "N/A")|\(.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A")"' 2>/dev/null || true)

# Check each ClusterApp
while IFS='|' read -r kind name scope type; do
  # Apply filters
  if [ -n "$FILTER_KIND" ] && [ "$kind" != "$FILTER_KIND" ]; then
    continue
  fi
  if [ -n "$FILTER_SCOPE" ] && [ "$scope" != "$FILTER_SCOPE" ]; then
    continue
  fi
  if [ -n "$FILTER_TYPE" ] && ! echo "$type" | grep -qi "$FILTER_TYPE"; then
    continue
  fi

  # Check if there's an AppDeployment for this ClusterApp that targets our cluster
  APP_DEPLOYMENT=$(echo "$APP_DEPLOYMENTS" | grep "^[^|]*|[^|]*|ClusterApp|${name}$" | head -1)

  if [ -z "$APP_DEPLOYMENT" ]; then
    DISABLED_APPS+=("$kind|$name|$scope|$type")
    continue
  fi

  # Extract AppDeployment namespace and name
  AD_NS=$(echo "$APP_DEPLOYMENT" | cut -d'|' -f1)
  AD_NAME=$(echo "$APP_DEPLOYMENT" | cut -d'|' -f2)

  # Check if this AppDeployment targets our cluster
  TARGETS_CLUSTER=false

  # Check cluster selector in AppDeployment
  CLUSTER_SELECTOR=$(kubectl get appdeployment "$AD_NAME" -n "$AD_NS" -o json 2>/dev/null | \
    jq -r '.spec.clusterSelector.matchLabels."kommander.d2iq.io/cluster-name" // empty' 2>/dev/null || echo "")

  if [ "$CLUSTER_SELECTOR" = "$CLUSTER_NAME" ]; then
    TARGETS_CLUSTER=true
  fi

  # Check cluster config overrides
  if [ "$TARGETS_CLUSTER" = false ]; then
    CLUSTER_VALUES=$(kubectl get appdeployment "$AD_NAME" -n "$AD_NS" -o json 2>/dev/null | \
      jq -r '.spec.clusterConfigOverrides[]?.clusterSelector.matchExpressions[]?.values[]? // .spec.clusterSelector.matchExpressions[]?.values[]? // empty' 2>/dev/null || echo "")

    if echo "$CLUSTER_VALUES" | grep -q "^${CLUSTER_NAME}$"; then
      TARGETS_CLUSTER=true
    fi
  fi

  # Check AppDeploymentInstance for this cluster
  if [ "$TARGETS_CLUSTER" = false ]; then
    INSTANCE=$(kubectl get appdeploymentinstance -n "$AD_NS" -o json 2>/dev/null | \
      jq -r --arg AD_NAME "$AD_NAME" --arg CLUSTER "$CLUSTER_NAME" \
      '.items[] | select(.metadata.ownerReferences[]?.name == $AD_NAME and
        (.metadata.labels."apps.kommander.nutanix.com/kommander-cluster" // "") == $CLUSTER) |
      .metadata.name' 2>/dev/null | head -1)

    if [ -n "$INSTANCE" ]; then
      TARGETS_CLUSTER=true
    fi
  fi

  if [ "$TARGETS_CLUSTER" = true ]; then
    ENABLED_APPS+=("$kind|$name|$scope|$type")
  else
    DISABLED_APPS+=("$kind|$name|$scope|$type")
  fi
done <<< "$ALL_CLUSTERAPPS"

# Check each App
while IFS='|' read -r kind name namespace scope type; do
  # Apply filters
  if [ -n "$FILTER_KIND" ] && [ "$kind" != "$FILTER_KIND" ]; then
    continue
  fi
  if [ -n "$FILTER_SCOPE" ] && [ "$scope" != "$FILTER_SCOPE" ]; then
    continue
  fi
  if [ -n "$FILTER_TYPE" ] && ! echo "$type" | grep -qi "$FILTER_TYPE"; then
    continue
  fi

  # Check if there's an AppDeployment for this App that targets our cluster
  APP_DEPLOYMENT=$(echo "$APP_DEPLOYMENTS" | grep "^[^|]*|[^|]*|App|${name}$" | grep "|${namespace}$" | head -1)

  if [ -z "$APP_DEPLOYMENT" ]; then
    DISABLED_APPS+=("$kind|$name|$scope|$type")
    continue
  fi

  # Extract AppDeployment namespace and name
  AD_NS=$(echo "$APP_DEPLOYMENT" | cut -d'|' -f1)
  AD_NAME=$(echo "$APP_DEPLOYMENT" | cut -d'|' -f2)

  # Check if this AppDeployment targets our cluster (same logic as above)
  TARGETS_CLUSTER=false

  CLUSTER_SELECTOR=$(kubectl get appdeployment "$AD_NAME" -n "$AD_NS" -o json 2>/dev/null | \
    jq -r '.spec.clusterSelector.matchLabels."kommander.d2iq.io/cluster-name" // empty' 2>/dev/null || echo "")

  if [ "$CLUSTER_SELECTOR" = "$CLUSTER_NAME" ]; then
    TARGETS_CLUSTER=true
  fi

  if [ "$TARGETS_CLUSTER" = false ]; then
    CLUSTER_VALUES=$(kubectl get appdeployment "$AD_NAME" -n "$AD_NS" -o json 2>/dev/null | \
      jq -r '.spec.clusterConfigOverrides[]?.clusterSelector.matchExpressions[]?.values[]? // .spec.clusterSelector.matchExpressions[]?.values[]? // empty' 2>/dev/null || echo "")

    if echo "$CLUSTER_VALUES" | grep -q "^${CLUSTER_NAME}$"; then
      TARGETS_CLUSTER=true
    fi
  fi

  if [ "$TARGETS_CLUSTER" = false ]; then
    INSTANCE=$(kubectl get appdeploymentinstance -n "$AD_NS" -o json 2>/dev/null | \
      jq -r --arg AD_NAME "$AD_NAME" --arg CLUSTER "$CLUSTER_NAME" \
      '.items[] | select(.metadata.ownerReferences[]?.name == $AD_NAME and
        (.metadata.labels."apps.kommander.nutanix.com/kommander-cluster" // "") == $CLUSTER) |
      .metadata.name' 2>/dev/null | head -1)

    if [ -n "$INSTANCE" ]; then
      TARGETS_CLUSTER=true
    fi
  fi

  if [ "$TARGETS_CLUSTER" = true ]; then
    ENABLED_APPS+=("$kind|$name|$scope|$type")
  else
    DISABLED_APPS+=("$kind|$name|$scope|$type")
  fi
done <<< "$ALL_APPS"

# Print results
ENABLED_COUNT=${#ENABLED_APPS[@]}
DISABLED_COUNT=${#DISABLED_APPS[@]}

# Print enabled apps
if [ "$DISABLED_ONLY" = false ] && ([ "$ENABLED_ONLY" = true ] || [ "$ENABLED_COUNT" -gt 0 ]); then
  echo -e "${BOLD}${GREEN}Enabled Apps (${ENABLED_COUNT}):${NC}"
  if [ "$ENABLED_COUNT" -eq 0 ]; then
    echo "  (none)"
  else
    printf "%-15s %-45s %-12s %-25s\n" "Kind" "Name" "Scope" "Type"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────"
    for app in "${ENABLED_APPS[@]}"; do
      IFS='|' read -r kind name scope type <<< "$app"
      printf "%-15s %-45s %-12s %-25s\n" "$kind" "$name" "$scope" "$type"
    done | sort -t'|' -k2,2
  fi
  echo ""
fi

# Print disabled apps
if [ "$ENABLED_ONLY" = false ] && ([ "$DISABLED_ONLY" = true ] || [ "$DISABLED_COUNT" -gt 0 ]); then
  echo -e "${BOLD}${YELLOW}Disabled Apps (${DISABLED_COUNT}):${NC}"
  if [ "$DISABLED_COUNT" -eq 0 ]; then
    echo "  (none)"
  else
    printf "%-15s %-45s %-12s %-25s\n" "Kind" "Name" "Scope" "Type"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────"
    for app in "${DISABLED_APPS[@]}"; do
      IFS='|' read -r kind name scope type <<< "$app"
      printf "%-15s %-45s %-12s %-25s\n" "$kind" "$name" "$scope" "$type"
    done | sort -t'|' -k2,2
  fi
  echo ""
fi

# Print summary
if [ "$ENABLED_ONLY" = false ] && [ "$DISABLED_ONLY" = false ]; then
  echo -e "${BOLD}Summary:${NC}"
  echo -e "  ${GREEN}Enabled:${NC}  ${ENABLED_COUNT}"
  echo -e "  ${YELLOW}Disabled:${NC} ${DISABLED_COUNT}"
  echo -e "  ${CYAN}Total:${NC}    $((ENABLED_COUNT + DISABLED_COUNT))"
fi

