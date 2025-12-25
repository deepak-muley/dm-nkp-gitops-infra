#!/bin/bash
# Helper script to update image name for all clusters in dev overlay
#
# Usage:
#   ./update-image-name.sh OLD_IMAGE_NAME NEW_IMAGE_NAME
#
# Example:
#   ./update-image-name.sh nkp-rocky-9.6-release-1.34.1-20251225180234 nkp-rocky-9.6-release-1.35.0-20260101120000

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZATION_FILE="${SCRIPT_DIR}/kustomization.yaml"

if [ $# -ne 2 ]; then
    echo "Usage: $0 OLD_IMAGE_NAME NEW_IMAGE_NAME"
    echo ""
    echo "Example:"
    echo "  $0 nkp-rocky-9.6-release-1.34.1-20251225180234 nkp-rocky-9.6-release-1.35.0-20260101120000"
    exit 1
fi

OLD_IMAGE="$1"
NEW_IMAGE="$2"

if [ ! -f "$KUSTOMIZATION_FILE" ]; then
    echo "Error: kustomization.yaml not found at $KUSTOMIZATION_FILE"
    exit 1
fi

# Count occurrences
COUNT=$(grep -c "$OLD_IMAGE" "$KUSTOMIZATION_FILE" || true)

if [ "$COUNT" -eq 0 ]; then
    echo "Warning: Image name '$OLD_IMAGE' not found in kustomization.yaml"
    exit 1
fi

echo "Found $COUNT occurrences of '$OLD_IMAGE'"
echo "Replacing with '$NEW_IMAGE'..."

# Create backup
cp "$KUSTOMIZATION_FILE" "${KUSTOMIZATION_FILE}.bak"

# Replace in place
sed -i.tmp "s|$OLD_IMAGE|$NEW_IMAGE|g" "$KUSTOMIZATION_FILE"
rm -f "${KUSTOMIZATION_FILE}.tmp"

echo "✓ Updated image name in kustomization.yaml"
echo "  Backup saved to: ${KUSTOMIZATION_FILE}.bak"
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff $KUSTOMIZATION_FILE"
echo "  2. Test the build: kustomize build $SCRIPT_DIR"
echo "  3. Commit if satisfied: git add $KUSTOMIZATION_FILE && git commit -m 'Update image to $NEW_IMAGE'"

