#!/bin/bash

# Quick Reset and Join Script
# Run this on k8s-cp2, k8s-cp3, k8s-cp4 if they have leftover Kubernetes files
# Purpose: Clean reset and rejoin to cluster

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    Quick Reset and Rejoin - Control Plane Node"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will:"
    echo "1. Reset Kubernetes completely"
    echo "2. Clean all Kubernetes files"
    echo "3. Restart container runtime"
    echo "4. Run the join script"
    echo
}

reset_kubernetes() {
    log "Resetting Kubernetes..."

    # Reset kubeadm
    kubeadm reset -f || true

    # Remove Kubernetes files
    rm -rf /etc/kubernetes/
    rm -rf /var/lib/etcd/
    rm -rf ~/.kube/
    rm -rf /home/*/. kube/

    # Remove CNI configs
    rm -rf /etc/cni/net.d/
    rm -rf /var/lib/cni/

    # Remove any leftover iptables rules
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X || true

    success "Kubernetes reset complete"
}

restart_services() {
    log "Restarting container runtime and kubelet..."

    # Restart containerd
    systemctl stop kubelet || true
    systemctl stop containerd || true
    sleep 2
    systemctl start containerd
    systemctl start kubelet

    success "Services restarted"
}

verify_clean_state() {
    log "Verifying clean state..."

    # Check no Kubernetes files exist
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        error "Kubernetes files still exist. Reset may have failed."
    fi

    # Check port 10250 is free
    if netstat -tlnp | grep -q ":10250"; then
        warning "Port 10250 still in use, but continuing..."
    fi

    success "Clean state verified"
}

main() {
    banner
    check_root

    local hostname=$(hostname)
    log "Starting quick reset and rejoin for $hostname..."

    # Confirm with user
    read -p "This will completely reset Kubernetes on this node. Continue? [y/N]: " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Reset cancelled."
        exit 0
    fi

    # Perform reset
    reset_kubernetes
    restart_services
    verify_clean_state

    echo
    success "Reset complete! Now you can run the join script:"
    echo
    echo "  sudo ./04-ha-cluster-join.sh"
    echo
}

main "$@"
