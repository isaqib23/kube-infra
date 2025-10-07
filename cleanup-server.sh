#!/bin/bash

# Ubuntu Server Cleanup Script
# Completely removes all Kubernetes components and restores fresh Ubuntu state
# Version: 1.0

set -euo pipefail

LOG_FILE="/var/log/cleanup-server.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

confirm_cleanup() {
    echo "WARNING: This will completely remove all Kubernetes components and restore a fresh Ubuntu state!"
    echo "This action is IRREVERSIBLE and will:"
    echo "- Remove all Kubernetes clusters and data"
    echo "- Remove all container images and volumes"
    echo "- Reset network and system configurations"
    echo "- Remove all installed packages from k8s-setup.sh"
    echo
    read -p "Are you absolutely sure you want to continue? [type 'YES' to confirm]: " confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

stop_kubernetes_services() {
    log "Stopping Kubernetes services..."
    
    # Stop kubelet first
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    
    # Stop containerd
    systemctl stop containerd 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true
    
    # Stop docker if running
    systemctl stop docker 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    
    log "Services stopped ✓"
}

reset_kubernetes_cluster() {
    log "Resetting Kubernetes cluster..."
    
    # Reset kubeadm if it exists
    if command -v kubeadm >/dev/null 2>&1; then
        kubeadm reset -f --cleanup-tmp-dir 2>/dev/null || true
    fi
    
    # Force cleanup of remaining pods
    crictl rm --force $(crictl ps -aq) 2>/dev/null || true
    crictl rmi --prune 2>/dev/null || true
    
    log "Kubernetes cluster reset ✓"
}

remove_kubernetes_packages() {
    log "Removing Kubernetes packages..."
    
    # Unhold packages first
    apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    
    # Remove Kubernetes packages
    apt purge -y kubelet kubeadm kubectl kubernetes-cni 2>/dev/null || true
    
    # Remove Kubernetes repository
    rm -f /etc/apt/sources.list.d/kubernetes.list
    rm -f /usr/share/keyrings/kubernetes-apt-keyring.gpg
    
    log "Kubernetes packages removed ✓"
}

remove_container_runtime() {
    log "Removing container runtime and Docker components..."
    
    # Remove containerd and Docker packages
    apt purge -y \
        containerd.io \
        docker.io \
        docker-doc \
        docker-compose \
        docker-compose-plugin \
        docker-ce \
        docker-ce-cli \
        docker-buildx-plugin \
        podman-docker \
        runc 2>/dev/null || true
    
    # Remove Docker repository
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    
    log "Container runtime removed ✓"
}

remove_helm() {
    log "Removing Helm..."
    
    # Remove Helm binary
    rm -f /usr/local/bin/helm
    rm -f /usr/bin/helm
    
    # Remove Helm repository
    rm -f /etc/apt/sources.list.d/helm-stable-debian.list
    rm -f /usr/share/keyrings/helm.gpg
    
    # Remove Helm cache and config
    rm -rf /root/.helm
    rm -rf /root/.cache/helm
    rm -rf /root/.config/helm
    
    # Remove for all users
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            rm -rf "$user_home/.helm"
            rm -rf "$user_home/.cache/helm"
            rm -rf "$user_home/.config/helm"
        fi
    done
    
    log "Helm removed ✓"
}

clean_kubernetes_directories() {
    log "Cleaning Kubernetes directories and configurations..."
    
    # Remove Kubernetes directories
    rm -rf /etc/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/kubeadm
    rm -rf /var/lib/etcd
    rm -rf /etc/cni
    rm -rf /opt/cni
    rm -rf /var/lib/cni
    
    # Remove kubectl configs for all users
    rm -rf /root/.kube
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            rm -rf "$user_home/.kube"
        fi
    done
    
    # Remove containerd directories
    rm -rf /etc/containerd
    rm -rf /var/lib/containerd
    rm -rf /run/containerd
    
    # Remove Docker directories
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    
    log "Kubernetes directories cleaned ✓"
}

clean_network_configuration() {
    log "Cleaning network configurations..."
    
    # Remove CNI network interfaces
    for interface in $(ip link show | grep -E "(cni|flannel|calico|weave)" | awk -F: '{print $2}' | tr -d ' '); do
        ip link delete "$interface" 2>/dev/null || true
    done
    
    # Remove bridge interfaces
    for bridge in $(ip link show type bridge | grep -E "(docker|k8s|cni)" | awk -F: '{print $2}' | tr -d ' '); do
        ip link delete "$bridge" 2>/dev/null || true
    done
    
    # Clean iptables rules
    iptables -F 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    
    log "Network configuration cleaned ✓"
}

restore_system_configuration() {
    log "Restoring original system configuration..."
    
    # Remove kernel module configuration
    rm -f /etc/modules-load.d/k8s.conf
    rm -f /etc/modules-load.d/containerd.conf
    
    # Remove sysctl configuration
    rm -f /etc/sysctl.d/k8s.conf
    rm -f /etc/sysctl.d/docker.conf
    rm -f /etc/sysctl.d/99-kubernetes-cri.conf
    
    # Restore original sysctl values
    sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
    sysctl -w net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
    sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
    
    # Reload sysctl
    sysctl --system >/dev/null 2>&1 || true
    
    log "System configuration restored ✓"
}

restore_swap() {
    log "Restoring swap configuration..."
    
    # Restore swap entries in fstab
    sed -i 's/^#.*swap.*$//' /etc/fstab
    sed -i '/^$/d' /etc/fstab
    
    # Re-enable swap if swap files/partitions exist
    if [[ -f /swapfile ]]; then
        swapon /swapfile 2>/dev/null || true
    fi
    
    # Check for swap partitions and enable them
    for swap_partition in $(blkid | grep -i swap | cut -d: -f1); do
        swapon "$swap_partition" 2>/dev/null || true
    done
    
    log "Swap configuration restored ✓"
}

clean_hostname() {
    log "Cleaning hostname modifications..."
    
    # Remove k8s-related entries from /etc/hosts
    sed -i '/k8s-master/d' /etc/hosts
    sed -i '/k8s-worker/d' /etc/hosts
    sed -i '/k8s-node/d' /etc/hosts
    
    # Reset hostname to original if it was changed
    if grep -q "k8s" /etc/hostname; then
        echo "ubuntu-server" > /etc/hostname
        hostnamectl set-hostname ubuntu-server
    fi
    
    log "Hostname cleaned ✓"
}

remove_logs_and_temp_files() {
    log "Removing logs and temporary files..."
    
    # Remove setup logs
    rm -f /var/log/k8s-setup.log
    rm -f /var/log/k8s-*.log
    
    # Remove downloaded manifests and scripts
    rm -f /root/tigera-operator.yaml
    rm -f /root/custom-resources.yaml
    rm -f /root/get_helm.sh
    rm -f /root/local-storage-class.yaml
    
    # Remove any remaining Kubernetes-related files in /tmp
    find /tmp -name "*k8s*" -delete 2>/dev/null || true
    find /tmp -name "*kubernetes*" -delete 2>/dev/null || true
    find /tmp -name "*containerd*" -delete 2>/dev/null || true
    find /tmp -name "*calico*" -delete 2>/dev/null || true
    
    log "Logs and temporary files removed ✓"
}

clean_packages_and_cache() {
    log "Cleaning packages and cache..."
    
    # Update package database
    apt update
    
    # Remove orphaned packages
    apt autoremove -y --purge
    
    # Clean package cache
    apt autoclean
    apt clean
    
    # Remove any remaining package files
    find /var/cache/apt -type f -delete 2>/dev/null || true
    
    log "Packages and cache cleaned ✓"
}

remove_systemd_services() {
    log "Removing systemd service files..."
    
    # Remove Kubernetes systemd files
    rm -f /etc/systemd/system/kubelet.service
    rm -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    rm -f /lib/systemd/system/kubelet.service
    rm -f /usr/lib/systemd/system/kubelet.service
    
    # Remove containerd systemd files (if not system default)
    systemctl stop containerd 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload
    
    log "Systemd services cleaned ✓"
}

final_cleanup() {
    log "Performing final cleanup..."
    
    # Remove any remaining processes
    pkill -f kubelet 2>/dev/null || true
    pkill -f containerd 2>/dev/null || true
    pkill -f dockerd 2>/dev/null || true
    
    # Unmount any remaining Kubernetes mounts
    for mount in $(mount | grep -E "(kubelet|containerd|docker)" | awk '{print $3}'); do
        umount "$mount" 2>/dev/null || true
    done
    
    # Clear bash history for root (optional)
    history -c 2>/dev/null || true
    
    log "Final cleanup completed ✓"
}

show_cleanup_summary() {
    log "Cleanup completed successfully!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "✓ Kubernetes cluster reset and removed"
    echo "✓ All Kubernetes packages removed"
    echo "✓ Container runtime (containerd/Docker) removed"
    echo "✓ Helm removed"
    echo "✓ System configurations restored"
    echo "✓ Network configurations cleaned"
    echo "✓ Swap restored"
    echo "✓ Hostname cleaned"
    echo "✓ Logs and temporary files removed"
    echo "✓ Package cache cleaned"
    echo
    echo "=== VERIFICATION ==="
    echo "Remaining packages check:"
    dpkg -l | grep -E "(kubelet|kubeadm|kubectl|containerd|docker)" || echo "No Kubernetes/Docker packages found ✓"
    echo
    echo "Running services check:"
    systemctl list-units --type=service --state=running | grep -E "(kubelet|containerd|docker)" || echo "No Kubernetes/Docker services running ✓"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Reboot the server: sudo reboot"
    echo "2. Verify clean state after reboot"
    echo "3. Server is now in fresh Ubuntu state"
    echo
    echo "Your Ubuntu server has been restored to a clean state!"
}

main() {
    log "Starting Ubuntu server cleanup..."
    
    check_root
    confirm_cleanup
    
    # Phase 1: Stop all services
    stop_kubernetes_services
    
    # Phase 2: Reset Kubernetes
    reset_kubernetes_cluster
    
    # Phase 3: Remove packages
    remove_kubernetes_packages
    remove_container_runtime
    remove_helm
    
    # Phase 4: Clean directories and configurations
    clean_kubernetes_directories
    clean_network_configuration
    restore_system_configuration
    restore_swap
    clean_hostname
    
    # Phase 5: Clean logs and temporary files
    remove_logs_and_temp_files
    remove_systemd_services
    
    # Phase 6: Final cleanup
    clean_packages_and_cache
    final_cleanup
    
    show_cleanup_summary
    
    log "Ubuntu server cleanup completed successfully!"
}

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Ubuntu Server Cleanup Script"
    echo "Completely removes all Kubernetes components and restores fresh Ubuntu state"
    echo
    echo "Usage: sudo $0"
    echo
    echo "This script will:"
    echo "1. Stop all Kubernetes and container services"
    echo "2. Reset and remove Kubernetes cluster"
    echo "3. Remove all Kubernetes packages and repositories"
    echo "4. Remove container runtime (containerd/Docker)"
    echo "5. Remove Helm and other tools"
    echo "6. Clean all configurations and directories"
    echo "7. Restore original system settings"
    echo "8. Clean network configurations"
    echo "9. Restore swap configuration"
    echo "10. Remove logs and temporary files"
    echo
    echo "WARNING: This action is IRREVERSIBLE!"
    exit 0
fi

main "$@"