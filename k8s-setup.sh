#!/bin/bash

# Kubernetes Setup Script for Ubuntu 24.04 on Dell R740
# Production-ready Kubernetes cluster setup
# Version: 1.0

set -euo pipefail

LOG_FILE="/var/log/k8s-setup.log"
KUBE_VERSION="1.34"
CONTAINERD_VERSION="1.7.28"
CALICO_VERSION="v3.30.1"

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

check_ubuntu_version() {
    if ! grep -q "24.04" /etc/os-release; then
        error "This script is designed for Ubuntu 24.04"
    fi
    log "Ubuntu 24.04 detected ✓"
}

update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
    log "System updated ✓"
}

install_dependencies() {
    log "Installing required dependencies..."
    apt install -y \
        curl \
        wget \
        git \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        gnupg \
        lsb-release \
        net-tools \
        htop \
        iotop \
        iftop \
        vim \
        jq
    log "Dependencies installed ✓"
}

configure_hostname() {
    local hostname="${1:-k8s-master}"
    log "Configuring hostname to: $hostname"
    hostnamectl set-hostname "$hostname"
    
    # Update /etc/hosts
    local ip=$(hostname -I | awk '{print $1}')
    echo "$ip $hostname" >> /etc/hosts
    log "Hostname configured ✓"
}

disable_swap() {
    log "Disabling swap..."
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    log "Swap disabled ✓"
}

configure_kernel_modules() {
    log "Configuring kernel modules..."
    
    # Load modules
    modprobe overlay
    modprobe br_netfilter
    
    # Ensure modules load at boot
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    log "Kernel modules configured ✓"
}

configure_sysctl() {
    log "Configuring sysctl parameters..."
    
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    
    sysctl --system
    log "Sysctl parameters configured ✓"
}

install_containerd() {
    log "Installing containerd..."
    
    # Remove any existing installations
    apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y containerd.io
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Enable SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    systemctl restart containerd
    systemctl enable containerd
    
    log "Containerd installed and configured ✓"
}

install_kubernetes() {
    log "Installing Kubernetes components..."
    
    # Add Kubernetes GPG key
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes repository
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    
    apt update
    apt install -y kubelet kubeadm kubectl
    
    # Hold packages to prevent accidental upgrades
    apt-mark hold kubelet kubeadm kubectl
    
    log "Kubernetes components installed ✓"
}

initialize_cluster() {
    local pod_network_cidr="${1:-192.168.0.0/16}"
    log "Initializing Kubernetes cluster with pod network CIDR: $pod_network_cidr"
    
    # Initialize cluster
    kubeadm init --pod-network-cidr="$pod_network_cidr" --cri-socket unix:///var/run/containerd/containerd.sock
    
    # Configure kubectl for root
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    
    log "Kubernetes cluster initialized ✓"
}

configure_kubectl_user() {
    local username="${1:-ubuntu}"
    log "Configuring kubectl for user: $username"
    
    if id "$username" &>/dev/null; then
        local user_home=$(eval echo ~$username)
        mkdir -p "$user_home/.kube"
        cp -i /etc/kubernetes/admin.conf "$user_home/.kube/config"
        chown "$username:$username" "$user_home/.kube/config"
        log "kubectl configured for $username ✓"
    else
        log "User $username not found, skipping kubectl configuration"
    fi
}

install_calico() {
    log "Installing Calico CNI..."
    
    # Download Calico manifest
    curl -O https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml
    curl -O https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml
    
    # Apply Tigera operator first
    kubectl create -f tigera-operator.yaml
    
    # Wait for CRDs to be established
    log "Waiting for Tigera operator CRDs to be ready..."
    kubectl wait --for condition=established --timeout=120s crd/installations.operator.tigera.io || true
    kubectl wait --for condition=established --timeout=120s crd/apiservers.operator.tigera.io || true
    
    # Wait a bit more for operator to be fully ready
    sleep 30
    
    # Now apply custom resources
    kubectl create -f custom-resources.yaml
    
    log "Calico CNI installed ✓"
}

allow_scheduling_on_control_plane() {
    log "Allowing pod scheduling on control plane node..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    log "Control plane node configured for scheduling ✓"
}

install_metrics_server() {
    log "Installing metrics-server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Patch metrics-server for development/testing
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }
    ]'
    
    log "Metrics-server installed ✓"
}

install_helm() {
    log "Installing Helm..."
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
    apt update
    apt install -y helm
    log "Helm installed ✓"
}

install_nginx_ingress() {
    log "Installing NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=NodePort \
        --set controller.metrics.enabled=true
    log "NGINX Ingress Controller installed ✓"
}

create_storage_class() {
    log "Creating local storage class..."
    cat > local-storage-class.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
    
    kubectl apply -f local-storage-class.yaml
    log "Local storage class created ✓"
}

show_cluster_info() {
    log "Cluster setup completed! Here's your cluster information:"
    echo
    echo "=== Cluster Status ==="
    kubectl get nodes -o wide
    echo
    echo "=== System Pods ==="
    kubectl get pods -A
    echo
    echo "=== Services ==="
    kubectl get svc -A
    echo
    echo "=== Join Command for Worker Nodes ==="
    kubeadm token create --print-join-command
    echo
    echo "=== Access Information ==="
    echo "kubectl config file: /root/.kube/config"
    echo "To access from another machine, copy this config file"
    echo
    echo "=== Next Steps ==="
    echo "1. Test cluster: kubectl get nodes"
    echo "2. Deploy test application: kubectl create deployment nginx --image=nginx"
    echo "3. Add worker nodes using the join command above"
    echo "4. Configure persistent storage as needed"
}

main() {
    log "Starting Kubernetes setup on Dell R740..."
    
    check_root
    check_ubuntu_version
    
    # Phase 1: Server Preparation
    update_system
    install_dependencies
    configure_hostname "${1:-k8s-master}"
    disable_swap
    configure_kernel_modules
    configure_sysctl
    
    # Phase 2: Container Runtime
    install_containerd
    
    # Phase 3: Kubernetes Installation
    install_kubernetes
    
    # Phase 4: Cluster Initialization
    initialize_cluster
    configure_kubectl_user "${2:-ubuntu}"
    
    # Phase 5: CNI and Add-ons
    install_calico
    allow_scheduling_on_control_plane
    install_metrics_server
    install_helm
    install_nginx_ingress
    create_storage_class
    
    # Wait for cluster to be ready
    log "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    show_cluster_info
    
    log "Kubernetes setup completed successfully!"
}

# Usage information
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [hostname] [username]"
    echo "Example: $0 k8s-master ubuntu"
    echo
    echo "This script will:"
    echo "1. Prepare Ubuntu 24.04 for Kubernetes"
    echo "2. Install containerd as container runtime"
    echo "3. Install and configure Kubernetes"
    echo "4. Initialize a single-node cluster"
    echo "5. Install Calico CNI, metrics-server, Helm, and NGINX Ingress"
    echo
    read -p "Continue with defaults (hostname: k8s-master, user: ubuntu)? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

main "$@"