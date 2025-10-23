#!/bin/bash

# Server Preparation Script for Staging Kubernetes Cluster
# Run this script on BOTH staging Dell R740 servers (k8s-stg1, k8s-stg2)
# Purpose: Prepare fresh Ubuntu 24.04 systems for Kubernetes 2-node HA deployment

set -euo pipefail

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env-config.sh"
source "$SCRIPT_DIR/../common/common-functions.sh"

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    STAGING Kubernetes Server Preparation - Dell R740"
    echo "=============================================================="
    echo -e "${NC}"
    echo "Environment: STAGING (2-server setup)"
    echo "This script will prepare a fresh Ubuntu 24.04 server for"
    echo "Staging Kubernetes cluster deployment."
    echo
}

get_server_info() {
    echo "=== Staging Server Configuration ==="
    echo "Current hostname: $(hostname)"
    echo "Current IP: $(hostname -I | awk '{print $1}')"
    echo
    echo "Available staging server configurations:"
    for server in "${!SERVER_CONFIG[@]}"; do
        IFS=':' read -r ip priority <<< "${SERVER_CONFIG[$server]}"
        echo "  $server: $ip"
    done
    echo

    read -p "Enter this server's hostname (k8s-stg1 or k8s-stg2): " SERVER_NAME

    if [[ ! ${SERVER_CONFIG[$SERVER_NAME]+_} ]]; then
        error "Invalid server name. Must be one of: ${!SERVER_CONFIG[*]}"
    fi

    IFS=':' read -r SERVER_IP SERVER_PRIORITY <<< "${SERVER_CONFIG[$SERVER_NAME]}"
    echo
    echo "Configuration for this server:"
    echo "  Environment: STAGING"
    echo "  Hostname: $SERVER_NAME"
    echo "  IP Address: $SERVER_IP"
    echo "  VIP: $VIP"
    echo

    read -p "Is this configuration correct? [y/N]: " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled"
        exit 0
    fi
}

configure_hostname() {
    log "Configuring hostname to: $SERVER_NAME"

    # Set hostname
    hostnamectl set-hostname "$SERVER_NAME"

    # Update /etc/hosts with all staging cluster nodes
    cat > /etc/hosts << EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

# Staging Kubernetes Cluster Nodes
10.255.254.20    k8s-stg1
10.255.254.21    k8s-stg2
10.255.254.100   k8s-stg-api

# Local server entry
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
      gateway4: $GATEWAY
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

    # Install essential packages
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
        unzip \
        keepalived \
        haproxy

    success "System packages updated"
}

configure_time_sync() {
    log "Configuring time synchronization..."

    systemctl enable ntpsec 2>/dev/null || systemctl enable systemd-timesyncd
    systemctl start ntpsec 2>/dev/null || systemctl start systemd-timesyncd

    if systemctl is-active --quiet ntpsec || systemctl is-active --quiet systemd-timesyncd; then
        success "Time synchronization configured"
    else
        warning "Time sync service may not be running properly, but continuing..."
    fi
}

disable_swap() {
    log "Disabling swap (required for Kubernetes)..."

    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    success "Swap disabled permanently"
}

configure_kernel_modules() {
    log "Configuring kernel modules for Kubernetes..."

    modprobe overlay
    modprobe br_netfilter

    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF

    success "Kernel modules configured"
}

configure_sysctl() {
    log "Configuring sysctl parameters for Kubernetes..."

    cat > /etc/sysctl.d/k8s.conf << EOF
# Kubernetes networking requirements
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1

# Additional optimizations for staging cluster
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

    sysctl --system

    success "Sysctl parameters configured"
}

configure_firewall() {
    log "Configuring firewall for Kubernetes..."

    apt install -y ufw
    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing

    # Essential services
    ufw allow 22/tcp
    ufw allow 6443/tcp
    ufw allow 2379:2380/tcp
    ufw allow 10250/tcp
    ufw allow 10259/tcp
    ufw allow 10257/tcp
    ufw allow 30000:32767/tcp
    ufw allow 179/tcp
    ufw allow 4789/udp
    ufw allow 8404/tcp

    # Allow all traffic from staging cluster subnet
    ufw allow from 10.255.254.0/24
    ufw allow from 192.168.0.0/16  # Pod network
    ufw allow from 10.96.0.0/12    # Service network

    ufw --force enable

    success "Firewall configured for Kubernetes"
}

install_containerd() {
    log "Installing containerd container runtime..."

    apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update
    apt install -y containerd.io

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    systemctl restart containerd
    systemctl enable containerd

    success "containerd installed and configured"
}

install_kubernetes() {
    log "Installing Kubernetes components..."

    rm -f /usr/share/keyrings/kubernetes-apt-keyring.gpg

    curl -fsSL https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/core:/stable:/v${KUBE_VERSION}/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/core:/stable:/v${KUBE_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

    apt update
    apt install -y kubelet kubeadm kubectl

    apt-mark hold kubelet kubeadm kubectl

    systemctl enable kubelet

    success "Kubernetes components installed"
}

create_directories() {
    log "Creating necessary directories..."

    mkdir -p /etc/kubernetes/pki
    mkdir -p /var/lib/etcd
    mkdir -p /var/log/kubernetes
    mkdir -p /opt/kubernetes/backups
    mkdir -p /etc/haproxy/ssl
    mkdir -p /etc/keepalived

    chmod 700 /var/lib/etcd
    chmod 755 /var/log/kubernetes
    chmod 755 /opt/kubernetes/backups

    success "Directories created"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 STAGING Server Preparation Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Server Information ==="
    echo "Environment: STAGING"
    echo "Hostname: $SERVER_NAME"
    echo "IP Address: $SERVER_IP"
    echo "VIP: $VIP"
    echo
    echo "=== Installed Components ==="
    echo "containerd version: $(containerd --version | cut -d' ' -f3)"
    echo "kubeadm version: $(kubeadm version --output=short)"
    echo "kubelet version: $(kubelet --version | cut -d' ' -f2)"
    echo "kubectl version: $(kubectl version --client --output=json | jq -r '.clientVersion.gitVersion')"
    echo
    echo "=== Next Steps ==="
    echo "1. Run this script on both servers (k8s-stg1, k8s-stg2)"
    echo "2. Run 02-ha-loadbalancer-setup.sh on both servers"
    echo "3. Run 03-ha-cluster-init.sh on k8s-stg1 (first control plane)"
    echo "4. Run 04-ha-cluster-join.sh on k8s-stg2"
    echo
    echo "=== Important Notes ==="
    echo "- This is a 2-node staging cluster (limited HA)"
    echo "- etcd quorum requires both nodes to be operational"
    echo "- SSH keys should be exchanged between servers"
    echo "- Network connectivity verified between nodes"
    echo
    echo -e "${GREEN}Server $SERVER_NAME is ready for STAGING Kubernetes deployment!${NC}"
}

main() {
    banner
    check_root
    check_ubuntu_version
    get_server_info

    log "Starting staging server preparation for $SERVER_NAME..."

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

    success "Staging server preparation completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script prepares a fresh Ubuntu 24.04 server for STAGING Kubernetes deployment."
        echo "Run this script on BOTH staging servers (k8s-stg1, k8s-stg2)."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
