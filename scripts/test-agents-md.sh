#!/bin/bash
# test-agents-md.sh - Automated validation tests for AGENTS.md

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🧪 Testing AGENTS.md..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

test_check() {
    local test_name="$1"
    local command="$2"

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED++))
        return 1
    fi
}

# Test 1: Check if AGENTS.md exists
echo "📄 File Existence Tests"
echo "───────────────────────"
test_check "AGENTS.md file exists" "[ -f AGENTS.md ]"
test_check "AGENTS.md is readable" "[ -r AGENTS.md ]"
echo ""

# Test 2: Check critical sections
echo "📋 Content Structure Tests"
echo "───────────────────────────"
test_check "Dependencies section exists" "grep -q 'Flux Kustomization Dependencies' AGENTS.md"
test_check "Sealed Secrets section exists" "grep -q 'Sealed Secrets' AGENTS.md"
test_check "Naming Conventions section exists" "grep -q 'Naming Conventions' AGENTS.md"
test_check "Common Mistakes section exists" "grep -q 'Common Mistakes' AGENTS.md"
test_check "Quick Reference section exists" "grep -q 'Quick Reference' AGENTS.md"
test_check "Security Guidelines section exists" "grep -q 'Security Guidelines' AGENTS.md"
echo ""

# Test 3: Check if referenced paths exist
echo "📁 Referenced Path Tests"
echo "───────────────────────"
test_check "DEBUGGING-GITOPS.md exists" "[ -f docs/DEBUGGING-GITOPS.md ]"
test_check "NKP-RBAC-GUIDE.md exists" "[ -f docs/NKP-RBAC-GUIDE.md ]"
test_check "scripts/README.md exists" "[ -f scripts/README.md ]"
test_check "Main README.md exists" "[ -f README.md ]"
test_check "USA AZ1 bootstrap exists" "[ -f region-usa/az1/management-cluster/bootstrap.yaml ]"
echo ""

# Test 4: Check if examples contain valid patterns
echo "🔍 Pattern Validation Tests"
echo "───────────────────────────"
test_check "Contains GitRepository example" "grep -q 'kind: GitRepository' AGENTS.md"
test_check "Contains Kustomization example" "grep -q 'kind: Kustomization' AGENTS.md"
test_check "Contains kubectl commands" "grep -q 'kubectl' AGENTS.md"
test_check "Contains flux commands" "grep -q 'flux' AGENTS.md"
test_check "Contains kustomize commands" "grep -q 'kustomize' AGENTS.md"
echo ""

# Test 5: Check naming convention examples
echo "🏷️  Naming Convention Tests"
echo "───────────────────────────"
test_check "Contains gitops naming pattern" "grep -q 'gitops-{region}-{az}' AGENTS.md"
test_check "Contains clusterops naming pattern" "grep -q 'clusterops-' AGENTS.md"
test_check "Contains namespace examples" "grep -q 'dm-nkp-gitops-infra' AGENTS.md"
echo ""

# Test 6: Check security guidelines
echo "🔒 Security Guidelines Tests"
echo "───────────────────────────"
test_check "Mentions Sealed Secrets requirement" "grep -qi 'sealed.*secret' AGENTS.md"
test_check "Warns against plaintext secrets" "grep -qi 'plaintext\|never.*commit.*secret' AGENTS.md"
test_check "References sealed-secrets key location" "grep -q '/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml' AGENTS.md"
echo ""

# Test 7: Check dependency information
echo "🔗 Dependency Information Tests"
echo "───────────────────────────────"
test_check "Lists dependency levels" "grep -q 'Level 0\|Level 1\|Level 2' AGENTS.md"
test_check "Mentions dependsOn" "grep -q 'dependsOn' AGENTS.md"
test_check "Contains dependency chain example" "grep -q 'clusterops-clusters' AGENTS.md && grep -q 'depends' AGENTS.md"
echo ""

# Test 8: Check file structure examples
echo "📂 File Structure Tests"
echo "───────────────────────"
test_check "Contains region structure example" "grep -q 'region-{region}' AGENTS.md"
test_check "Contains workspace path example" "grep -q 'workspaces/{workspace}' AGENTS.md"
test_check "Contains cluster path example" "grep -q 'clusters/' AGENTS.md"
echo ""

# Test 9: Check command examples
echo "💻 Command Examples Tests"
echo "───────────────────────"
test_check "Contains kubectl get commands" "grep -q 'kubectl get' AGENTS.md"
test_check "Contains flux reconcile commands" "grep -q 'flux reconcile' AGENTS.md"
test_check "Contains kustomize build commands" "grep -q 'kustomize build' AGENTS.md"
echo ""

# Test 10: Check if it's well-organized
echo "Organization Tests"
echo "────────────────────"
test_check "Has table of contents or clear sections" "grep -q '^##' AGENTS.md"
test_check "Has code examples" "grep -q '\`\`\`' AGENTS.md"
SECTION_COUNT=$(grep -c '^##' AGENTS.md 2>/dev/null || echo "0")
if [ "$SECTION_COUNT" -ge 10 ]; then
    echo -e "${GREEN}✓${NC} Has at least 10 major sections"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Has at least 10 major sections (found: $SECTION_COUNT)"
    ((FAILED++))
fi
echo ""

# Summary
echo "───────────────────────"
echo "📊 Test Summary"
echo "───────────────────────"
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    echo ""
    echo "⚠️  Some tests failed. Review AGENTS.md and fix the issues."
    exit 1
else
    echo -e "${GREEN}Failed: $FAILED${NC}"
    echo ""
    echo "✅ All automated tests passed!"
    echo ""
    echo "💡 Next steps:"
    echo "   1. Test with an AI agent using scenarios from docs/TESTING-AGENTS.md"
    echo "   2. Ask the agent to perform common tasks"
    echo "   3. Verify the agent follows conventions from AGENTS.md"
fi

