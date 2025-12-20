# Testing AGENTS.md - Validation Guide

This document provides test scenarios to validate that `AGENTS.md` is effective and usable by AI agents.

## Test Approach

### 1. **Information Retrieval Tests**
Test if agents can find and use information from AGENTS.md

### 2. **Task Execution Tests**
Test if agents can perform common tasks using AGENTS.md guidance

### 3. **Error Prevention Tests**
Test if agents avoid common mistakes when following AGENTS.md

### 4. **Edge Case Tests**
Test if agents handle unusual scenarios correctly

---

## Test Scenarios

### Test 1: Adding a New Application

**Prompt to Agent:**
> "I need to add a new application called 'my-app' to the dm-dev-workspace. It should be a platform-level application."

**Expected Behavior:**
- Agent should identify this as a workspace-level application
- Agent should create the file in: `region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/{category}/my-app/`
- Agent should update the parent `kustomization.yaml`
- Agent should follow the naming conventions from AGENTS.md

**Validation:**
```bash
# Check if file was created in correct location
ls -la region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/*/my-app/

# Check if kustomization.yaml was updated
grep -r "my-app" region-usa/az1/management-cluster/workspaces/dm-dev-workspace/applications/*/kustomization.yaml
```

---

### Test 2: Understanding Dependencies

**Prompt to Agent:**
> "Why is clusterops-clusters failing? Check the dependencies."

**Expected Behavior:**
- Agent should check dependency chain from AGENTS.md
- Agent should verify that `clusterops-workspaces` and `clusterops-sealed-secrets` are ready
- Agent should use the dependency debugging commands from AGENTS.md

**Validation:**
```bash
# Agent should run these commands:
kubectl get kustomization clusterops-workspaces -n dm-nkp-gitops-infra -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
kubectl get kustomization clusterops-sealed-secrets -n dm-nkp-gitops-infra -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

---

### Test 3: Security - Sealed Secrets

**Prompt to Agent:**
> "I need to add credentials for a new cluster. Create a secret with username 'admin' and password 'secret123'."

**Expected Behavior:**
- Agent should **NOT** create a plaintext Secret
- Agent should use Sealed Secrets
- Agent should reference the sealed-secrets key backup location
- Agent should follow the security guidelines from AGENTS.md

**Validation:**
```bash
# Check that NO plaintext secrets were created
grep -r "secret123" region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/*/sealed-secrets/ || echo "Good - no plaintext found"

# Check that SealedSecret was created instead
find region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters -name "*sealed-secret*.yaml" -type f
```

---

### Test 4: Adding a New Region/AZ

**Prompt to Agent:**
> "Add a new availability zone az2 for region-usa."

**Expected Behavior:**
- Agent should copy structure from az1
- Agent should update ALL names, paths, and references
- Agent should create new bootstrap.yaml with correct paths
- Agent should follow the multi-region pattern from AGENTS.md

**Validation:**
```bash
# Check bootstrap.yaml has correct paths
grep "path:" region-usa/az2/management-cluster/bootstrap.yaml
# Should show: ./region-usa/az2/management-cluster

# Check GitRepository name
grep "name:" region-usa/az2/management-cluster/bootstrap.yaml
# Should show: gitops-usa-az2

# Check Kustomization name
grep "name:" region-usa/az2/management-cluster/bootstrap.yaml | grep -i kustomization
# Should show: clusterops-usa-az2
```

---

### Test 5: Modifying Cluster Configuration

**Prompt to Agent:**
> "Update dm-nkp-workload-1 to use NKP version 2.18.0 and increase workers to 5."

**Expected Behavior:**
- Agent should NOT modify base files directly
- Agent should create/update overlay in `overlays/2.18.0/`
- Agent should use JSON patches (not strategic merge)
- Agent should test locally with `kustomize build`

**Validation:**
```bash
# Check overlay was created/updated
ls -la region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.18.0/

# Check JSON patch format (not strategic merge)
grep -A 5 "op:" region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.18.0/kustomization.yaml

# Verify base wasn't modified
git diff region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/bases/
```

---

### Test 6: Finding Documentation

**Prompt to Agent:**
> "How do I debug a Flux Kustomization that's stuck?"

**Expected Behavior:**
- Agent should reference `docs/DEBUGGING-GITOPS.md` from AGENTS.md
- Agent should provide relevant debugging commands
- Agent should check dependency status

**Validation:**
- Agent mentions DEBUGGING-GITOPS.md
- Agent provides specific kubectl/flux commands
- Agent checks dependencies first

---

### Test 7: Understanding File Structure

**Prompt to Agent:**
> "Where should I put a new Gatekeeper policy?"

**Expected Behavior:**
- Agent should identify `_common/policies/gatekeeper/` as the location
- Agent should create ConstraintTemplate in `constraint-templates/{category}/`
- Agent should create Constraint in `constraints/{category}/`
- Agent should update kustomization.yaml files

**Validation:**
```bash
# Check policy was added to _common (not cluster-specific)
find region-usa/az1/_common/policies/gatekeeper -name "*.yaml" -newer AGENTS.md

# Check kustomization.yaml was updated
grep -r "new-policy" region-usa/az1/_common/policies/gatekeeper/*/kustomization.yaml
```

---

### Test 8: Naming Conventions

**Prompt to Agent:**
> "Create a new Flux Kustomization for managing monitoring applications."

**Expected Behavior:**
- Agent should follow naming convention: `clusterops-{category}`
- Agent should use appropriate namespace: `dm-nkp-gitops-infra`
- Agent should set correct `sourceRef` and `path`
- Agent should specify `dependsOn` if needed

**Validation:**
```bash
# Check naming convention
grep "name:" region-usa/az1/management-cluster/global/monitoring/flux-ks.yaml
# Should match pattern: clusterops-monitoring or clusterops-workspace-monitoring

# Check namespace
grep "namespace:" region-usa/az1/management-cluster/global/monitoring/flux-ks.yaml
# Should be: dm-nkp-gitops-infra
```

---

### Test 9: Error Prevention - Circular Dependencies

**Prompt to Agent:**
> "Create a new Kustomization that depends on clusterops-clusters, and make clusterops-clusters depend on it."

**Expected Behavior:**
- Agent should **REJECT** this request
- Agent should explain why circular dependencies are bad
- Agent should reference the dependency chain from AGENTS.md
- Agent should suggest a better approach

**Validation:**
- No circular dependencies created
- Agent explains the issue
- Agent suggests alternative structure

---

### Test 10: Quick Reference Usage

**Prompt to Agent:**
> "How do I force reconcile a Kustomization?"

**Expected Behavior:**
- Agent should provide command from Quick Reference section
- Agent should use correct namespace
- Agent should provide both flux CLI and kubectl annotation methods

**Validation:**
- Command matches Quick Reference section
- Uses correct namespace: `dm-nkp-gitops-infra`
- Provides alternative methods

---

## Automated Test Script

Create a test script that validates key aspects:

```bash
#!/bin/bash
# test-agents-md.sh - Automated tests for AGENTS.md

echo "Testing AGENTS.md..."

# Test 1: Check if critical sections exist
echo "✓ Checking critical sections..."
grep -q "Flux Kustomization Dependencies" AGENTS.md && echo "  ✓ Dependencies section found" || echo "  ✗ Dependencies section missing"
grep -q "Sealed Secrets" AGENTS.md && echo "  ✓ Sealed Secrets section found" || echo "  ✗ Sealed Secrets section missing"
grep -q "Naming Conventions" AGENTS.md && echo "  ✓ Naming Conventions found" || echo "  ✗ Naming Conventions missing"
grep -q "Common Mistakes" AGENTS.md && echo "  ✓ Common Mistakes found" || echo "  ✗ Common Mistakes missing"

# Test 2: Check if examples are valid YAML
echo "✓ Checking YAML examples..."
yq eval '.apiVersion' <(grep -A 10 "apiVersion:" AGENTS.md | head -1) > /dev/null 2>&1 && echo "  ✓ YAML examples are valid" || echo "  ✗ YAML examples may be invalid"

# Test 3: Check if paths exist
echo "✓ Checking referenced paths..."
PATHS=(
  "region-usa/az1/management-cluster/bootstrap.yaml"
  "docs/DEBUGGING-GITOPS.md"
  "docs/NKP-RBAC-GUIDE.md"
  "scripts/README.md"
)
for path in "${PATHS[@]}"; do
  [ -f "$path" ] && echo "  ✓ $path exists" || echo "  ✗ $path missing"
done

# Test 4: Check if commands are executable (syntax check)
echo "✓ Checking command syntax..."
grep -E "kubectl|flux|kustomize" AGENTS.md | head -5 | while read cmd; do
  echo "  Checking: $cmd"
done

echo ""
echo "Test complete!"
```

---

## Manual Testing Checklist

Use this checklist when testing with an actual AI agent:

- [ ] Agent can find information about dependencies
- [ ] Agent follows naming conventions correctly
- [ ] Agent uses Sealed Secrets (never plaintext)
- [ ] Agent creates JSON patches (not strategic merge) for overlays
- [ ] Agent references correct paths and namespaces
- [ ] Agent checks dependencies before creating new Kustomizations
- [ ] Agent uses correct directory structure
- [ ] Agent references documentation files correctly
- [ ] Agent provides correct commands from Quick Reference
- [ ] Agent avoids common mistakes listed in AGENTS.md

---

## Testing with AI Agent (Recommended)

### Step 1: Ask the agent to read AGENTS.md
> "Please read AGENTS.md and summarize the key conventions for this repository."

**Expected:** Agent should mention:
- Flux dependency chains
- Sealed Secrets requirement
- JSON patches for overlays
- Naming conventions
- Multi-region structure

### Step 2: Give a realistic task
> "Add a new monitoring application called 'prometheus-operator' to the dm-dev-workspace as a platform application."

**Expected:** Agent should:
- Create file in correct location
- Follow naming conventions
- Update kustomization.yaml
- Use correct structure

### Step 3: Test error handling
> "Create a secret with password 'mypassword123' for cluster credentials."

**Expected:** Agent should:
- Refuse to create plaintext secret
- Suggest using Sealed Secrets
- Reference security guidelines

### Step 4: Test debugging knowledge
> "The clusterops-clusters Kustomization is failing. Help me debug it."

**Expected:** Agent should:
- Check dependencies first
- Use commands from DEBUGGING-GITOPS.md
- Check GitRepository status
- Verify sealed secrets

---

## Success Criteria

AGENTS.md is effective if:

1. ✅ Agent can find information within 1-2 queries
2. ✅ Agent follows conventions without being explicitly told
3. ✅ Agent avoids common mistakes automatically
4. ✅ Agent provides correct commands and paths
5. ✅ Agent references related documentation
6. ✅ Agent explains reasoning using AGENTS.md content

---

## Continuous Improvement

After testing, update AGENTS.md based on:

1. **Missing Information**: If agent asks questions not covered
2. **Unclear Sections**: If agent misunderstands instructions
3. **Incomplete Examples**: If examples don't work as expected
4. **Common Confusions**: If agent makes same mistakes repeatedly

---

## Quick Test Commands

Run these to quickly validate AGENTS.md:

```bash
# Check if agent can find key information
grep -i "dependency\|sealed\|json patch\|naming" AGENTS.md | head -10

# Check if examples are complete
grep -A 5 "apiVersion:" AGENTS.md | head -20

# Check if paths are correct
grep -E "region-usa|dm-dev-workspace|dm-nkp-gitops" AGENTS.md | head -10

# Validate YAML snippets (if yq is installed)
yq eval '.' <(grep -A 20 "kind: Kustomization" AGENTS.md | head -20) 2>&1
```

---

## Feedback Loop

When testing reveals issues:

1. **Document the gap** - What information was missing?
2. **Update AGENTS.md** - Add missing information
3. **Re-test** - Verify the fix works
4. **Iterate** - Continue improving

---

## Example Test Session

```bash
# Start a test session with an AI agent

# Test 1: Information retrieval
> "What are the dependency levels for Flux Kustomizations?"
Expected: Agent lists Level 0, 1, 2, 3, 4 from AGENTS.md

# Test 2: Task execution
> "Add a new application 'test-app' to dm-dev-workspace"
Expected: Agent creates file in correct location, updates kustomization.yaml

# Test 3: Security check
> "I need to store a password for my app"
Expected: Agent suggests Sealed Secrets, refuses plaintext

# Test 4: Error handling
> "Why is my Kustomization failing?"
Expected: Agent checks dependencies, GitRepository, provides debugging steps
```

---

## Conclusion

Regular testing ensures AGENTS.md remains:
- **Accurate** - Information is correct and up-to-date
- **Complete** - Covers all common scenarios
- **Usable** - Easy for agents to find and apply information
- **Effective** - Prevents mistakes and guides correct behavior

