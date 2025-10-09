#!/bin/bash

# Post-Join HAProxy Configuration Check
# Run this script AFTER all 4 control planes have joined the cluster
# Purpose: Verify HAProxy configuration across all nodes

set -euo pipefail

LOG_FILE="/var/log/post-join-haproxy-check.log"

# Control plane servers
declare -A CONTROL_PLANES=(
    ["k8s-cp1"]="10.255.254.10"
    ["k8s-cp2"]="10.255.254.11"
    ["k8s-cp3"]="10.255.254.12"
    ["k8s-cp4"]="10.255.254.13"
)
VIP="10.255.254.100"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

banner() {
    echo -e "${BLUE}"
    echo "================================================================"
    echo "    Post-Join HAProxy Configuration Check"
    echo "================================================================"
    echo -e "${NC}"
    echo "This script verifies HAProxy configuration after all"
    echo "control planes have joined the cluster."
    echo
}

check_cluster_nodes() {
    log "Checking cluster nodes..."

    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")

    if [[ $ready_nodes -eq 4 ]]; then
        success "All 4 nodes are Ready"
    else
        error "Only $ready_nodes nodes are Ready. Expected 4 nodes."
        kubectl get nodes
        exit 1
    fi
}

check_vip_assignment() {
    log "Checking VIP assignment..."

    local current_node=$(hostname)

    if ip addr show | grep -q "$VIP"; then
        success "VIP $VIP is assigned to this node ($current_node)"
        return 0
    else
        warning "VIP $VIP is NOT assigned to this node ($current_node)"
        return 1
    fi
}

check_haproxy_status() {
    log "Checking HAProxy status on this node..."

    local current_node=$(hostname)

    if systemctl is-active --quiet haproxy; then
        warning "HAProxy is RUNNING on $current_node"

        # Check if it's conflicting
        if netstat -tlnp 2>/dev/null | grep -q ":6443.*haproxy"; then
            error "HAProxy is listening on port 6443 - this may conflict with kube-apiserver"
        fi
    else
        log "HAProxy is NOT running on $current_node"
    fi
}

check_api_accessibility() {
    log "Checking Kubernetes API accessibility..."

    # Test localhost
    if curl -k "https://127.0.0.1:6443/healthz" &>/dev/null; then
        success "✓ API accessible via localhost:6443"
    else
        error "✗ API NOT accessible via localhost:6443"
    fi

    # Test VIP
    if curl -k "https://$VIP:6443/healthz" &>/dev/null; then
        success "✓ API accessible via VIP:6443"
    else
        error "✗ API NOT accessible via VIP:6443"
    fi

    # Test each control plane
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if curl -k "https://$node_ip:6443/healthz" &>/dev/null; then
            success "✓ API accessible via $node ($node_ip:6443)"
        else
            warning "⚠ API NOT accessible via $node ($node_ip:6443)"
        fi
    done
}

show_recommendations() {
    echo
    echo -e "${BLUE}================================================================"
    echo "                    Recommendations"
    echo "================================================================${NC}"
    echo

    local has_vip=0
    if ip addr show | grep -q "$VIP"; then
        has_vip=1
    fi

    echo "Current Node: $(hostname)"
    echo "VIP Assignment: $(if [[ $has_vip -eq 1 ]]; then echo "YES (MASTER)"; else echo "NO (BACKUP)"; fi)"
    echo

    if [[ $has_vip -eq 1 ]]; then
        echo -e "${YELLOW}This node has the VIP:${NC}"
        echo "  → HAProxy should be DISABLED (conflicts with kube-apiserver)"
        echo "  → kube-apiserver handles VIP:6443 directly"
        echo
        echo "Commands:"
        echo "  sudo systemctl stop haproxy"
        echo "  sudo systemctl disable haproxy"
    else
        echo -e "${GREEN}This node does NOT have the VIP:${NC}"
        echo "  → HAProxy can run if needed for monitoring/stats"
        echo "  → But it's OPTIONAL - kube-apiserver + keepalived is sufficient"
        echo
        echo "To enable HAProxy (optional):"
        echo "  sudo systemctl enable haproxy"
        echo "  sudo systemctl start haproxy"
    fi

    echo
    echo -e "${BLUE}Summary:${NC}"
    echo "• Kubernetes API is accessible via VIP through kube-apiserver"
    echo "• Keepalived manages VIP failover between control planes"
    echo "• HAProxy is NOT required for HA functionality"
    echo "• HAProxy can be used optionally for stats/monitoring on non-VIP nodes"
    echo
}

main() {
    banner

    log "Starting post-join HAProxy configuration check..."

    check_cluster_nodes
    check_vip_assignment
    check_haproxy_status
    check_api_accessibility
    show_recommendations

    success "Post-join check completed!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script checks HAProxy configuration after all control planes"
        echo "have joined the cluster and provides recommendations."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
