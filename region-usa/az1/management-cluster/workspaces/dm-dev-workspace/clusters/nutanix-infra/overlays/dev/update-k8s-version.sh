#!/bin/bash
# Helper script to update k8s version for all clusters in dev overlay
#
# Usage:
#   ./update-k8s-version.sh NEW_VERSION
#
# Example:
#   ./update-k8s-version.sh v1.35.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZATION_FILE="${SCRIPT_DIR}/kustomization.yaml"

if [ $# -ne 1 ]; then
    echo "Usage: $0 NEW_VERSION"
    echo ""
    echo "Example:"
    echo "  $0 v1.35.0"
    exit 1
fi

NEW_VERSION="$1"

if [ ! -f "$KUSTOMIZATION_FILE" ]; then
    echo "Error: kustomization.yaml not found at $KUSTOMIZATION_FILE"
    exit 1
fi

# Check if version patches already exist
if grep -q "path: /spec/topology/version" "$KUSTOMIZATION_FILE"; then
    echo "Version patches already exist. Updating..."
    # Extract old version and replace
    OLD_VERSION=$(grep -A 1 "path: /spec/topology/version" "$KUSTOMIZATION_FILE" | grep "value:" | head -1 | awk '{print $2}' | tr -d '"')
    if [ -n "$OLD_VERSION" ]; then
        echo "Found existing version: $OLD_VERSION"
        sed -i.tmp "s|value: $OLD_VERSION|value: $NEW_VERSION|g" "$KUSTOMIZATION_FILE"
        rm -f "${KUSTOMIZATION_FILE}.tmp"
        echo "✓ Updated version to $NEW_VERSION"
    fi
else
    echo "Version patches not found. Adding version patches for all clusters..."

    # Create backup
    cp "$KUSTOMIZATION_FILE" "${KUSTOMIZATION_FILE}.bak"

    # Find all cluster names in COMMON PATCHES section
    CLUSTERS=$(grep -A 1 "kind: Cluster" "$KUSTOMIZATION_FILE" | grep "name:" | awk '{print $2}' | sort -u)

    # Add version patches after COMMON PATCHES section
    # This is a simple approach - you may need to adjust based on your file structure
    echo ""
    echo "Please manually add version patches for each cluster:"
    for CLUSTER in $CLUSTERS; do
        echo "  - target:"
        echo "      kind: Cluster"
        echo "      name: $CLUSTER"
        echo "    patch: |-"
        echo "      - op: replace"
        echo "        path: /spec/topology/version"
        echo "        value: $NEW_VERSION"
    done
    echo ""
    echo "Add these patches in the COMMON PATCHES section of kustomization.yaml"
fi

echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff $KUSTOMIZATION_FILE"
echo "  2. Test the build: kustomize build $SCRIPT_DIR"
echo "  3. Commit if satisfied: git add $KUSTOMIZATION_FILE && git commit -m 'Update k8s version to $NEW_VERSION'"

