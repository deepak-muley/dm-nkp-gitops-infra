#!/bin/bash
#
# NKP Policy Violations Checker (Gatekeeper & Kyverno)
#
# Usage:
#   ./check-violations.sh                       # Check both engines, default kubeconfig
#   ./check-violations.sh -e gatekeeper         # Check only Gatekeeper
#   ./check-violations.sh -e kyverno            # Check only Kyverno
#   ./check-violations.sh -e both               # Check both engines (default)
#   ./check-violations.sh /path/to/kubeconfig   # Uses specified kubeconfig
#   ./check-violations.sh --summary             # Show only summary
#   ./check-violations.sh --export              # Export to violations-report.json
#   ./check-violations.sh -n <namespace>        # Filter violations for a specific namespace
#   ./check-violations.sh --namespace <ns>      # Filter violations for a specific namespace
#
# Author: Platform Team
# Date: December 2024
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default kubeconfig locations for NKP clusters
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
DEFAULT_WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

KUBECONFIG_FILE=""
SUMMARY_ONLY=false
EXPORT_JSON=false
NAMESPACE=""
POLICY_ENGINE="both"  # gatekeeper, kyverno, or both

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --engine|-e)
            if [[ -n "$2" && "$2" != -* ]]; then
                POLICY_ENGINE="$2"
                if [[ "$POLICY_ENGINE" != "gatekeeper" && "$POLICY_ENGINE" != "kyverno" && "$POLICY_ENGINE" != "both" ]]; then
                    echo -e "${RED}Error: --engine must be 'gatekeeper', 'kyverno', or 'both'${NC}"
                    exit 1
                fi
                shift 2
            else
                echo -e "${RED}Error: --engine requires a value (gatekeeper, kyverno, or both)${NC}"
                exit 1
            fi
            ;;
        --summary)
            SUMMARY_ONLY=true
            shift
            ;;
        --export)
            EXPORT_JSON=true
            shift
            ;;
        --namespace|-n)
            if [[ -n "$2" && "$2" != -* ]]; then
                NAMESPACE="$2"
                shift 2
            else
                echo -e "${RED}Error: --namespace requires a namespace name${NC}"
                exit 1
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [KUBECONFIG_PATH]"
            echo ""
            echo "Policy Engine Options:"
            echo "  -e, --engine ENGINE  Policy engine to check (gatekeeper, kyverno, both)"
            echo "                       Default: both"
            echo ""
            echo "Output Options:"
            echo "  --summary            Show only violation summary (no details)"
            echo "  --export             Export full violations to violations-report.json"
            echo ""
            echo "Filter Options:"
            echo "  -n, --namespace NS   Filter violations for a specific namespace"
            echo ""
            echo "Other Options:"
            echo "  --help               Show this help message"
            echo ""
            echo "Kubeconfig shortcuts:"
            echo "  mgmt         Use management cluster kubeconfig"
            echo "  workload1    Use workload cluster 1 kubeconfig"
            echo "  workload2    Use workload cluster 2 kubeconfig"
            echo ""
            echo "Examples:"
            echo "  $0                                  # Check both engines, default kubeconfig"
            echo "  $0 -e gatekeeper mgmt              # Check Gatekeeper on mgmt cluster"
            echo "  $0 -e kyverno workload1            # Check Kyverno on workload1"
            echo "  $0 -e both --summary               # Summary for both engines"
            echo "  $0 -n kube-system -e kyverno mgmt  # Kyverno violations in kube-system"
            echo "  $0 --export -e both mgmt           # Export both engine violations"
            exit 0
            ;;
        mgmt)
            KUBECONFIG_FILE="$DEFAULT_MGMT_KUBECONFIG"
            shift
            ;;
        workload1)
            KUBECONFIG_FILE="$DEFAULT_WORKLOAD1_KUBECONFIG"
            shift
            ;;
        workload2)
            KUBECONFIG_FILE="$DEFAULT_WORKLOAD2_KUBECONFIG"
            shift
            ;;
        *)
            if [[ -f "$1" ]]; then
                KUBECONFIG_FILE="$1"
            else
                echo -e "${RED}Error: File not found: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set kubeconfig
if [[ -n "$KUBECONFIG_FILE" ]]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
    echo -e "${BLUE}Using kubeconfig: $KUBECONFIG_FILE${NC}"
elif [[ -f "$DEFAULT_MGMT_KUBECONFIG" ]]; then
    export KUBECONFIG="$DEFAULT_MGMT_KUBECONFIG"
    echo -e "${BLUE}Using default kubeconfig: $DEFAULT_MGMT_KUBECONFIG${NC}"
fi

# Check kubectl connectivity
echo -e "${BLUE}Checking cluster connectivity...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster. Check your kubeconfig.${NC}"
    exit 1
fi

CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
echo -e "${GREEN}Connected to cluster: $CLUSTER_NAME${NC}"
echo -e "${CYAN}Policy Engine: $POLICY_ENGINE${NC}"

if [[ -n "$NAMESPACE" ]]; then
    echo -e "${YELLOW}Filtering violations for namespace: $NAMESPACE${NC}"
fi
echo ""

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Function to print sub-header
print_subheader() {
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
}

# Function to print severity with color
print_severity() {
    case $1 in
        critical) echo -e "${RED}🔴 CRITICAL${NC}" ;;
        high)     echo -e "${YELLOW}🟠 HIGH${NC}" ;;
        medium)   echo -e "${BLUE}🟡 MEDIUM${NC}" ;;
        low)      echo -e "${GREEN}🟢 LOW${NC}" ;;
        *)        echo -e "⚪ $1" ;;
    esac
}

# Check if Gatekeeper is installed
check_gatekeeper_installed() {
    kubectl get crd constraints.templates.gatekeeper.sh &>/dev/null 2>&1 || \
    kubectl get constraints &>/dev/null 2>&1
}

# Check if Kyverno is installed
check_kyverno_installed() {
    kubectl get crd clusterpolicies.kyverno.io &>/dev/null 2>&1 || \
    kubectl get clusterpolicyreport &>/dev/null 2>&1
}

# Initialize totals
GATEKEEPER_TOTAL=0
KYVERNO_TOTAL=0

#######################################
# GATEKEEPER VIOLATIONS
#######################################
check_gatekeeper_violations() {
    if ! check_gatekeeper_installed; then
        echo -e "${YELLOW}⚠️  Gatekeeper not installed on this cluster${NC}"
        return
    fi

    if [[ -n "$NAMESPACE" ]]; then
        print_subheader "GATEKEEPER VIOLATIONS (namespace: $NAMESPACE)"
    else
        print_subheader "GATEKEEPER VIOLATIONS"
    fi

    echo ""
    echo "Constraint                              | Violations | Severity"
    echo "----------------------------------------|------------|----------"

    if [[ -n "$NAMESPACE" ]]; then
        # Filter by namespace
        kubectl get constraints -o json 2>/dev/null | jq -r --arg ns "$NAMESPACE" '
        .items[] |
        select(.status.violations != null) |
        {
          name: .metadata.name,
          severity: (.metadata.labels["policy-severity"] // "unknown"),
          count: ([.status.violations[] | select(.namespace == $ns)] | length)
        } |
        select(.count > 0) |
        [.name, (.count | tostring), .severity] | @tsv
        ' | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name count severity; do
            printf "%-40s| %-10s | " "$name" "$count"
            print_severity "$severity"
        done
    else
        kubectl get constraints -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.totalViolations != null) |
        [
          .metadata.name,
          (.status.totalViolations | tostring),
          (.metadata.labels["policy-severity"] // "unknown")
        ] | @tsv
        ' | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name count severity; do
            printf "%-40s| %-10s | " "$name" "$count"
            print_severity "$severity"
        done
    fi

    # Total violations
    if [[ -n "$NAMESPACE" ]]; then
        GATEKEEPER_TOTAL=$(kubectl get constraints -o json 2>/dev/null | jq --arg ns "$NAMESPACE" '[.items[].status.violations[]? | select(.namespace == $ns)] | length')
    else
        GATEKEEPER_TOTAL=$(kubectl get constraints -o json 2>/dev/null | jq '[.items[].status.totalViolations // 0] | add')
    fi
    echo ""
    echo -e "----------------------------------------|------------|----------"
    echo -e "${YELLOW}GATEKEEPER TOTAL: ${GATEKEEPER_TOTAL:-0}${NC}"
}

#######################################
# KYVERNO VIOLATIONS
#######################################
check_kyverno_violations() {
    if ! check_kyverno_installed; then
        echo -e "${YELLOW}⚠️  Kyverno not installed on this cluster${NC}"
        return
    fi

    if [[ -n "$NAMESPACE" ]]; then
        print_subheader "KYVERNO VIOLATIONS (namespace: $NAMESPACE)"
    else
        print_subheader "KYVERNO VIOLATIONS"
    fi

    echo ""
    echo "Policy                                  | Violations | Severity"
    echo "----------------------------------------|------------|----------"

    if [[ -n "$NAMESPACE" ]]; then
        # Get namespace-scoped PolicyReport
        kubectl get policyreport -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
        .items[] |
        .results[]? |
        select(.result == "fail") |
        {
          policy: .policy,
          severity: (.severity // "unknown"),
          count: 1
        }
        ' | jq -s 'group_by(.policy) | map({
          policy: .[0].policy,
          severity: .[0].severity,
          count: length
        }) | sort_by(.count) | reverse | .[] | [.policy, (.count | tostring), .severity] | @tsv
        ' 2>/dev/null | while IFS=$'\t' read -r name count severity; do
            printf "%-40s| %-10s | " "$name" "$count"
            print_severity "$severity"
        done

        # Count total for namespace
        KYVERNO_TOTAL=$(kubectl get policyreport -n "$NAMESPACE" -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | length' 2>/dev/null || echo "0")
    else
        # Get cluster-wide PolicyReport (ClusterPolicyReport) and namespace PolicyReports
        {
            # ClusterPolicyReport violations
            kubectl get clusterpolicyreport -o json 2>/dev/null | jq -r '
            .items[] |
            .results[]? |
            select(.result == "fail") |
            {
              policy: .policy,
              severity: (.severity // "unknown")
            }
            ' 2>/dev/null

            # All namespace PolicyReport violations
            kubectl get policyreport -A -o json 2>/dev/null | jq -r '
            .items[] |
            .results[]? |
            select(.result == "fail") |
            {
              policy: .policy,
              severity: (.severity // "unknown")
            }
            ' 2>/dev/null
        } | jq -s 'group_by(.policy) | map({
          policy: .[0].policy,
          severity: .[0].severity,
          count: length
        }) | sort_by(.count) | reverse | .[] | [.policy, (.count | tostring), .severity] | @tsv
        ' 2>/dev/null | while IFS=$'\t' read -r name count severity; do
            printf "%-40s| %-10s | " "$name" "$count"
            print_severity "$severity"
        done

        # Count total
        CLUSTER_VIOLATIONS=$(kubectl get clusterpolicyreport -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | length' 2>/dev/null || echo "0")
        NS_VIOLATIONS=$(kubectl get policyreport -A -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | length' 2>/dev/null || echo "0")
        KYVERNO_TOTAL=$((${CLUSTER_VIOLATIONS:-0} + ${NS_VIOLATIONS:-0}))
    fi

    echo ""
    echo -e "----------------------------------------|------------|----------"
    echo -e "${MAGENTA}KYVERNO TOTAL: ${KYVERNO_TOTAL:-0}${NC}"
}

#######################################
# KYVERNO VIOLATIONS BY NAMESPACE
#######################################
check_kyverno_by_namespace() {
    if ! check_kyverno_installed; then
        return
    fi

    if [[ -n "$NAMESPACE" ]]; then
        # Skip when filtering by namespace
        return
    fi

    print_subheader "KYVERNO VIOLATIONS BY NAMESPACE"

    kubectl get policyreport -A -o json 2>/dev/null | jq -r '
    [.items[] | {
      namespace: .metadata.namespace,
      violations: ([.results[]? | select(.result == "fail")] | length)
    }] |
    sort_by(.violations) | reverse | .[:15][] |
    select(.violations > 0) |
    "\(.violations)\t\(.namespace)"
    ' 2>/dev/null | while IFS=$'\t' read -r count ns; do
        printf "  %-30s %s violations\n" "$ns" "$count"
    done
}

#######################################
# GATEKEEPER VIOLATIONS BY NAMESPACE
#######################################
check_gatekeeper_by_namespace() {
    if ! check_gatekeeper_installed; then
        return
    fi

    if [[ -n "$NAMESPACE" ]]; then
        # Skip when filtering by namespace
        return
    fi

    print_subheader "GATEKEEPER VIOLATIONS BY NAMESPACE"

    kubectl get constraints -o json 2>/dev/null | jq -r '
    [.items[] | .status.violations[]? | .namespace // "cluster-scoped"] |
    group_by(.) |
    map({namespace: .[0], count: length}) |
    sort_by(.count) | reverse | .[:15][] |
    "\(.count)\t\(.namespace)"
    ' | while IFS=$'\t' read -r count ns; do
        printf "  %-30s %s violations\n" "$ns" "$count"
    done
}

#######################################
# KYVERNO VIOLATIONS BY CATEGORY
#######################################
check_kyverno_by_category() {
    if ! check_kyverno_installed; then
        return
    fi

    print_subheader "KYVERNO VIOLATIONS BY CATEGORY"

    if [[ -n "$NAMESPACE" ]]; then
        kubectl get policyreport -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
        [.items[].results[]? | select(.result == "fail") | .category // "unknown"] |
        group_by(.) |
        map({category: .[0], count: length}) |
        sort_by(.count) | reverse | .[] |
        "\(.count)\t\(.category)"
        ' 2>/dev/null | while IFS=$'\t' read -r count category; do
            printf "  %-25s %s violations\n" "$category" "$count"
        done
    else
        {
            kubectl get clusterpolicyreport -o json 2>/dev/null | jq -r '.items[].results[]? | select(.result == "fail") | .category // "unknown"' 2>/dev/null
            kubectl get policyreport -A -o json 2>/dev/null | jq -r '.items[].results[]? | select(.result == "fail") | .category // "unknown"' 2>/dev/null
        } | sort | uniq -c | sort -rn | head -15 | while read -r count category; do
            printf "  %-25s %s violations\n" "$category" "$count"
        done
    fi
}

#######################################
# GATEKEEPER VIOLATIONS BY CATEGORY
#######################################
check_gatekeeper_by_category() {
    if ! check_gatekeeper_installed; then
        return
    fi

    print_subheader "GATEKEEPER VIOLATIONS BY CATEGORY"

    if [[ -n "$NAMESPACE" ]]; then
        kubectl get constraints -o json 2>/dev/null | jq -r --arg ns "$NAMESPACE" '
        [.items[] | {
          category: (.metadata.labels["policy-category"] // "unknown"),
          violations: ([.status.violations[]? | select(.namespace == $ns)] | length)
        }] |
        group_by(.category) |
        map({category: .[0].category, total: (map(.violations) | add)}) |
        sort_by(.total) | reverse | .[] |
        select(.total > 0) |
        "\(.total)\t\(.category)"
        ' | while IFS=$'\t' read -r count category; do
            printf "  %-25s %s violations\n" "$category" "$count"
        done
    else
        kubectl get constraints -o json 2>/dev/null | jq -r '
        [.items[] | {category: (.metadata.labels["policy-category"] // "unknown"), violations: (.status.totalViolations // 0)}] |
        group_by(.category) |
        map({category: .[0].category, total: (map(.violations) | add)}) |
        sort_by(.total) | reverse | .[] |
        "\(.total)\t\(.category)"
        ' | while IFS=$'\t' read -r count category; do
            printf "  %-25s %s violations\n" "$category" "$count"
        done
    fi
}

#######################################
# DETAILED KYVERNO VIOLATIONS
#######################################
check_kyverno_details() {
    if ! check_kyverno_installed; then
        return
    fi

    print_subheader "DETAILED KYVERNO VIOLATIONS"

    if [[ -n "$NAMESPACE" ]]; then
        kubectl get policyreport -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
        .items[] |
        .results[]? |
        select(.result == "fail") |
        "\u001b[1;35m▶ \(.policy)\u001b[0m",
        "  - \(.resources[0].namespace // "cluster")/\(.resources[0].kind)/\(.resources[0].name)",
        "    → \(.message)",
        ""
        ' 2>/dev/null | head -50
    else
        {
            kubectl get clusterpolicyreport -o json 2>/dev/null | jq -r '
            .items[] |
            .results[]? |
            select(.result == "fail") |
            "\u001b[1;35m▶ \(.policy)\u001b[0m",
            "  - \(.resources[0].namespace // "cluster")/\(.resources[0].kind)/\(.resources[0].name)",
            "    → \(.message)",
            ""
            ' 2>/dev/null

            kubectl get policyreport -A -o json 2>/dev/null | jq -r '
            .items[] |
            .results[]? |
            select(.result == "fail") |
            "\u001b[1;35m▶ \(.policy)\u001b[0m",
            "  - \(.resources[0].namespace // "cluster")/\(.resources[0].kind)/\(.resources[0].name)",
            "    → \(.message)",
            ""
            ' 2>/dev/null
        } | head -100
    fi
}

#######################################
# DETAILED GATEKEEPER VIOLATIONS
#######################################
check_gatekeeper_details() {
    if ! check_gatekeeper_installed; then
        return
    fi

    print_subheader "DETAILED GATEKEEPER VIOLATIONS"

    if [[ -n "$NAMESPACE" ]]; then
        kubectl get constraints -o json 2>/dev/null | jq -r --arg ns "$NAMESPACE" '
        .items[] |
        select([.status.violations[]? | select(.namespace == $ns)] | length > 0) |
        {
          name: .metadata.name,
          violations: [.status.violations[]? | select(.namespace == $ns)],
          total: ([.status.violations[]? | select(.namespace == $ns)] | length)
        } |
        "\u001b[1;33m▶ \(.name)\u001b[0m",
        (.violations[:10][] | "  - \(.namespace // "cluster")/\(.kind)/\(.name)\n    → \(.message)"),
        (if .total > 10 then "  \u001b[0;34m... and \(.total - 10) more violations in \($ns)\u001b[0m" else empty end),
        ""
        '
    else
        kubectl get constraints -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.totalViolations > 0) |
        {
          name: .metadata.name,
          violations: .status.violations,
          total: .status.totalViolations
        } |
        "\u001b[1;33m▶ \(.name)\u001b[0m",
        (.violations[:10][] | "  - \(.namespace // "cluster")/\(.kind)/\(.name)\n    → \(.message)"),
        (if .total > 10 then "  \u001b[0;34m... and \(.total - 10) more violations\u001b[0m" else empty end),
        ""
        '
    fi
}

#######################################
# MAIN SUMMARY
#######################################
print_header "POLICY VIOLATIONS SUMMARY"

# Check based on selected engine
if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
    check_gatekeeper_violations
fi

if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
    check_kyverno_violations
fi

#######################################
# BY NAMESPACE
#######################################
if [[ -z "$NAMESPACE" ]]; then
    print_header "VIOLATIONS BY NAMESPACE"

    if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
        check_gatekeeper_by_namespace
    fi

    if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
        check_kyverno_by_namespace
    fi
fi

#######################################
# BY CATEGORY
#######################################
print_header "VIOLATIONS BY CATEGORY"

if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
    check_gatekeeper_by_category
fi

if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
    check_kyverno_by_category
fi

#######################################
# DETAILED VIEW (unless --summary)
#######################################
if [[ "$SUMMARY_ONLY" != true ]]; then
    print_header "DETAILED VIOLATIONS"

    if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
        check_gatekeeper_details
    fi

    if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
        check_kyverno_details
    fi
fi

#######################################
# EXPORT TO JSON
#######################################
if [[ "$EXPORT_JSON" == true ]]; then
    if [[ -n "$NAMESPACE" ]]; then
        EXPORT_FILE="violations-report-${POLICY_ENGINE}-${NAMESPACE}-$(date +%Y%m%d-%H%M%S).json"
    else
        EXPORT_FILE="violations-report-${POLICY_ENGINE}-$(date +%Y%m%d-%H%M%S).json"
    fi
    print_header "EXPORTING TO $EXPORT_FILE"

    # Create combined JSON report
    {
        echo "{"
        echo "  \"generated\": \"$(date +%Y-%m-%dT%H:%M:%S)\","
        echo "  \"cluster\": \"$CLUSTER_NAME\","
        echo "  \"policy_engine\": \"$POLICY_ENGINE\","
        if [[ -n "$NAMESPACE" ]]; then
            echo "  \"namespace_filter\": \"$NAMESPACE\","
        fi

        # Gatekeeper section
        if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
            if check_gatekeeper_installed; then
                echo "  \"gatekeeper\": {"
                if [[ -n "$NAMESPACE" ]]; then
                    kubectl get constraints -o json 2>/dev/null | jq --arg ns "$NAMESPACE" '
                    {
                        total_violations: [.items[].status.violations[]? | select(.namespace == $ns)] | length,
                        by_constraint: [.items[] |
                          {
                            name: .metadata.name,
                            category: .metadata.labels["policy-category"],
                            severity: .metadata.labels["policy-severity"],
                            violations: ([.status.violations[]? | select(.namespace == $ns)] | length),
                            details: [.status.violations[]? | select(.namespace == $ns)]
                          } | select(.violations > 0)
                        ] | sort_by(.violations) | reverse
                    }
                    ' | sed 's/^/    /' | tail -n +2 | head -n -1
                else
                    kubectl get constraints -o json 2>/dev/null | jq '
                    {
                        total_violations: [.items[].status.totalViolations // 0] | add,
                        by_constraint: [.items[] | select(.status.totalViolations > 0) | {
                            name: .metadata.name,
                            category: .metadata.labels["policy-category"],
                            severity: .metadata.labels["policy-severity"],
                            violations: .status.totalViolations,
                            details: .status.violations
                        }] | sort_by(.violations) | reverse,
                        by_namespace: ([.items[] | .status.violations[]? | .namespace // "cluster-scoped"] | group_by(.) | map({namespace: .[0], count: length}) | sort_by(.count) | reverse)
                    }
                    ' | sed 's/^/    /' | tail -n +2 | head -n -1
                fi
                if [[ "$POLICY_ENGINE" == "both" ]]; then
                    echo "  },"
                else
                    echo "  }"
                fi
            fi
        fi

        # Kyverno section
        if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
            if check_kyverno_installed; then
                echo "  \"kyverno\": {"
                if [[ -n "$NAMESPACE" ]]; then
                    kubectl get policyreport -n "$NAMESPACE" -o json 2>/dev/null | jq '
                    {
                        total_violations: [.items[].results[]? | select(.result == "fail")] | length,
                        by_policy: [.items[].results[]? | select(.result == "fail")] | group_by(.policy) | map({
                            policy: .[0].policy,
                            category: .[0].category,
                            severity: .[0].severity,
                            violations: length,
                            details: .
                        }) | sort_by(.violations) | reverse
                    }
                    ' 2>/dev/null | sed 's/^/    /' | tail -n +2 | head -n -1
                else
                    {
                        echo "{"
                        echo "  \"cluster_violations\": $(kubectl get clusterpolicyreport -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | length' 2>/dev/null || echo "0"),"
                        echo "  \"namespace_violations\": $(kubectl get policyreport -A -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | length' 2>/dev/null || echo "0"),"
                        echo "  \"by_namespace\": $(kubectl get policyreport -A -o json 2>/dev/null | jq '[.items[] | {namespace: .metadata.namespace, violations: ([.results[]? | select(.result == "fail")] | length)}] | sort_by(.violations) | reverse' 2>/dev/null || echo "[]"),"
                        echo "  \"by_policy\": $(kubectl get policyreport -A -o json 2>/dev/null | jq '[.items[].results[]? | select(.result == "fail")] | group_by(.policy) | map({policy: .[0].policy, category: .[0].category, severity: .[0].severity, violations: length}) | sort_by(.violations) | reverse' 2>/dev/null || echo "[]")"
                        echo "}"
                    } | jq '.' | sed 's/^/    /' | tail -n +2 | head -n -1
                fi
                echo "  }"
            fi
        fi

        echo "}"
    } | jq '.' > "$EXPORT_FILE" 2>/dev/null || echo "{\"error\": \"Failed to generate report\"}" > "$EXPORT_FILE"

    echo -e "${GREEN}Exported to: $EXPORT_FILE${NC}"
fi

#######################################
# QUICK ACTIONS
#######################################
print_header "QUICK ACTIONS"

echo ""
echo -e "${CYAN}=== General ===${NC}"
echo "To see violations for a specific namespace:"
echo -e "  ${GREEN}./scripts/check-violations.sh -n <namespace> -e both mgmt${NC}"
echo ""
echo "To check only one policy engine:"
echo -e "  ${GREEN}./scripts/check-violations.sh -e gatekeeper mgmt${NC}"
echo -e "  ${GREEN}./scripts/check-violations.sh -e kyverno mgmt${NC}"
echo ""

if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
    echo -e "${YELLOW}=== Gatekeeper Commands ===${NC}"
    echo "To see all violations for a specific constraint:"
    echo -e "  ${GREEN}kubectl get constraints <constraint-name> -o yaml | grep -A 100 violations${NC}"
    echo ""
    echo "To trigger a full Gatekeeper audit:"
    echo -e "  ${GREEN}kubectl annotate constraint --all gatekeeper.sh/audit-timestamp=\$(date +%s) --overwrite${NC}"
    echo ""
    echo "To see constraint templates:"
    echo -e "  ${GREEN}kubectl get constrainttemplates${NC}"
    echo ""
fi

if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
    echo -e "${MAGENTA}=== Kyverno Commands ===${NC}"
    echo "To see policy reports:"
    echo -e "  ${GREEN}kubectl get policyreport -A${NC}"
    echo -e "  ${GREEN}kubectl get clusterpolicyreport${NC}"
    echo ""
    echo "To see violations for a specific policy:"
    echo -e "  ${GREEN}kubectl get policyreport -A -o json | jq '.items[].results[]? | select(.policy==\"<policy-name>\" and .result==\"fail\")'${NC}"
    echo ""
    echo "To see all Kyverno policies:"
    echo -e "  ${GREEN}kubectl get clusterpolicy${NC}"
    echo -e "  ${GREEN}kubectl get policy -A${NC}"
    echo ""
    echo "To see policy report summary:"
    echo -e "  ${GREEN}kubectl get policyreport -A -o custom-columns='NAMESPACE:.metadata.namespace,PASS:.summary.pass,FAIL:.summary.fail,WARN:.summary.warn,ERROR:.summary.error,SKIP:.summary.skip'${NC}"
    echo ""
fi

#######################################
# EXIT STATUS
#######################################
TOTAL_VIOLATIONS=$((${GATEKEEPER_TOTAL:-0} + ${KYVERNO_TOTAL:-0}))

print_header "SUMMARY"
echo ""
if [[ "$POLICY_ENGINE" == "gatekeeper" || "$POLICY_ENGINE" == "both" ]]; then
    echo -e "  Gatekeeper violations: ${YELLOW}${GATEKEEPER_TOTAL:-0}${NC}"
fi
if [[ "$POLICY_ENGINE" == "kyverno" || "$POLICY_ENGINE" == "both" ]]; then
    echo -e "  Kyverno violations:    ${MAGENTA}${KYVERNO_TOTAL:-0}${NC}"
fi
echo -e "  ─────────────────────────────"
echo -e "  Total violations:      ${RED}${TOTAL_VIOLATIONS}${NC}"
echo ""

if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found $TOTAL_VIOLATIONS total violations${NC}"
    exit 0  # Still exit 0 since audit/warn mode doesn't block
else
    echo -e "${GREEN}✅ No violations found${NC}"
    exit 0
fi
