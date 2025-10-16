#!/bin/bash

# Server Preparation Script for DEVELOPMENT Kubernetes Cluster
# Run this script on the single Dell R740 server (k8s-dev1)
# Purpose: Prepare fresh Ubuntu 24.04 system for single-node Kubernetes deployment

set -euo pipefail

# Configuration
KUBE_VERSION="1.34"
CONTAINERD_VERSION="1.7.28"
CALICO_VERSION="v3.30.1"
LOG_FILE="/var/log/dev-k8s-prep.log"

# Server configuration - Single node development environment
SERVER_NAME="k8s-dev1"
SERVER_IP="10.255.254.10"
# No VIP for single-node cluster
VIP=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    exit 1
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    DEVELOPMENT Kubernetes Server Preparation - Dell R740"
    echo "    Single-Node Cluster Setup"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will prepare a fresh Ubuntu 24.04 server for"
    echo "single-node Development Kubernetes cluster deployment."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_ubuntu_version() {
    if ! grep -q "24.04" /etc/os-release; then
        error "This script requires Ubuntu 24.04 LTS"
    fi
    success "Ubuntu 24.04 LTS detected"
}

show_server_info() {
    echo "=== Server Configuration ==="
    echo "Current hostname: $(hostname)"
    echo "Current IP: $(hostname -I | awk '{print $1}')"
    echo
    echo "Configuring as:"
    echo "  Hostname: $SERVER_NAME"
    echo "  IP Address: $SERVER_IP"
    echo "  Single-node development cluster (no VIP)"
    echo

    read -p "Continue with this configuration? [y/N]: " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled"
        exit 0
    fi
}

configure_hostname() {
    log "Configuring hostname to: $SERVER_NAME"
    
    # Set hostname
    hostnamectl set-hostname "$SERVER_NAME"
    
    # Update /etc/hosts
    cat > /etc/hosts << EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

# Kubernetes Development Single-Node Cluster
$SERVER_IP      $SERVER_NAME
EOF
    
    success "Hostname and hosts file configured"
}

configure_network() {
    log "Configuring network settings..."
    
    # Update existing netplan configuration for static IP
    cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    # Primary network interface - Dell R740 standard
    eno1:
      dhcp4: false
      addresses:
        - $SERVER_IP/24
      gateway4: 10.255.254.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
        search:
          - local
EOF
    
    # Apply network configuration
    netplan apply
    
    success "Network configuration applied"
}

update_system() {
    log "Updating system packages..."
    
    # Update package lists and upgrade system
    apt update
    apt upgrade -y
    
    # Install essential packages (no haproxy/keepalived for single-node)
    apt install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        iotop \
        iftop \
        net-tools \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        gnupg \
        lsb-release \
        jq \
        unzip
    
    success "System packages updated"
}

configure_time_sync() {
    log "Configuring time synchronization..."
    
    # Your system uses ntpsec (already installed and enabled)
    systemctl enable ntpsec
    systemctl start ntpsec
    
    # Check if ntpsec is running
    if systemctl is-active --quiet ntpsec; then
        success "Time synchronization configured (ntpsec active)"
    else
        warning "ntpsec service may not be running properly, but continuing..."
    fi
}

disable_swap() {
    log "Disabling swap (required for Kubernetes)..."
    
    # Turn off swap
    swapoff -a
    
    # Comment out swap entries in fstab
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    success "Swap disabled permanently"
}

configure_kernel_modules() {
    log "Configuring kernel modules for Kubernetes..."
    
    # Load required kernel modules
    modprobe overlay
    modprobe br_netfilter
    
    # Ensure modules load at boot
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    success "Kernel modules configured"
}

configure_sysctl() {
    log "Configuring sysctl parameters for Kubernetes..."
    
    # Configure kernel parameters
    cat > /etc/sysctl.d/k8s.conf << EOF
# Kubernetes networking requirements
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1

# Additional optimizations for HA cluster
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
vm.max_map_count = 262144
EOF
    
    # Apply sysctl parameters
    sysctl --system
    
    success "Sysctl parameters configured"
}

configure_firewall() {
    log "Configuring firewall for Kubernetes..."
    
    # Install ufw if not present
    apt install -y ufw
    
    # Reset firewall to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Kubernetes API server
    ufw allow 6443/tcp
    
    # etcd server client API
    ufw allow 2379:2380/tcp
    
    # Kubelet API
    ufw allow 10250/tcp
    
    # kube-scheduler
    ufw allow 10259/tcp
    
    # kube-controller-manager
    ufw allow 10257/tcp
    
    # NodePort Services
    ufw allow 30000:32767/tcp
    
    # Calico BGP
    ufw allow 179/tcp
    
    # Calico VXLAN
    ufw allow 4789/udp
    
    # HAProxy stats
    ufw allow 8404/tcp
    
# Allow all traffic from cluster subnet
    ufw allow from 10.255.254.0/24
    ufw allow from 192.168.0.0/16  # Pod network
    ufw allow from 10.96.0.0/12    # Service network
    
    # Enable firewall
    ufw --force enable
    
    success "Firewall configured for Kubernetes"
}

install_containerd() {
    log "Installing containerd container runtime..."
    
    # Remove any existing Docker installations
    apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists and install containerd
    apt update
    apt install -y containerd.io
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Enable SystemdCgroup (required for Kubernetes)
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Restart and enable containerd
    systemctl restart containerd
    systemctl enable containerd
    
    success "containerd installed and configured"
}

install_kubernetes() {
    log "Installing Kubernetes components..."
    
    # Remove any existing keyring first
    rm -f /usr/share/keyrings/kubernetes-apt-keyring.gpg
    
    # Use the new redirected URL format
    curl -fsSL https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/core:/stable:/v${KUBE_VERSION}/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes repository with new URL
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/core:/stable:/v${KUBE_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    
    # Update package lists and install Kubernetes components
    apt update
    apt install -y kubelet kubeadm kubectl
    
    # Hold packages to prevent accidental upgrades
    apt-mark hold kubelet kubeadm kubectl
    
    # Enable kubelet (it will fail to start until cluster is initialized)
    systemctl enable kubelet
    
    success "Kubernetes components installed"
}

create_directories() {
    log "Creating necessary directories..."

    # Create directories for cluster data
    mkdir -p /etc/kubernetes/pki
    mkdir -p /var/lib/etcd
    mkdir -p /var/log/kubernetes
    mkdir -p /opt/kubernetes/backups

    # Set proper permissions
    chmod 700 /var/lib/etcd
    chmod 755 /var/log/kubernetes
    chmod 755 /opt/kubernetes/backups

    success "Directories created"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 Server Preparation Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Server Information ==="
    echo "Hostname: $SERVER_NAME"
    echo "IP Address: $SERVER_IP"
    echo "Type: Single-node Development Cluster"
    echo
    echo "=== Installed Components ==="
    echo "containerd version: $(containerd --version | cut -d' ' -f3)"
    echo "kubeadm version: $(kubeadm version --output=short)"
    echo "kubelet version: $(kubelet --version | cut -d' ' -f2)"
    echo "kubectl version: $(kubectl version --client --output=json | jq -r '.clientVersion.gitVersion')"
    echo
    echo "=== Next Steps ==="
    echo "1. Skip 02-ha-loadbalancer-setup.sh (not needed for single-node)"
    echo "2. Run 03-ha-cluster-init.sh to initialize the cluster"
    echo "3. Run 05-ha-storage-setup.sh to configure storage"
    echo "4. Run 06-ha-ingress-setup.sh to setup ingress controller"
    echo "5. Run 07-ha-monitoring-setup.sh to deploy monitoring stack"
    echo "6. Run 08-cluster-validation.sh to validate the cluster"
    echo
    echo "=== Important Notes ==="
    echo "- Single-node cluster (no HA, no VIP)"
    echo "- Time synchronization is now active"
    echo "- Firewall configured for Kubernetes traffic"
    echo "- All resources available for workloads"
    echo
    echo -e "${GREEN}Server $SERVER_NAME is ready for Development Kubernetes deployment!${NC}"
}

main() {
    banner
    check_root
    check_ubuntu_version
    show_server_info

    log "Starting server preparation for $SERVER_NAME..."

    # System configuration
    configure_hostname
    configure_network
    update_system
    configure_time_sync
    disable_swap

    # Kubernetes prerequisites
    configure_kernel_modules
    configure_sysctl
    configure_firewall

    # Container runtime and Kubernetes
    install_containerd
    install_kubernetes

    # Final setup
    create_directories

    show_completion_info

    success "Server preparation completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script prepares a fresh Ubuntu 24.04 server for single-node Development Kubernetes deployment."
        echo "Run this script on the single Dell R740 server (k8s-dev1) before cluster initialization."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac