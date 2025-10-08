#!/bin/bash

# Complete Server Reset Script for HA Kubernetes Cluster
# Purpose: Reset ALL servers back to fresh Ubuntu 24.04 state
# Run this script on ALL 4 servers to start completely from scratch

set -euo pipefail

LOG_FILE="/var/log/complete-reset.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
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
    echo -e "${RED}${BOLD}"
    echo "################################################################"
    echo "#                                                              #"
    echo "#                ⚠️  COMPLETE SERVER RESET ⚠️                  #"
    echo "#                                                              #"
    echo "#     This will remove ALL Kubernetes and HA components       #"
    echo "#     and return the server to fresh Ubuntu 24.04 state       #"
    echo "#                                                              #"
    echo "################################################################"
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
    echo -e "${RED}${BOLD}=== DANGER: COMPLETE RESET OPERATION ===${NC}"
    echo
    echo "This script will COMPLETELY REMOVE:"
    echo "❌ ALL Kubernetes components (kubeadm, kubelet, kubectl)"
    echo "❌ ALL container runtimes (containerd, Docker)"
    echo "❌ ALL HA components (HAProxy, Keepalived)"
    echo "❌ ALL cluster data (etcd, certificates, configs)"
    echo "❌ ALL custom network configurations"
    echo "❌ ALL firewall rules"
    echo "❌ ALL storage directories"
    echo "❌ ALL logs and backup data"
    echo
    echo "This will PRESERVE:"
    echo "✅ Base Ubuntu 24.04 OS"
    echo "✅ User accounts and SSH keys"
    echo "✅ Basic system packages"
    echo
    echo "After this reset, you'll need to run:"
    echo "1. 01-server-preparation.sh (on all servers)"
    echo "2. 02-ha-loadbalancer-setup.sh (on all servers)"
    echo "3. 03-ha-cluster-init.sh (on k8s-cp1)"
    echo "4. 04-ha-cluster-join.sh (on k8s-cp2, cp3, cp4)"
    echo "5. Continue with remaining phases..."
    echo
    echo -e "${RED}${BOLD}This operation is IRREVERSIBLE!${NC}"
    echo
    
    read -p "Type 'RESET' to confirm complete server reset: " CONFIRM
    if [[ "$CONFIRM" != "RESET" ]]; then
        echo "Reset cancelled."
        exit 0
    fi
    
    echo
    read -p "Are you absolutely sure? Type 'YES' to proceed: " FINAL_CONFIRM
    if [[ "$FINAL_CONFIRM" != "YES" ]]; then
        echo "Reset cancelled."
        exit 0
    fi
}

stop_all_services() {
    log "Stopping all Kubernetes and HA services..."
    
    # Stop Kubernetes services
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop kubeadm 2>/dev/null || true
    
    # Stop container services
    systemctl stop containerd 2>/dev/null || true
    systemctl stop docker 2>/dev/null || true
    systemctl stop dockerd 2>/dev/null || true
    
    # Stop HA services
    systemctl stop haproxy 2>/dev/null || true
    systemctl stop keepalived 2>/dev/null || true
    
    # Stop monitoring services if they exist
    systemctl stop prometheus 2>/dev/null || true
    systemctl stop grafana-server 2>/dev/null || true
    systemctl stop node_exporter 2>/dev/null || true
    
    success "All services stopped"
}

disable_all_services() {
    log "Disabling all Kubernetes and HA services..."
    
    # Disable Kubernetes services
    systemctl disable kubelet 2>/dev/null || true
    systemctl disable kubeadm 2>/dev/null || true
    
    # Disable container services
    systemctl disable containerd 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    systemctl disable dockerd 2>/dev/null || true
    
    # Disable HA services
    systemctl disable haproxy 2>/dev/null || true
    systemctl disable keepalived 2>/dev/null || true
    
    success "All services disabled"
}

reset_kubernetes_completely() {
    log "Completely removing Kubernetes components..."
    
    # Stop services first
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop kubeadm 2>/dev/null || true
    
    # Reset kubeadm if available
    if command -v kubeadm &>/dev/null; then
        kubeadm reset --force 2>/dev/null || true
    fi
    
    # Force remove data directories before package removal
    rm -rf /etc/kubernetes/* 2>/dev/null || true
    rm -rf /var/lib/kubelet/* 2>/dev/null || true
    rm -rf /var/lib/etcd/* 2>/dev/null || true
    rm -rf /var/lib/dockershim/* 2>/dev/null || true
    rm -rf /var/run/kubernetes/* 2>/dev/null || true
    rm -rf /var/log/kubernetes/* 2>/dev/null || true
    rm -rf /opt/kubernetes/* 2>/dev/null || true
    rm -rf /opt/cni/* 2>/dev/null || true
    rm -rf /etc/cni/* 2>/dev/null || true
    rm -rf /var/lib/cni/* 2>/dev/null || true
    
    # Remove all Kubernetes packages
    apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    apt remove --purge -y kubelet kubeadm kubectl kubernetes-cni 2>/dev/null || true
    
    # Force remove any remaining directories after package removal
    rm -rf /etc/kubernetes 2>/dev/null || true
    rm -rf /var/lib/kubelet 2>/dev/null || true
    rm -rf /var/lib/etcd 2>/dev/null || true
    rm -rf /var/lib/dockershim 2>/dev/null || true
    rm -rf /var/run/kubernetes 2>/dev/null || true
    rm -rf /var/log/kubernetes 2>/dev/null || true
    rm -rf /opt/kubernetes 2>/dev/null || true
    rm -rf /opt/cni 2>/dev/null || true
    rm -rf /etc/cni 2>/dev/null || true
    rm -rf /var/lib/cni 2>/dev/null || true
    
    # Remove Kubernetes repositories
    rm -f /etc/apt/sources.list.d/kubernetes.list
    rm -f /usr/share/keyrings/kubernetes-apt-keyring.gpg
    
    apt autoremove -y 2>/dev/null || true
    
    success "Kubernetes components removed"
}

reset_container_runtime() {
    log "Completely removing container runtimes..."
    
    # Stop services first
    systemctl stop containerd 2>/dev/null || true
    systemctl stop docker 2>/dev/null || true
    systemctl stop dockerd 2>/dev/null || true
    
    # Stop and remove all containers
    if command -v crictl &>/dev/null; then
        crictl stop $(crictl ps -q) 2>/dev/null || true
        crictl rm $(crictl ps -aq) 2>/dev/null || true
        crictl rmi --prune 2>/dev/null || true
    fi
    
    if command -v docker &>/dev/null; then
        docker stop $(docker ps -q) 2>/dev/null || true
        docker rm $(docker ps -aq) 2>/dev/null || true
        docker rmi $(docker images -q) 2>/dev/null || true
        docker system prune -af 2>/dev/null || true
    fi
    
    # Force remove data directories before package removal
    rm -rf /var/lib/containerd/* 2>/dev/null || true
    rm -rf /var/lib/docker/* 2>/dev/null || true
    rm -rf /var/lib/dockershim/* 2>/dev/null || true
    rm -rf /run/containerd/* 2>/dev/null || true
    rm -rf /run/docker/* 2>/dev/null || true
    rm -rf /etc/containerd/* 2>/dev/null || true
    rm -rf /etc/docker/* 2>/dev/null || true
    
    # Remove container runtime packages
    apt remove --purge -y containerd.io docker.io docker-ce docker-ce-cli docker-compose-plugin runc 2>/dev/null || true
    
    # Force remove any remaining directories after package removal
    rm -rf /var/lib/containerd 2>/dev/null || true
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -rf /var/lib/dockershim 2>/dev/null || true
    rm -rf /run/containerd 2>/dev/null || true
    rm -rf /run/docker 2>/dev/null || true
    rm -rf /etc/containerd 2>/dev/null || true
    rm -rf /etc/docker 2>/dev/null || true
    
    # Remove Docker/containerd repositories
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    
    apt autoremove -y 2>/dev/null || true
    
    success "Container runtimes removed"
}

reset_ha_components() {
    log "Completely removing HA components..."
    
    # Stop services first
    systemctl stop haproxy 2>/dev/null || true
    systemctl stop keepalived 2>/dev/null || true
    
    # Force remove configuration files and directories before package removal
    rm -rf /etc/haproxy/* 2>/dev/null || true
    rm -rf /etc/keepalived/* 2>/dev/null || true
    rm -rf /var/lib/haproxy/* 2>/dev/null || true
    rm -rf /run/haproxy/* 2>/dev/null || true
    
    # Remove HA packages
    apt remove --purge -y haproxy keepalived 2>/dev/null || true
    
    # Force remove any remaining directories after package removal
    rm -rf /etc/haproxy 2>/dev/null || true
    rm -rf /etc/keepalived 2>/dev/null || true
    rm -rf /var/lib/haproxy 2>/dev/null || true
    rm -rf /run/haproxy 2>/dev/null || true
    
    # Remove any leftover users/groups
    userdel haproxy 2>/dev/null || true
    groupdel haproxy 2>/dev/null || true
    
    # Clean up crontab entries
    crontab -l 2>/dev/null | grep -v -E 'haproxy|keepalived' | crontab - 2>/dev/null || true
    
    apt autoremove -y 2>/dev/null || true
    
    success "HA components removed"
}

clean_remaining_directories() {
    log "Cleaning remaining directories and configurations..."
    
    # Remove user kubectl configs (not handled by package removal)
    rm -rf /root/.kube
    rm -rf /home/*/.kube 2>/dev/null || true
    
    # Remove helm if installed
    rm -f /usr/local/bin/helm
    rm -rf /root/.helm
    rm -rf /home/*/.helm 2>/dev/null || true
    
    # Remove custom storage directories
    rm -rf /mnt/k8s-storage
    
    # Remove any remaining runtime directories
    rm -rf /run/flannel 2>/dev/null || true
    rm -rf /run/calico 2>/dev/null || true
    rm -rf /tmp/calico-* 2>/dev/null || true
    
    # Remove systemd unit files that may have been left behind
    rm -f /etc/systemd/system/kubelet.service 2>/dev/null || true
    rm -f /etc/systemd/system/containerd.service 2>/dev/null || true
    rm -f /lib/systemd/system/kubelet.service 2>/dev/null || true
    
    success "Remaining directories cleaned"
}

reset_network_configuration() {
    log "Resetting network configuration..."
    
    # Remove custom network interfaces
    for iface in $(ip link show | grep -E 'cali|flannel|weave|cni|docker|br-' | cut -d: -f2 | tr -d ' '); do
        ip link delete "$iface" 2>/dev/null || true
    done
    
    # Reset netplan to basic configuration
    cat > /etc/netplan/50-cloud-init.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: true
EOF
    
    # Apply basic network config
    netplan apply 2>/dev/null || true
    
    success "Network configuration reset"
}

reset_firewall() {
    log "Resetting firewall to default state..."
    
    # Reset UFW to defaults
    ufw --force reset 2>/dev/null || true
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow ssh 2>/dev/null || true
    ufw --force disable 2>/dev/null || true
    
    # Clean iptables rules
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    
    success "Firewall reset to defaults"
}

reset_system_configuration() {
    log "Resetting system configuration..."
    
    # Remove custom sysctl parameters
    rm -f /etc/sysctl.d/k8s.conf
    rm -f /etc/sysctl.d/99-kubernetes-cri.conf
    
    # Remove custom kernel modules
    rm -f /etc/modules-load.d/k8s.conf
    rm -f /etc/modules-load.d/containerd.conf
    
    # Reset /etc/hosts to basic
    cat > /etc/hosts << 'EOF'
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    
    # Re-enable swap if it was disabled
    sed -i 's/^#.*swap//' /etc/fstab 2>/dev/null || true
    
    # Remove custom systemd overrides
    rm -rf /etc/systemd/system/kubelet.service.d
    rm -rf /etc/systemd/system/containerd.service.d
    rm -rf /etc/systemd/system/haproxy.service.d
    rm -rf /etc/systemd/system/keepalived.service.d
    
    systemctl daemon-reload
    
    success "System configuration reset"
}

clean_logs_and_cache() {
    log "Cleaning logs and cache..."
    
    # Clean logs
    rm -f /var/log/ha-*.log
    rm -f /var/log/k8s-*.log
    rm -f /var/log/kubernetes-*.log
    rm -f /var/log/haproxy.log
    rm -f /var/log/keepalived.log
    rm -f /var/log/etcd-backup.log
    
    # Clean apt cache
    apt clean
    apt autoclean
    
    # Clean journal logs older than 1 day
    journalctl --vacuum-time=1d
    
    success "Logs and cache cleaned"
}

remove_custom_repositories() {
    log "Removing custom repositories..."
    
    # Remove Helm repository
    rm -f /etc/apt/sources.list.d/helm-stable-debian.list
    
    # Remove any monitoring repositories
    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /etc/apt/sources.list.d/prometheus.list
    
    # Update package lists
    apt update
    
    success "Custom repositories removed"
}

cleanup_package_system() {
    log "Cleaning up package system and fixing dpkg issues..."
    
    # Force reconfigure dpkg to clean up any broken packages
    dpkg --configure -a 2>/dev/null || true
    
    # Fix any broken dependencies
    apt --fix-broken install -y 2>/dev/null || true
    
    # Clean package cache thoroughly
    apt clean
    apt autoclean
    apt autoremove --purge -y 2>/dev/null || true
    
    # Update package database
    apt update
    
    # Remove any orphaned configuration files
    for pkg in $(dpkg -l | grep '^rc' | awk '{print $2}'); do
        dpkg --purge "$pkg" 2>/dev/null || true
    done
    
    success "Package system cleaned up"
}

reset_hostname_if_needed() {
    log "Checking hostname configuration..."
    
    local current_hostname=$(hostname)
    
    if [[ "$current_hostname" =~ ^k8s-cp[1-4]$ ]]; then
        warning "Hostname is set to $current_hostname"
        echo "You may want to reset hostname after this script completes."
        echo "Use: sudo hostnamectl set-hostname <new-name>"
    else
        success "Hostname is: $current_hostname (no reset needed)"
    fi
}

verify_reset_state() {
    log "Verifying complete reset state..."
    
    # Check that Kubernetes is gone
    if ! command -v kubectl &>/dev/null; then
        success "kubectl removed"
    else
        warning "kubectl still present"
    fi
    
    if ! command -v kubeadm &>/dev/null; then
        success "kubeadm removed"
    else
        warning "kubeadm still present"
    fi
    
    # Check that container runtimes are gone
    if ! command -v containerd &>/dev/null; then
        success "containerd removed"
    else
        warning "containerd still present"
    fi
    
    # Check that HA components are gone
    if ! command -v haproxy &>/dev/null; then
        success "haproxy removed"
    else
        warning "haproxy still present"
    fi
    
    if ! command -v keepalived &>/dev/null; then
        success "keepalived removed"
    else
        warning "keepalived still present"
    fi
    
    # Check that directories are gone
    if [[ ! -d /etc/kubernetes ]]; then
        success "/etc/kubernetes removed"
    else
        warning "/etc/kubernetes still exists"
    fi
    
    if [[ ! -d /var/lib/etcd ]]; then
        success "/var/lib/etcd removed"
    else
        warning "/var/lib/etcd still exists"
    fi
}

show_completion_info() {
    echo
    echo -e "${GREEN}${BOLD}################################################################"
    echo "#                                                              #"
    echo "#               🎉 COMPLETE RESET SUCCESSFUL! 🎉               #"
    echo "#                                                              #"
    echo "################################################################${NC}"
    echo
    echo -e "${GREEN}=== Server Reset Summary ===${NC}"
    echo "✅ All Kubernetes components removed"
    echo "✅ All container runtimes removed"
    echo "✅ All HA components removed"
    echo "✅ All cluster data and configs removed"
    echo "✅ Network configuration reset"
    echo "✅ Firewall reset to defaults"
    echo "✅ System configuration reset"
    echo "✅ Logs and cache cleaned"
    echo
    echo -e "${BLUE}=== Current Server State ===${NC}"
    echo "🖥️  Fresh Ubuntu 24.04 LTS"
    echo "👤 User accounts and SSH keys preserved"
    echo "🌐 Basic network configuration (DHCP)"
    echo "🔒 Basic firewall (SSH allowed)"
    echo
    echo -e "${YELLOW}=== Next Steps ===${NC}"
    echo "1. Run this reset script on ALL 4 servers"
    echo "2. Configure static IPs if needed"
    echo "3. Start fresh deployment:"
    echo "   └── ./01-server-preparation.sh (all servers)"
    echo "   └── ./02-ha-loadbalancer-setup.sh (all servers)"
    echo "   └── ./03-ha-cluster-init.sh (k8s-cp1 only)"
    echo "   └── ./04-ha-cluster-join.sh (k8s-cp2, cp3, cp4)"
    echo "   └── Continue with phases 5-8..."
    echo
    echo -e "${GREEN}=== Useful Commands ===${NC}"
    echo "• Check system status: systemctl status"
    echo "• Check network: ip addr show"
    echo "• Check packages: dpkg -l | grep -E 'kube|docker|contain|haproxy|keepalived'"
    echo "• Update system: apt update && apt upgrade"
    echo
    echo -e "${GREEN}${BOLD}Server $(hostname) is now ready for fresh HA deployment! 🚀${NC}"
}

main() {
    banner
    check_root
    get_confirmation
    
    log "Starting complete server reset on $(hostname)..."
    
    # Stop everything
    stop_all_services
    disable_all_services
    
    # Remove all components
    reset_kubernetes_completely
    reset_container_runtime
    reset_ha_components
    
    # Clean everything
    clean_remaining_directories
    reset_network_configuration
    reset_firewall
    reset_system_configuration
    clean_logs_and_cache
    remove_custom_repositories
    cleanup_package_system
    
    # Final checks
    reset_hostname_if_needed
    verify_reset_state
    
    show_completion_info
    
    success "Complete server reset finished successfully!"
    
    echo
    echo -e "${YELLOW}💻 REBOOT RECOMMENDED after running this script on all servers!${NC}"
    echo -e "${YELLOW}Run: sudo reboot${NC}"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "⚠️  DANGER: This script completely resets the server to fresh Ubuntu 24.04"
        echo
        echo "This removes ALL Kubernetes, container, and HA components, returning"
        echo "the server to a clean state for fresh deployment."
        echo
        echo "Run this script on ALL 4 servers if you want to start completely fresh."
        echo
        echo "After reset, run scripts 01-server-preparation.sh through 08-cluster-validation.sh"
        exit 0
        ;;
    --force)
        # Skip confirmations (dangerous!)
        export FORCE_RESET=true
        main "$@"
        ;;
    *)
        main "$@"
        ;;
esac