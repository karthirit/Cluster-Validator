#!/usr/bin/env bash

# Comprehensive Kubernetes Cluster Validation Script
# Validates namespaces, helm releases, deployments, pods, ingress URLs, and provides consolidated report

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
NAMESPACE=""
CONTEXT=""
TIMEOUT=10
VERBOSE=false
CLUSTER_NAME=""

# Global arrays to store validation results
declare -a NAMESPACE_ISSUES
declare -a HELM_ISSUES  
declare -a DEPLOYMENT_ISSUES
declare -a POD_ISSUES
declare -a INGRESS_ISSUES
declare -a KUSTOMIZATION_ISSUES

# Global counters
TOTAL_NAMESPACES=0
ACTIVE_NAMESPACES=0
TOTAL_HELM=0
DEPLOYED_HELM=0
TOTAL_DEPLOYMENTS=0
READY_DEPLOYMENTS=0
TOTAL_PODS=0
RUNNING_PODS=0
FAILED_PODS=0
PENDING_PODS=0
TOTAL_INGRESS=0
HEALTHY_INGRESS=0
TOTAL_KUSTOMIZATIONS=0
READY_KUSTOMIZATIONS=0
TOTAL_NODES=0
READY_NODES=0
ISTIO_VERSION="unknown"
CLUSTER_VERSION="unknown"

print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
        "HEADER") echo -e "\n${PURPLE}🔍 $message${NC}" ;;
        "SECTION") echo -e "\n${CYAN}📋 $message${NC}" ;;
    esac
}


# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace NAMESPACE    Check specific namespace (default: all)"
    echo "  -c, --context CONTEXT        Use specific kubectl context"
    echo "  -t, --timeout SECONDS        HTTP timeout in seconds (default: 10)"
    echo "  -v, --verbose               Verbose output"
    echo "  -h, --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Check all namespaces"
    echo "  $0 -n production                      # Check production namespace"
    echo "  $0 -c my-cluster -t 15               # Use specific context with 15s timeout"
    echo "  $0 -n default -v                     # Check with verbose output"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Get cluster info
get_cluster_info() {
    # Get cluster name
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
    print_status "INFO" "Cluster: $CLUSTER_NAME"
    
    # Get cluster version
    CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || echo "unknown")
    if [[ "$CLUSTER_VERSION" == "unknown" || -z "$CLUSTER_VERSION" ]]; then
        # Try alternative method
        CLUSTER_VERSION=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null | sed 's/v//' || echo "unknown")
    fi
    if [[ "$CLUSTER_VERSION" == "unknown" || -z "$CLUSTER_VERSION" ]]; then
        # Try kubectl get nodes method
        CLUSTER_VERSION=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || echo "unknown")
    fi
    print_status "INFO" "Cluster version: $CLUSTER_VERSION"
}

# Build kubectl command
build_kubectl_cmd() {
    KUBECTL_CMD="kubectl"
    if [[ -n "$CONTEXT" ]]; then
        KUBECTL_CMD="$KUBECTL_CMD --context=$CONTEXT"
    fi
    if [[ -n "$NAMESPACE" ]]; then
        KUBECTL_CMD="$KUBECTL_CMD --namespace=$NAMESPACE"
    fi
}

# Check namespaces
check_namespaces() {
    print_status "SECTION" "Checking Namespaces"
    
    local namespaces
    if [[ -n "$NAMESPACE" ]]; then
        namespaces="$NAMESPACE"
    else
        namespaces=$($KUBECTL_CMD get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    fi
    
    if [[ -z "$namespaces" ]]; then
        print_status "ERROR" "No namespaces found or unable to list namespaces"
        return 1
    fi
    
    TOTAL_NAMESPACES=0
    ACTIVE_NAMESPACES=0
    
    for ns in $namespaces; do
        TOTAL_NAMESPACES=$((TOTAL_NAMESPACES + 1))
        local status=$($KUBECTL_CMD get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        if [[ "$status" == "Active" ]]; then
            ACTIVE_NAMESPACES=$((ACTIVE_NAMESPACES + 1))
            print_status "SUCCESS" "Namespace $ns: $status"
        else
            NAMESPACE_ISSUES+=("$ns: $status")
            print_status "WARNING" "Namespace $ns: $status"
        fi
    done
    
    echo ""
    print_status "INFO" "Total namespaces: $TOTAL_NAMESPACES, Active: $ACTIVE_NAMESPACES"
}

# Check Helm releases
check_helm_releases() {
    print_status "SECTION" "Checking Helm Releases"
    
    TOTAL_HELM=0
    DEPLOYED_HELM=0
    
    # Get all helm releases across all namespaces at once (much faster)
    local all_releases=$(helm list --all-namespaces --output json 2>/dev/null | jq -r '.[] | "\(.namespace)|\(.name)|\(.status)"' 2>/dev/null || echo "")
    
    if [[ -n "$all_releases" ]]; then
        while IFS='|' read -r ns name status; do
            # Skip if specific namespace is requested and this isn't it
            if [[ -n "$NAMESPACE" && "$ns" != "$NAMESPACE" ]]; then
                continue
            fi
            
            TOTAL_HELM=$((TOTAL_HELM + 1))
            
            case "$status" in
                "deployed")
                    DEPLOYED_HELM=$((DEPLOYED_HELM + 1))
                    print_status "SUCCESS" "Helm release $name in $ns: $status"
                    ;;
                "failed"|"pending-upgrade"|"pending-install")
                    HELM_ISSUES+=("$ns/$name: $status")
                    print_status "ERROR" "Helm release $name in $ns: $status"
                    ;;
                *)
                    HELM_ISSUES+=("$ns/$name: $status")
                    print_status "WARNING" "Helm release $name in $ns: $status"
                    ;;
            esac
        done <<< "$all_releases"
    fi
    
    echo ""
    print_status "INFO" "Total Helm releases: $TOTAL_HELM, Deployed: $DEPLOYED_HELM, Failed: ${#HELM_ISSUES[@]}"
}

# Check deployments
check_deployments() {
    print_status "SECTION" "Checking Deployments"
    
    local namespaces
    if [[ -n "$NAMESPACE" ]]; then
        namespaces="$NAMESPACE"
    else
        namespaces=$($KUBECTL_CMD get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    fi
    
    TOTAL_DEPLOYMENTS=0
    READY_DEPLOYMENTS=0
    
    for ns in $namespaces; do
        # Check if namespace is active
        local ns_status=$($KUBECTL_CMD get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$ns_status" == "Active" ]]; then
            local deployments=$($KUBECTL_CMD get deployments -n "$ns" --no-headers 2>/dev/null || echo "")
            
            if [[ -n "$deployments" ]]; then
                while read -r line; do
                    if [[ -n "$line" ]]; then
                        local name=$(echo "$line" | awk '{print $1}')
                        local ready=$(echo "$line" | awk '{print $2}')
                        local up_to_date=$(echo "$line" | awk '{print $3}')
                        local available=$(echo "$line" | awk '{print $4}')
                        
                        TOTAL_DEPLOYMENTS=$((TOTAL_DEPLOYMENTS + 1))
                        
                        # Parse ready format (e.g., "2/2" means 2 ready out of 2 desired)
                        local ready_count=$(echo "$ready" | cut -d'/' -f1)
                        local ready_desired=$(echo "$ready" | cut -d'/' -f2)
                        
                        # Check if all pods are ready (ready_count == ready_desired) and available count matches
                        if [[ "$ready_count" == "$ready_desired" && "$ready_desired" != "0" && "$available" == "$ready_desired" ]]; then
                            READY_DEPLOYMENTS=$((READY_DEPLOYMENTS + 1))
                            print_status "SUCCESS" "Deployment $name in $ns: Ready ($ready)"
                        else
                            DEPLOYMENT_ISSUES+=("$ns/$name: Not Ready ($ready/$available)")
                            print_status "ERROR" "Deployment $name in $ns: Not Ready ($ready/$available)"
                        fi
                    fi
                done <<< "$deployments"
            fi
        fi
    done
    
    echo ""
    print_status "INFO" "Total deployments: $TOTAL_DEPLOYMENTS, Ready: $READY_DEPLOYMENTS, Not Ready: ${#DEPLOYMENT_ISSUES[@]}"
}

# Check pods
check_pods() {
    print_status "SECTION" "Checking Pods"
    
    local namespaces
    if [[ -n "$NAMESPACE" ]]; then
        namespaces="$NAMESPACE"
    else
        namespaces=$($KUBECTL_CMD get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    fi
    
    TOTAL_PODS=0
    RUNNING_PODS=0
    FAILED_PODS=0
    PENDING_PODS=0
    
    for ns in $namespaces; do
        # Check if namespace is active
        local ns_status=$($KUBECTL_CMD get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$ns_status" == "Active" ]]; then
            local pods=$($KUBECTL_CMD get pods -n "$ns" --no-headers 2>/dev/null || echo "")
            
            if [[ -n "$pods" ]]; then
                while read -r line; do
                    if [[ -n "$line" ]]; then
                        local name=$(echo "$line" | awk '{print $1}')
                        local status=$(echo "$line" | awk '{print $3}')
                        local ready=$(echo "$line" | awk '{print $2}')
                        local restarts=$(echo "$line" | awk '{print $4}')
                        
                        TOTAL_PODS=$((TOTAL_PODS + 1))
                        
                        case "$status" in
                            "Running")
                                if [[ "$ready" == *"/"* && "$ready" != "0/0" ]]; then
                                    local ready_count=$(echo "$ready" | cut -d'/' -f1)
                                    local total_count=$(echo "$ready" | cut -d'/' -f2)
                                    if [[ "$ready_count" == "$total_count" ]]; then
                                        RUNNING_PODS=$((RUNNING_PODS + 1))
                                        print_status "SUCCESS" "Pod $name in $ns: $status ($ready)"
                                    else
                                        FAILED_PODS=$((FAILED_PODS + 1))
                                        POD_ISSUES+=("$ns/$name: Not all containers ready ($ready)")
                                        print_status "WARNING" "Pod $name in $ns: $status ($ready) - Not all containers ready"
                                    fi
                                else
                                    RUNNING_PODS=$((RUNNING_PODS + 1))
                                    print_status "SUCCESS" "Pod $name in $ns: $status ($ready)"
                                fi
                                ;;
                            "Pending")
                                PENDING_PODS=$((PENDING_PODS + 1))
                                POD_ISSUES+=("$ns/$name: Pending")
                                print_status "WARNING" "Pod $name in $ns: $status"
                                ;;
                            "Completed")
                                # Count completed pods as running (successful jobs)
                                RUNNING_PODS=$((RUNNING_PODS + 1))
                                print_status "SUCCESS" "Pod $name in $ns: $status (Job completed successfully)"
                                ;;
                            "Failed"|"CrashLoopBackOff"|"ImagePullBackOff"|"ErrImagePull")
                                FAILED_PODS=$((FAILED_PODS + 1))
                                POD_ISSUES+=("$ns/$name: $status (Restarts: $restarts)")
                                print_status "ERROR" "Pod $name in $ns: $status (Restarts: $restarts)"
                                ;;
                            Init:*)
                                # Handle Init container states
                                FAILED_PODS=$((FAILED_PODS + 1))
                                POD_ISSUES+=("$ns/$name: $status (Init containers not ready)")
                                print_status "WARNING" "Pod $name in $ns: $status"
                                ;;
                            *)
                                # Handle any other status (like ContainerCreating, Terminating, etc.)
                                if [[ "$status" == *"Error"* || "$status" == *"Evicted"* ]]; then
                                    FAILED_PODS=$((FAILED_PODS + 1))
                                    POD_ISSUES+=("$ns/$name: $status")
                                    print_status "ERROR" "Pod $name in $ns: $status"
                                else
                                    PENDING_PODS=$((PENDING_PODS + 1))
                                    POD_ISSUES+=("$ns/$name: $status")
                                    print_status "WARNING" "Pod $name in $ns: $status"
                                fi
                                ;;
                        esac
                    fi
                done <<< "$pods"
            fi
        fi
    done
    
    echo ""
    print_status "INFO" "Total pods: $TOTAL_PODS, Running: $RUNNING_PODS, Failed: $FAILED_PODS, Pending: $PENDING_PODS"
    if [[ ${#POD_ISSUES[@]} -gt 0 ]]; then
        print_status "WARNING" "Pod issues found: ${#POD_ISSUES[@]} pods have problems"
    fi
}


# Check Flux Kustomizations
check_flux_kustomizations() {
    print_status "SECTION" "Checking Flux Kustomizations"
    
    local kustomizations=$($KUBECTL_CMD get kustomizations -A --no-headers 2>/dev/null || echo "")
    TOTAL_KUSTOMIZATIONS=0
    READY_KUSTOMIZATIONS=0
    
    if [[ -n "$kustomizations" ]]; then
        while read -r line; do
            if [[ -n "$line" ]]; then
                local namespace=$(echo "$line" | awk '{print $1}')
                local name=$(echo "$line" | awk '{print $2}')
                local ready=$(echo "$line" | awk '{print $3}')
                local status=$(echo "$line" | awk '{print $4}')
                local age=$(echo "$line" | awk '{print $5}')
                
                TOTAL_KUSTOMIZATIONS=$((TOTAL_KUSTOMIZATIONS + 1))
                
                if [[ "$ready" == "True" ]]; then
                    READY_KUSTOMIZATIONS=$((READY_KUSTOMIZATIONS + 1))
                    print_status "SUCCESS" "Kustomization $name in $namespace: $ready ($status)"
                else
                    KUSTOMIZATION_ISSUES+=("$namespace/$name: $ready ($status)")
                    print_status "ERROR" "Kustomization $name in $namespace: $ready ($status)"
                fi
            fi
        done <<< "$kustomizations"
    fi
    
    echo ""
    print_status "INFO" "Total Kustomizations: $TOTAL_KUSTOMIZATIONS, Ready: $READY_KUSTOMIZATIONS, Failed: ${#KUSTOMIZATION_ISSUES[@]}"
}

# Check nodes
check_nodes() {
    print_status "SECTION" "Checking Nodes"
    
    local nodes=$($KUBECTL_CMD get nodes --no-headers 2>/dev/null || echo "")
    TOTAL_NODES=0
    READY_NODES=0
    
    if [[ -n "$nodes" ]]; then
        while read -r line; do
            if [[ -n "$line" ]]; then
                local name=$(echo "$line" | awk '{print $1}')
                local status=$(echo "$line" | awk '{print $2}')
                local roles=$(echo "$line" | awk '{print $3}')
                local age=$(echo "$line" | awk '{print $4}')
                local version=$(echo "$line" | awk '{print $5}')
                
                TOTAL_NODES=$((TOTAL_NODES + 1))
                
                if [[ "$status" == "Ready" ]]; then
                    READY_NODES=$((READY_NODES + 1))
                    print_status "SUCCESS" "Node $name: $status ($roles)"
                else
                    POD_ISSUES+=("Node $name: $status")
                    print_status "ERROR" "Node $name: $status"
                fi
            fi
        done <<< "$nodes"
    fi
    
    echo ""
    print_status "INFO" "Total nodes: $TOTAL_NODES, Ready: $READY_NODES, Not Ready: $((TOTAL_NODES - READY_NODES))"
}

# Check Istio version
check_istio_version() {
    print_status "SECTION" "Checking Istio Version"
    
    # Check if Istio is installed
    local istio_namespace="istio-system"
    if $KUBECTL_CMD get namespace "$istio_namespace" &> /dev/null; then
        # Try to get Istio version from pilot pod
        ISTIO_VERSION=$($KUBECTL_CMD get pods -n "$istio_namespace" -l app=istiod --no-headers 2>/dev/null | head -1 | awk '{print $1}' | xargs -I {} $KUBECTL_CMD exec -n "$istio_namespace" {} -- pilot-discovery version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 || echo "unknown")
        
        if [[ "$ISTIO_VERSION" != "unknown" ]]; then
            print_status "SUCCESS" "Istio version: $ISTIO_VERSION"
        else
            # Fallback: check from istio-proxy sidecar
            ISTIO_VERSION=$($KUBECTL_CMD get pods -n "$istio_namespace" -l app=istiod --no-headers 2>/dev/null | head -1 | awk '{print $1}' | xargs -I {} $KUBECTL_CMD exec -n "$istio_namespace" {} -- pilot-discovery version 2>/dev/null | grep -o 'version [0-9]\+\.[0-9]\+\.[0-9]\+' | cut -d' ' -f2 || echo "unknown")
            
            if [[ "$ISTIO_VERSION" != "unknown" ]]; then
                print_status "SUCCESS" "Istio version: $ISTIO_VERSION"
            else
                ISTIO_VERSION="unknown"
                print_status "WARNING" "Could not determine Istio version"
            fi
        fi
        
        # Check Istio components status
        local istio_pods=$($KUBECTL_CMD get pods -n "$istio_namespace" --no-headers 2>/dev/null | wc -l)
        local istio_running=$($KUBECTL_CMD get pods -n "$istio_namespace" --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        print_status "INFO" "Istio pods: $istio_running/$istio_pods running"
    else
        ISTIO_VERSION="Not installed"
        print_status "WARNING" "Istio namespace not found - Istio may not be installed"
    fi
    echo ""
}


# Check ingress URLs (integrated from the provided script)
check_ingress_urls() {
    print_status "SECTION" "Checking Ingress URLs"
    
    # Get all ingress resources
    local ingress_json=$($KUBECTL_CMD get ingress -A -o json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        print_status "ERROR" "Failed to get ingress resources. Check your permissions and cluster access."
        return 1
    fi
    
    # Extract URLs from ingress resources
    local urls=$(echo "$ingress_json" | jq -r '
    .items[] | 
    .metadata.namespace as $ns |
    .metadata.name as $name |
    .spec.rules[]? | 
    .host as $host |
    if $host then
      (.http.paths[]? | 
        if .path then
          "\($ns)|\($name)|\($host)|\(.path)"
        else
          "\($ns)|\($name)|\($host)|/"
        end
      ) // "\($ns)|\($name)|\($host)|/"
    else
      empty
    end
    ')
    
    if [[ -z "$urls" ]]; then
        print_status "WARNING" "No ingress resources found or no URLs extracted."
        return 0
    fi
    
    # Count total URLs
    local total_urls=$(echo "$urls" | wc -l)
    print_status "INFO" "Found $total_urls URLs to test"
    
    # Initialize counters
    local healthy_count=0
    local dns_failed=0
    local http_failed=0
    local current=0
    
    # Test each URL
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        
        current=$((current + 1))
        IFS='|' read -r namespace name host path <<< "$line"
        
        # Determine protocol (assume HTTPS if no specific indication)
        local protocol="https"
        local url="$protocol://$host$path"
        
        echo ""
        echo "[$current/$total_urls] Testing: $url"
        echo "  Namespace: $namespace | Ingress: $name"
        
        # Test DNS resolution
        local dns_ok=false
        if nslookup "$host" &> /dev/null; then
            print_status "SUCCESS" "DNS: $host resolved"
            dns_ok=true
        else
            print_status "ERROR" "DNS: $host failed to resolve"
            dns_failed=$((dns_failed + 1))
        fi
        
        # Test HTTP connectivity if DNS is OK
        if [[ "$dns_ok" == "true" ]]; then
            # Use curl with timeout
            local http_status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")
            
            if [[ "$http_status" =~ ^[2-5][0-9][0-9]$ ]]; then
                print_status "SUCCESS" "HTTP: $http_status (DNS resolved, service reachable)"
                healthy_count=$((healthy_count + 1))
                INGRESS_ISSUES+=("$url|Healthy ($http_status)")
            else
                print_status "ERROR" "HTTP: Connection failed (Status: $http_status)"
                http_failed=$((http_failed + 1))
                INGRESS_ISSUES+=("$url|Failed ($http_status)")
            fi
        else
            http_failed=$((http_failed + 1))
            INGRESS_ISSUES+=("$url|DNS Failed")
        fi
        
    done <<< "$urls"
    
    TOTAL_INGRESS=$total_urls
    HEALTHY_INGRESS=$healthy_count
    
    echo ""
    print_status "INFO" "Ingress URLs tested: $TOTAL_INGRESS, Healthy: $HEALTHY_INGRESS, DNS failures: $dns_failed, HTTP failures: $http_failed"
}

# Generate consolidated template report
generate_template_report() {
    echo ""
    echo ""
    print_status "HEADER" "Generating Cluster Delivery Template"
    
    # Get URLs from ingress results - extract healthy URLs
    local prometheus_url=""
    local alertmanager_url=""
    local grafana_url=""
    local dashboard_url=""
    local thanos_url=""
    local kiali_url=""
    
    # Parse through all ingress entries to find healthy ones
    for ingress_entry in "${INGRESS_ISSUES[@]}"; do
        IFS='|' read -r url status <<< "$ingress_entry"
        if [[ "$status" == *"Healthy"* ]]; then
            case "$url" in
                *prometheus.*)
                    if [[ "$url" != *"alertmanager"* ]]; then
                        prometheus_url="$url"
                    fi
                    ;;
                *alertmanager.*)
                    alertmanager_url="$url"
                    ;;
                *grafana.*)
                    grafana_url="$url"
                    ;;
                *dashboard.*)
                    dashboard_url="$url"
                    ;;
                *thanos-sidecar.*)
                    thanos_url="$url"
                    ;;
                *thanos-sc.*)
                    if [[ -z "$thanos_url" ]]; then
                        thanos_url="$url"
                    fi
                    ;;
                *kiali.*)
                    kiali_url="$url"
                    ;;
            esac
        fi
    done
    
    # Generate clean template output
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                              CLUSTER DELIVERY TEMPLATE                               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                                CLUSTER INFORMATION                                  │"
    echo "├─────────────────────────────────────────────────────────────────────────────────────┤"
    printf "│ %-20s: %-60s │\n" "Cluster Name" "$CLUSTER_NAME"
    printf "│ %-20s: %-60s │\n" "Cluster Version" "$CLUSTER_VERSION"
    printf "│ %-20s: %-60s │\n" "Istio Version" "$ISTIO_VERSION"
    printf "│ %-20s: %-60s │\n" "Namespaces" "(Product team namespaces only)"
    echo "└─────────────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                                SERVICE ENDPOINTS                                    │"
    echo "├─────────────────────────────────────────────────────────────────────────────────────┤"
    
    # Function to format URL display within the box - single line with full URLs
    format_service_url() {
        local service_name="$1"
        local url="$2"
        if [[ -z "$url" ]]; then
            url="(Not configured or not found)"
        fi
        
        # Calculate padding to maintain consistent box width
        local total_content_width=$((20 + 2 + ${#url}))  # name + ": " + url
        local min_width=79
        local padding=0
        
        if [[ $total_content_width -lt $min_width ]]; then
            padding=$((min_width - total_content_width))
        fi
        
        printf "│ %-20s: %s%*s │\n" "$service_name" "$url" $padding ""
    }
    
    format_service_url "Prometheus URL" "$prometheus_url"
    format_service_url "Alert Manager URL" "$alertmanager_url"
    format_service_url "Grafana URL" "$grafana_url"
    format_service_url "Dashboard URL" "$dashboard_url"
    format_service_url "Thanos URL" "$thanos_url"
    format_service_url "Kiali URL" "$kiali_url"
    format_service_url "Vault URL" "(To be configured)"
    echo "└─────────────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                                VALIDATION SUMMARY                                   │"
    echo "├─────────────────────────────────────────────────────────────────────────────────────┤"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Component" "Status" "Healthy" "Total" "Issues"
    echo "├─────────────────────┼────────────┼──────────┼──────────┼──────────┤"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Namespaces" "Active" "$ACTIVE_NAMESPACES" "$TOTAL_NAMESPACES" "${#NAMESPACE_ISSUES[@]}"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Helm Releases" "Deployed" "$DEPLOYED_HELM" "$TOTAL_HELM" "${#HELM_ISSUES[@]}"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Deployments" "Ready" "$READY_DEPLOYMENTS" "$TOTAL_DEPLOYMENTS" "${#DEPLOYMENT_ISSUES[@]}"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Ingress URLs" "Healthy" "$HEALTHY_INGRESS" "$TOTAL_INGRESS" "$((TOTAL_INGRESS - HEALTHY_INGRESS))"
    printf "│ %-20s │ %-10s │ %-8s │ %-8s │ %-8s │\n" "Kustomizations" "Ready" "$READY_KUSTOMIZATIONS" "$TOTAL_KUSTOMIZATIONS" "${#KUSTOMIZATION_ISSUES[@]}"
    echo "└─────────────────────┴────────────┴──────────┴──────────┴──────────┘"
    echo ""
    
    # Calculate total issues (including pod issues)
    local total_issues=$((${#NAMESPACE_ISSUES[@]} + ${#HELM_ISSUES[@]} + ${#DEPLOYMENT_ISSUES[@]} + TOTAL_INGRESS - HEALTHY_INGRESS + ${#KUSTOMIZATION_ISSUES[@]} + ${#POD_ISSUES[@]}))
    
    if [[ $total_issues -eq 0 ]]; then
        echo "🎉 OVERALL STATUS: ALL SYSTEMS HEALTHY - CLUSTER READY FOR DELIVERY! 🎉"
    else
        echo "⚠️  OVERALL STATUS: $total_issues ISSUES FOUND - REVIEW REQUIRED ⚠️"
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────────────────────┐"
        echo "│                           🔍 DETAILED ISSUES BREAKDOWN                             │"
        echo "├─────────────────────────────────────────────────────────────────────────────────────┤"
        
        # Function to safely truncate text for display
        format_issue_text() {
            local text="$1"
            if [[ ${#text} -gt 77 ]]; then
                echo "${text:0:74}..."
            else
                echo "$text"
            fi
        }
        
        # Collect all issues in one organized display
        local has_issues=false
        
        # Show specific failed namespaces
        if [[ ${#NAMESPACE_ISSUES[@]} -gt 0 ]]; then
            printf "│ %-79s │\n" "❌ NAMESPACES (${#NAMESPACE_ISSUES[@]} issues):"
            for issue in "${NAMESPACE_ISSUES[@]}"; do
                local formatted_issue=$(format_issue_text "   • $issue")
                printf "│ %-79s │\n" "$formatted_issue"
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        # Show specific failed helm releases
        if [[ ${#HELM_ISSUES[@]} -gt 0 ]]; then
            printf "│ %-79s │\n" "❌ HELM RELEASES (${#HELM_ISSUES[@]} issues):"
            for issue in "${HELM_ISSUES[@]}"; do
                local formatted_issue=$(format_issue_text "   • $issue")
                printf "│ %-79s │\n" "$formatted_issue"
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        # Show specific failed deployments
        if [[ ${#DEPLOYMENT_ISSUES[@]} -gt 0 ]]; then
            printf "│ %-79s │\n" "❌ DEPLOYMENTS (${#DEPLOYMENT_ISSUES[@]} issues):"
            for issue in "${DEPLOYMENT_ISSUES[@]}"; do
                local formatted_issue=$(format_issue_text "   • $issue")
                printf "│ %-79s │\n" "$formatted_issue"
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        # Show pod issues
        if [[ ${#POD_ISSUES[@]} -gt 0 ]]; then
            printf "│ %-79s │\n" "⚠️  POD ISSUES (${#POD_ISSUES[@]} pods with problems):"
            for issue in "${POD_ISSUES[@]}"; do
                local formatted_issue=$(format_issue_text "   • $issue")
                printf "│ %-79s │\n" "$formatted_issue"
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        # Show specific failed ingress URLs
        if [[ $((TOTAL_INGRESS - HEALTHY_INGRESS)) -gt 0 ]]; then
            printf "│ %-79s │\n" "❌ INGRESS URLs ($((TOTAL_INGRESS - HEALTHY_INGRESS)) issues):"
            for ingress_entry in "${INGRESS_ISSUES[@]}"; do
                IFS='|' read -r url status <<< "$ingress_entry"
                if [[ "$status" != *"Healthy"* ]]; then
                    local formatted_issue=$(format_issue_text "   • $url: $status")
                    printf "│ %-79s │\n" "$formatted_issue"
                fi
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        # Show specific failed kustomizations
        if [[ ${#KUSTOMIZATION_ISSUES[@]} -gt 0 ]]; then
            printf "│ %-79s │\n" "❌ KUSTOMIZATIONS (${#KUSTOMIZATION_ISSUES[@]} issues):"
            for issue in "${KUSTOMIZATION_ISSUES[@]}"; do
                local formatted_issue=$(format_issue_text "   • $issue")
                printf "│ %-79s │\n" "$formatted_issue"
            done
            printf "│ %-79s │\n" ""
            has_issues=true
        fi
        
        if [[ "$has_issues" == "false" ]]; then
            printf "│ %-79s │\n" "No specific issues to report."
        fi
        
        echo "└─────────────────────────────────────────────────────────────────────────────────────┘"
    fi
    echo ""
}

# Main execution
main() {
    print_status "HEADER" "Starting Kubernetes Cluster Validation"
    
    # Get cluster info
    get_cluster_info
    
    # Build kubectl command
    build_kubectl_cmd
    
    # Run all checks
    check_namespaces
    check_helm_releases
    check_deployments
    check_pods
    check_flux_kustomizations
    check_nodes
    check_istio_version
    check_ingress_urls
    
    # Generate template report
    generate_template_report
    
    print_status "HEADER" "Cluster validation completed!"
}

# Run main function
main "$@"
