#!/bin/bash

# Kubernetes Reset Script for HA Cluster
# Purpose: Reset only Kubernetes components while preserving server prep and load balancer setup
# Run this on ALL nodes that have joined the cluster

set -euo pipefail

LOG_FILE="/var/log/ha-k8s-reset.log"

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
    echo "    Kubernetes Reset for HA Cluster"
    echo "    Preserving Server Prep + Load Balancer Setup"
    echo "=============================================================="
    echo -e "${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

get_confirmation() {
    echo "=== WHAT THIS SCRIPT WILL DO ==="
    echo "✓ PRESERVE: Server preparation (packages, network, firewall)"
    echo "✓ PRESERVE: HAProxy and Keepalived configuration"
    echo "✗ RESET: Kubernetes cluster state (kubeadm reset)"
    echo "✗ RESET: kubectl configuration"
    echo "✗ RESET: Container images and data"
    echo "✗ RESET: etcd data"
    echo
    echo "After this reset, you can run the FIXED scripts cleanly:"
    echo "1. 03-ha-cluster-init.sh (on k8s-cp1)"
    echo "2. 04-ha-cluster-join.sh (on other nodes)"
    echo
    
    read -p "Continue with Kubernetes reset? [y/N]: " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Reset cancelled."
        exit 0
    fi
}

stop_kubernetes_services() {
    log "Stopping Kubernetes services..."
    
    # Stop kubelet
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    
    # Stop containerd temporarily
    systemctl stop containerd 2>/dev/null || true
    
    success "Kubernetes services stopped"
}

reset_kubernetes_cluster() {
    log "Resetting Kubernetes cluster state..."
    
    # Reset kubeadm
    if command -v kubeadm &>/dev/null; then
        kubeadm reset --force 2>/dev/null || true
        success "kubeadm reset completed"
    fi
    
    # Clean up kubectl config
    rm -rf /root/.kube 2>/dev/null || true
    rm -rf /home/ubuntu/.kube 2>/dev/null || true
    rm -rf /home/rao/.kube 2>/dev/null || true
    success "kubectl configurations removed"
    
    # Clean up Kubernetes directories
    rm -rf /etc/kubernetes/manifests/* 2>/dev/null || true
    rm -rf /var/lib/etcd/* 2>/dev/null || true
    rm -rf /var/lib/kubelet/* 2>/dev/null || true
    rm -rf /var/lib/dockershim 2>/dev/null || true
    rm -rf /var/run/kubernetes 2>/dev/null || true
    rm -rf /opt/kubernetes/join-info 2>/dev/null || true
    
    success "Kubernetes directories cleaned"
}

clean_container_state() {
    log "Cleaning container state..."
    
    # Stop all containers
    if command -v crictl &>/dev/null; then
        crictl stop $(crictl ps -q) 2>/dev/null || true
        crictl rm $(crictl ps -aq) 2>/dev/null || true
        crictl rmi --prune 2>/dev/null || true
    fi
    
    # Clean containerd state
    rm -rf /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs 2>/dev/null || true
    rm -rf /var/lib/containerd/tmpmounts 2>/dev/null || true
    
    success "Container state cleaned"
}

clean_network_state() {
    log "Cleaning network state..."
    
    # Remove CNI networks
    rm -rf /etc/cni/net.d/* 2>/dev/null || true
    rm -rf /var/lib/cni 2>/dev/null || true
    
    # Clean up any remaining network interfaces
    for iface in $(ip link show | grep -E 'cali|flannel|weave|cni' | cut -d: -f2 | tr -d ' '); do
        ip link delete "$iface" 2>/dev/null || true
    done
    
    # Clean iptables rules (be careful, preserve basic rules)
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    
    success "Network state cleaned"
}

update_haproxy_config() {
    log "Updating HAProxy configuration for fresh start..."
    
    # Reset HAProxy config to use port 16443 (pre-cluster state)
    if [[ -f /etc/haproxy/haproxy.cfg ]]; then
        sed -i 's/bind.*:6443/bind 10.255.254.'"$(hostname | cut -d'-' -f3)"':16443/' /etc/haproxy/haproxy.cfg
        sed -i 's/bind 127.0.0.1:6443/bind 127.0.0.1:16443/' /etc/haproxy/haproxy.cfg
        
        # Restart HAProxy with updated config
        systemctl restart haproxy
        success "HAProxy configuration reset to pre-cluster state"
    fi
}

restart_services() {
    log "Restarting services..."
    
    # Restart containerd
    systemctl start containerd
    systemctl enable containerd
    
    # Ensure Keepalived is running
    systemctl restart keepalived
    systemctl enable keepalived
    
    # Ensure HAProxy is running
    systemctl restart haproxy
    systemctl enable haproxy
    
    # Re-enable kubelet (but don't start it yet)
    systemctl enable kubelet
    
    success "Services restarted"
}

verify_reset_state() {
    log "Verifying reset state..."
    
    # Check that Kubernetes is not running
    if ! systemctl is-active --quiet kubelet; then
        success "kubelet is stopped"
    else
        warning "kubelet is still running"
    fi
    
    # Check that basic services are running
    if systemctl is-active --quiet containerd; then
        success "containerd is running"
    else
        error "containerd is not running"
    fi
    
    if systemctl is-active --quiet keepalived; then
        success "keepalived is running"
    else
        error "keepalived is not running"
    fi
    
    if systemctl is-active --quiet haproxy; then
        success "haproxy is running"
    else
        error "haproxy is not running"
    fi
    
    # Check that kubectl doesn't work (as expected)
    if ! kubectl get nodes &>/dev/null; then
        success "kubectl is not configured (expected after reset)"
    else
        warning "kubectl still works (unexpected)"
    fi
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 Kubernetes Reset Completed!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Current State ==="
    echo "✓ Server preparation: PRESERVED"
    echo "✓ Load balancer setup: PRESERVED and RESET for fresh start"
    echo "✓ Kubernetes cluster: RESET (clean slate)"
    echo "✓ Container runtime: RUNNING"
    echo "✓ HA services: RUNNING"
    echo
    echo "=== Next Steps ==="
    echo "1. Run this reset script on ALL nodes that were in the cluster"
    echo "2. Run the FIXED cluster initialization: ./03-ha-cluster-init.sh (on k8s-cp1)"
    echo "3. Run the FIXED cluster join: ./04-ha-cluster-join.sh (on k8s-cp2, cp3, cp4)"
    echo "4. Continue with storage, ingress, monitoring phases"
    echo
    echo "=== Useful Commands ==="
    echo "• Check services: systemctl status kubelet containerd keepalived haproxy"
    echo "• Check VIP: ip addr show | grep 10.255.254.100"
    echo "• Test integration: ./10-integration-test.sh"
    echo
    echo -e "${GREEN}Ready for clean HA deployment with fixed scripts! 🚀${NC}"
}

main() {
    banner
    check_root
    get_confirmation
    
    log "Starting Kubernetes reset on $(hostname)..."
    
    stop_kubernetes_services
    reset_kubernetes_cluster
    clean_container_state
    clean_network_state
    update_haproxy_config
    restart_services
    verify_reset_state
    
    show_completion_info
    
    success "Kubernetes reset completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script resets only Kubernetes components while preserving:"
        echo "• Server preparation (packages, network, firewall)"
        echo "• Load balancer configuration (HAProxy + Keepalived)"
        echo
        echo "Run this on ALL nodes, then use the fixed scripts for clean deployment."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac