#!/bin/bash

# Integration Test Script for HA Kubernetes Deployment
# Purpose: Test the fixes for VIP integration and HAProxy conflicts

set -euo pipefail

LOG_FILE="/var/log/ha-integration-test.log"
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
    echo "=============================================================="
    echo "    HA Kubernetes Integration Test"
    echo "    Testing VIP and HAProxy Integration Fixes"
    echo "=============================================================="
    echo -e "${NC}"
    echo
}

test_haproxy_config() {
    log "Testing HAProxy configuration..."
    
    # Check if HAProxy config uses port 16443 initially
    if grep -q "bind.*16443" /etc/haproxy/haproxy.cfg; then
        success "HAProxy configured for port 16443 (no conflict with Kubernetes)"
    else
        warning "HAProxy not configured for alternate port"
    fi
    
    # Test HAProxy config validation
    if haproxy -f /etc/haproxy/haproxy.cfg -c; then
        success "HAProxy configuration is valid"
    else
        error "HAProxy configuration validation failed"
    fi
}

test_vip_assignment() {
    log "Testing VIP assignment..."
    
    if ip addr show | grep -q "$VIP"; then
        success "VIP $VIP is assigned to this server"
    else
        warning "VIP $VIP is not assigned to this server (may be on another node)"
    fi
    
    if ping -c 2 "$VIP" &>/dev/null; then
        success "VIP $VIP is reachable"
    else
        error "VIP $VIP is not reachable"
    fi
}

test_kubernetes_readiness() {
    log "Testing Kubernetes readiness..."
    
    if command -v kubectl &>/dev/null; then
        success "kubectl is installed"
        
        if [[ -f /root/.kube/config ]] || [[ -f /home/rao/.kube/config ]]; then
            success "kubectl config exists"
            
            # Test cluster access
            if kubectl cluster-info &>/dev/null; then
                success "Kubernetes cluster is accessible"
                
                # Check nodes
                local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
                log "Ready nodes: $ready_nodes"
                
            else
                warning "Kubernetes cluster not yet accessible"
            fi
        else
            warning "kubectl config not found"
        fi
    else
        warning "kubectl not installed yet"
    fi
}

test_port_conflicts() {
    log "Testing for port conflicts..."
    
    # Check if anything is listening on port 6443
    local port_6443_users=$(netstat -tlnp | grep ":6443" | wc -l || echo "0")
    
    if [[ $port_6443_users -eq 0 ]]; then
        success "Port 6443 is available for Kubernetes API"
    elif [[ $port_6443_users -eq 1 ]]; then
        local service=$(netstat -tlnp | grep ":6443" | awk '{print $7}' | head -1)
        log "Port 6443 in use by: $service (expected if Kubernetes is running)"
    else
        warning "Multiple services using port 6443: $port_6443_users"
    fi
    
    # Check if anything is listening on port 16443
    local port_16443_users=$(netstat -tlnp | grep ":16443" | wc -l || echo "0")
    
    if [[ $port_16443_users -eq 1 ]]; then
        local service=$(netstat -tlnp | grep ":16443" | awk '{print $7}' | head -1)
        success "Port 16443 in use by HAProxy: $service"
    else
        warning "Port 16443 not in use (HAProxy may not be running)"
    fi
}

test_service_status() {
    log "Testing service status..."
    
    # Check Keepalived
    if systemctl is-active --quiet keepalived; then
        success "Keepalived is running"
    else
        warning "Keepalived is not running"
    fi
    
    # Check HAProxy
    if systemctl is-active --quiet haproxy; then
        success "HAProxy is running"
    else
        warning "HAProxy is not running"
    fi
    
    # Check kubelet
    if systemctl is-active --quiet kubelet; then
        success "kubelet is running"
    else
        warning "kubelet is not running"
    fi
}

show_summary() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "Integration Test Summary"
    echo -e "==============================================================${NC}"
    echo
    echo "This test validates that the integration fixes are working:"
    echo "1. HAProxy uses alternate port (16443) to avoid conflicts"
    echo "2. VIP is properly managed by Keepalived"
    echo "3. No port conflicts between HAProxy and Kubernetes"
    echo "4. Services are configured correctly"
    echo
    echo "If all tests pass, you can proceed with clean deployment."
    echo
}

main() {
    banner
    
    log "Starting integration test for HA Kubernetes fixes..."
    
    test_haproxy_config
    test_vip_assignment
    test_port_conflicts
    test_service_status
    test_kubernetes_readiness
    
    show_summary
    
    success "Integration test completed"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script tests the integration fixes for HA Kubernetes deployment."
        echo "Run this script to verify that the VIP and HAProxy fixes are working."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac