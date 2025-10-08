#!/bin/bash

# HA Kubernetes Cluster Initialization Script
# Run this script ONLY on k8s-cp1 (first control plane)
# Purpose: Initialize the Kubernetes cluster with HA configuration

set -euo pipefail

LOG_FILE="/var/log/ha-cluster-init.log"

# Cluster configuration
VIP="10.255.254.100"
CLUSTER_NAME="ha-k8s-cluster"
POD_NETWORK_CIDR="192.168.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
KUBE_VERSION="1.34.0"
CALICO_VERSION="v3.30.1"

# Control plane servers
declare -A CONTROL_PLANES=(
    ["k8s-cp1"]="10.255.254.10"
    ["k8s-cp2"]="10.255.254.11"
    ["k8s-cp3"]="10.255.254.12"
    ["k8s-cp4"]="10.255.254.13"
)

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
    exit 1
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    HA Kubernetes Cluster Initialization - k8s-cp1"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script initializes the first control plane node for a"
    echo "4-node High Availability Kubernetes cluster."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Verify this is k8s-cp1
    local hostname=$(hostname)
    if [[ "$hostname" != "k8s-cp1" ]]; then
        error "This script should only be run on k8s-cp1. Current hostname: $hostname"
    fi
    
    # Check if kubeadm is installed
    if ! command -v kubeadm &> /dev/null; then
        error "kubeadm is not installed. Run 01-server-preparation.sh first"
    fi
    
    # Check if VIP is accessible (should be assigned to this server initially)
    if ! ping -c 1 "$VIP" &> /dev/null; then
        warning "VIP $VIP is not responding. This may be normal during initial setup"
    fi
    
    # Check if HAProxy and Keepalived are installed (they may be stopped to avoid port conflicts)
    if ! command -v haproxy &> /dev/null; then
        error "HAProxy is not installed. Run 02-ha-loadbalancer-setup.sh first"
    fi
    
    if ! command -v keepalived &> /dev/null; then
        error "Keepalived is not installed. Run 02-ha-loadbalancer-setup.sh first"
    fi
    
    # HAProxy should already be configured for port 16443, no conflicts expected
    # But ensure Keepalived is running to assign VIP
    if ! systemctl is-active --quiet keepalived; then
        log "Starting Keepalived to ensure VIP assignment..."
        systemctl start keepalived
        sleep 10
    fi
    
    success "Prerequisites check passed"
}

wait_for_vip() {
    log "Checking VIP assignment status..."
    
    # If keepalived was stopped, we need to start it temporarily to get VIP
    if ! systemctl is-active --quiet keepalived; then
        log "Starting Keepalived temporarily to assign VIP..."
        systemctl start keepalived
        sleep 10
    fi
    
    local timeout=30
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if ip addr show | grep -q "$VIP"; then
            success "VIP $VIP is assigned to this server"
            return 0
        fi
        sleep 2
        ((counter+=2))
        echo -n "."
    done
    
    # Even if VIP isn't assigned, we can continue - it might be on another server
    warning "VIP $VIP not assigned to this server, but continuing cluster initialization"
    return 0
}

create_kubeadm_config() {
    log "Creating kubeadm configuration for HA cluster..."
    
    cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${CONTROL_PLANES[k8s-cp1]}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
    container-runtime-endpoint: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v$KUBE_VERSION
clusterName: $CLUSTER_NAME
controlPlaneEndpoint: "$VIP:6443"
networking:
  serviceSubnet: "$SERVICE_CIDR"
  podSubnet: "$POD_NETWORK_CIDR"
  dnsDomain: "cluster.local"
apiServer:
  advertiseAddress: ${CONTROL_PLANES[k8s-cp1]}
  certSANs:
  - "localhost"
  - "127.0.0.1"
  - "$VIP"
  - "k8s-api"
  - "k8s-api.local"
EOF

    # Add all control plane IPs and hostnames to cert SANs
    for hostname in "${!CONTROL_PLANES[@]}"; do
        echo "  - \"${CONTROL_PLANES[$hostname]}\"" >> /tmp/kubeadm-config.yaml
        echo "  - \"$hostname\"" >> /tmp/kubeadm-config.yaml
        echo "  - \"$hostname.local\"" >> /tmp/kubeadm-config.yaml
    done

    cat >> /tmp/kubeadm-config.yaml << EOF
  extraArgs:
    audit-log-maxage: "30"
    audit-log-maxbackup: "3"
    audit-log-maxsize: "100"
    audit-log-path: "/var/log/kubernetes/audit.log"
    enable-admission-plugins: "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota"
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
    terminated-pod-gc-threshold: "10"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
etcd:
  local:
    serverCertSANs:
    - "localhost"
    - "127.0.0.1"
    - "${CONTROL_PLANES[k8s-cp1]}"
    - "k8s-cp1"
    peerCertSANs:
    - "localhost"
    - "127.0.0.1"
    - "${CONTROL_PLANES[k8s-cp1]}"
    - "k8s-cp1"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerRuntimeEndpoint: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
  strictARP: true
EOF
    
    success "kubeadm configuration created"
}

pre_pull_images() {
    log "Pre-pulling Kubernetes images..."
    
    # Pre-pull images to speed up initialization
    kubeadm config images pull --config /tmp/kubeadm-config.yaml
    
    success "Kubernetes images pre-pulled"
}

initialize_cluster() {
    log "Initializing Kubernetes cluster..."
    
    # Keep Keepalived running - no conflicts expected with port 16443 HAProxy config
    log "Keeping Keepalived running for VIP management during initialization..."
    
    # Create audit log directory
    mkdir -p /var/log/kubernetes
    
    # Initialize the cluster
    kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs --v=5
    
    success "Kubernetes cluster initialized"
}

configure_kubectl() {
    log "Configuring kubectl for root user..."
    
    # Configure kubectl for root
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    
    # Configure kubectl for ubuntu user if exists
    if id "ubuntu" &>/dev/null; then
        log "Configuring kubectl for ubuntu user..."
        mkdir -p /home/ubuntu/.kube
        cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
        chown ubuntu:ubuntu /home/ubuntu/.kube/config
    fi
    
    success "kubectl configured"
}

wait_for_api_server() {
    log "Waiting for API server to be ready..."
    
    local timeout=300
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if kubectl get nodes &> /dev/null; then
            success "API server is ready"
            return 0
        fi
        sleep 5
        ((counter+=5))
        echo -n "."
    done
    
    error "API server was not ready within $timeout seconds"
}

install_calico_cni() {
    log "Installing Calico CNI for HA networking..."
    
    # Create directory for manifests
    mkdir -p /tmp/calico-manifests
    cd /tmp/calico-manifests
    
    # Try multiple methods to download Calico manifests
    local download_success=false
    
    # Method 1: Try direct curl with DNS fallback
    log "Attempting to download Calico manifests (Method 1: Direct curl)..."
    if curl -L -f --connect-timeout 30 --max-time 120 \
        -o tigera-operator.yaml \
        "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" 2>/dev/null && \
       curl -L -f --connect-timeout 30 --max-time 120 \
        -o custom-resources.yaml \
        "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" 2>/dev/null; then
        download_success=true
        log "Successfully downloaded manifests using direct curl"
    fi
    
    # Method 2: Try with explicit DNS servers
    if [[ "$download_success" != "true" ]]; then
        log "Attempting download with explicit DNS servers (Method 2)..."
        echo "nameserver 8.8.8.8" > /tmp/resolv.conf.backup
        echo "nameserver 8.8.4.4" >> /tmp/resolv.conf.backup
        echo "nameserver 1.1.1.1" >> /tmp/resolv.conf.backup
        cp /etc/resolv.conf /etc/resolv.conf.original
        cp /tmp/resolv.conf.backup /etc/resolv.conf
        
        if curl -L -f --connect-timeout 30 --max-time 120 \
            -o tigera-operator.yaml \
            "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" 2>/dev/null && \
           curl -L -f --connect-timeout 30 --max-time 120 \
            -o custom-resources.yaml \
            "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" 2>/dev/null; then
            download_success=true
            log "Successfully downloaded manifests using explicit DNS"
        fi
        
        # Restore original resolv.conf
        cp /etc/resolv.conf.original /etc/resolv.conf
    fi
    
    # Method 3: Use wget as fallback
    if [[ "$download_success" != "true" ]]; then
        log "Attempting download with wget (Method 3)..."
        if wget --timeout=120 --tries=3 \
            -O tigera-operator.yaml \
            "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" 2>/dev/null && \
           wget --timeout=120 --tries=3 \
            -O custom-resources.yaml \
            "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" 2>/dev/null; then
            download_success=true
            log "Successfully downloaded manifests using wget"
        fi
    fi
    
    # Method 4: Create manifests manually if download fails
    if [[ "$download_success" != "true" ]]; then
        warning "All download methods failed. Creating Calico manifests manually..."
        
        # Create tigera-operator.yaml manually
        cat > tigera-operator.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: tigera-operator
  labels:
    name: tigera-operator
---
apiVersion: v1
kind: CustomResourceDefinition
metadata:
  name: installations.operator.tigera.io
spec:
  group: operator.tigera.io
  scope: Cluster
  names:
    kind: Installation
    listKind: InstallationList
    plural: installations
    singular: installation
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        description: Installation configures an installation of Calico or Calico Enterprise.
        type: object
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation of an object.'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this object represents.'
            type: string
          metadata:
            type: object
          spec:
            description: Specification of the desired state for the Calico or Calico Enterprise installation.
            type: object
            properties:
              variant:
                description: The product variant - one of 'Calico' or 'TigeraSecureEnterprise'
                type: string
                enum: ['Calico', 'TigeraSecureEnterprise']
                default: Calico
          status:
            description: Most recently observed state for the Calico or Calico Enterprise installation.
            type: object
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tigera-operator
  namespace: tigera-operator
  labels:
    k8s-app: tigera-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      name: tigera-operator
  template:
    metadata:
      labels:
        name: tigera-operator
        k8s-app: tigera-operator
    spec:
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
      - effect: NoExecute
        operator: Exists
      - effect: NoSchedule
        operator: Exists
      serviceAccountName: tigera-operator
      hostNetwork: true
      containers:
      - name: tigera-operator
        image: quay.io/tigera/operator:v1.30.1
        imagePullPolicy: IfNotPresent
        command:
        - operator
        volumeMounts:
        - name: var-lib-calico
          readOnly: true
          mountPath: /var/lib/calico
        env:
        - name: WATCH_NAMESPACE
          value: ""
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: "tigera-operator"
        - name: TIGERA_OPERATOR_INIT_IMAGE_VERSION
          value: v1.30.1
        envFrom:
        - configMapRef:
            name: kubernetes-services-endpoint
            optional: true
      volumes:
      - name: var-lib-calico
        hostPath:
          path: /var/lib/calico
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tigera-operator
  namespace: tigera-operator
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  creationTimestamp: null
  name: tigera-operator
rules:
- apiGroups:
  - ""
  resources:
  - namespaces
  - pods
  - podtemplates
  - services
  - endpoints
  - events
  - configmaps
  - secrets
  - serviceaccounts
  verbs:
  - create
  - get
  - list
  - update
  - delete
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - update
  - patch
  - watch
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - clusterroles
  - clusterrolebindings
  - rolebindings
  - roles
  verbs:
  - create
  - get
  - list
  - update
  - delete
  - watch
  - bind
  - escalate
- apiGroups:
  - apps
  resources:
  - deployments
  - daemonsets
  - replicasets
  verbs:
  - create
  - get
  - list
  - patch
  - update
  - delete
  - watch
- apiGroups:
  - apps
  resourceNames:
  - tigera-operator
  resources:
  - deployments/finalizers
  verbs:
  - update
- apiGroups:
  - operator.tigera.io
  resources:
  - '*'
  verbs:
  - create
  - get
  - list
  - update
  - patch
  - delete
  - watch
- apiGroups:
  - crd.projectcalico.org
  resources:
  - '*'
  verbs:
  - create
  - get
  - list
  - update
  - delete
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tigera-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tigera-operator
subjects:
- kind: ServiceAccount
  name: tigera-operator
  namespace: tigera-operator
EOF
        
        # Create custom-resources.yaml manually
        cat > custom-resources.yaml << 'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
        
        download_success=true
        log "Created Calico manifests manually"
    fi
    
    if [[ "$download_success" != "true" ]]; then
        error "Failed to obtain Calico manifests"
    fi
    
    # Modify custom-resources for our pod CIDR
    sed -i "s|192.168.0.0/16|${POD_NETWORK_CIDR}|g" custom-resources.yaml
    
    # Apply Tigera operator
    kubectl create -f tigera-operator.yaml
    
    # Wait for operator to be ready
    log "Waiting for Tigera operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/tigera-operator -n tigera-operator
    
    # Apply custom resources
    kubectl apply -f custom-resources.yaml
    
    # Wait for Calico to be ready
    log "Waiting for Calico pods to be ready..."
    kubectl wait --for=condition=ready --timeout=600s pod -l app.kubernetes.io/name=calico-node -n calico-system
    
    # Clean up
    cd /
    rm -rf /tmp/calico-manifests
    
    success "Calico CNI installed and configured"
}

remove_control_plane_taints() {
    log "Removing control plane taints to allow workload scheduling..."
    
    # Remove taints from all control plane nodes (currently just this one)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true
    kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || true
    
    success "Control plane taints removed"
}

install_metrics_server() {
    log "Installing metrics server..."
    
    # Download and apply metrics server
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Patch metrics server for development environment
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }
    ]'
    
    success "Metrics server installed"
}

install_helm() {
    log "Installing Helm package manager..."
    
    # Download and install Helm
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    
    # Add common Helm repositories
    helm repo add stable https://charts.helm.sh/stable
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    success "Helm installed and repositories added"
}

create_storage_directories() {
    log "Creating storage directories on k8s-cp1..."
    
    # Create storage directories for HA setup
    mkdir -p /mnt/k8s-storage/{fast-ssd,standard,backup,logs}
    mkdir -p /mnt/k8s-storage/fast-ssd/{postgresql,redis,prometheus,grafana,loki}
    mkdir -p /mnt/k8s-storage/standard/{general,temp}
    mkdir -p /mnt/k8s-storage/backup/{databases,configs,volumes}
    mkdir -p /mnt/k8s-storage/logs/{applications,system}
    
    # Set permissions
    chmod 755 /mnt/k8s-storage
    chmod 755 /mnt/k8s-storage/*
    
    success "Storage directories created"
}

generate_join_commands() {
    log "Generating join commands for other control planes..."
    
    # Create directory for join information
    mkdir -p /opt/kubernetes/join-info
    
    # Generate new bootstrap token
    local token=$(kubeadm token create --ttl 24h)
    local ca_cert_hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    local cert_key=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
    
    # Create join command for control planes
    cat > /opt/kubernetes/join-info/control-plane-join.sh << EOF
#!/bin/bash
# Join command for additional control planes (k8s-cp2, k8s-cp3, k8s-cp4)
# Run this on each additional control plane server

kubeadm join $VIP:6443 \\
    --token $token \\
    --discovery-token-ca-cert-hash sha256:$ca_cert_hash \\
    --control-plane \\
    --certificate-key $cert_key \\
    --cri-socket unix:///var/run/containerd/containerd.sock
EOF
    
    chmod +x /opt/kubernetes/join-info/control-plane-join.sh
    
    # Create join command for worker nodes (if any)
    cat > /opt/kubernetes/join-info/worker-join.sh << EOF
#!/bin/bash
# Join command for worker nodes
# Run this on any additional worker nodes

kubeadm join $VIP:6443 \\
    --token $token \\
    --discovery-token-ca-cert-hash sha256:$ca_cert_hash \\
    --cri-socket unix:///var/run/containerd/containerd.sock
EOF
    
    chmod +x /opt/kubernetes/join-info/worker-join.sh
    
    # Save join information
    cat > /opt/kubernetes/join-info/join-info.txt << EOF
# Kubernetes HA Cluster Join Information
Generated: $(date)
Cluster: $CLUSTER_NAME
VIP: $VIP

# Token Information
Token: $token
CA Cert Hash: sha256:$ca_cert_hash
Certificate Key: $cert_key

# Control Plane Join Command:
kubeadm join $VIP:6443 --token $token --discovery-token-ca-cert-hash sha256:$ca_cert_hash --control-plane --certificate-key $cert_key --cri-socket unix:///var/run/containerd/containerd.sock

# Worker Join Command:
kubeadm join $VIP:6443 --token $token --discovery-token-ca-cert-hash sha256:$ca_cert_hash --cri-socket unix:///var/run/containerd/containerd.sock

# Token expires in 24 hours. To generate a new token:
# kubeadm token create --ttl 24h

# To get CA cert hash:
# openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'

# To upload certificates and get new certificate key:
# kubeadm init phase upload-certs --upload-certs
EOF
    
    success "Join commands generated and saved to /opt/kubernetes/join-info/"
}

create_backup_script() {
    log "Creating etcd backup script..."
    
    cat > /opt/kubernetes/etcd-backup.sh << EOF
#!/bin/bash
# etcd Backup Script for HA Kubernetes Cluster
# Run this script daily to backup etcd data

BACKUP_DIR="/opt/kubernetes/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/etcd-snapshot-\$DATE.db"

# Create backup directory
mkdir -p \$BACKUP_DIR

# Take etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save \$BACKUP_FILE \\
    --endpoints=https://127.0.0.1:2379 \\
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
    --cert=/etc/kubernetes/pki/etcd/server.crt \\
    --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status \$BACKUP_FILE \\
    --write-out=table

# Keep only last 7 days of backups
find \$BACKUP_DIR -name "etcd-snapshot-*.db" -mtime +7 -delete

echo "etcd backup completed: \$BACKUP_FILE"
EOF
    
    chmod +x /opt/kubernetes/etcd-backup.sh
    
    # Create cron job for daily backups
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/kubernetes/etcd-backup.sh >> /var/log/etcd-backup.log 2>&1") | crontab -
    
    success "etcd backup script created and scheduled"
}

verify_cluster_health() {
    log "Verifying cluster health..."
    
    # Check nodes
    local nodes_ready=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ $nodes_ready -lt 1 ]]; then
        error "No nodes in Ready state"
    fi
    
    # Check system pods
    local system_pods_running=$(kubectl get pods -n kube-system --no-headers | grep -c "Running")
    if [[ $system_pods_running -lt 5 ]]; then
        warning "Some system pods may not be running yet"
    fi
    
    # Check API server connectivity via VIP
    if ! kubectl --server="https://$VIP:6443" get nodes &> /dev/null; then
        warning "API server not accessible via VIP (this may be normal during initial setup)"
    fi
    
    success "Cluster health verification completed"
}

restart_ha_services() {
    log "Updating HA services for Kubernetes integration..."
    
    # Ensure Keepalived is running and VIP is assigned
    if ! systemctl is-active --quiet keepalived; then
        systemctl start keepalived
        sleep 10
    fi
    
    # Update HAProxy configuration to use VIP:6443 for API frontend
    log "Updating HAProxy configuration for Kubernetes API load balancing..."
    
    # Stop HAProxy temporarily
    systemctl stop haproxy 2>/dev/null || true
    
    # Update HAProxy config to use VIP and proper port
    sed -i 's/bind.*16443/bind '"$VIP"':6443/' /etc/haproxy/haproxy.cfg
    sed -i 's/bind 127.0.0.1:16443/bind 127.0.0.1:6443/' /etc/haproxy/haproxy.cfg
    
    # Validate and start HAProxy
    if haproxy -f /etc/haproxy/haproxy.cfg -c; then
        systemctl start haproxy
        success "HAProxy updated and started for Kubernetes integration"
    else
        warning "HAProxy configuration validation failed, but continuing..."
    fi
    
    # Test VIP accessibility
    if curl -k "https://$VIP:6443/healthz" &>/dev/null; then
        success "Kubernetes API accessible via VIP"
    else
        warning "VIP may take time to propagate"
    fi
    
    success "HA services updated for Kubernetes integration"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Kubernetes Cluster Initialization Completed!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Cluster Information ==="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Kubernetes Version: v$KUBE_VERSION"
    echo "Control Plane Endpoint: $VIP:6443"
    echo "Pod Network CIDR: $POD_NETWORK_CIDR"
    echo "Service CIDR: $SERVICE_CIDR"
    echo
    echo "=== Node Status ==="
    kubectl get nodes -o wide
    echo
    echo "=== System Pods ==="
    kubectl get pods -n kube-system
    echo
    echo "=== Calico Status ==="
    kubectl get pods -n calico-system 2>/dev/null || echo "Calico pods starting..."
    echo
    echo "=== Join Information ==="
    echo "Join commands saved to: /opt/kubernetes/join-info/"
    echo "• control-plane-join.sh - For k8s-cp2, k8s-cp3, k8s-cp4"
    echo "• worker-join.sh - For any additional worker nodes"
    echo "• join-info.txt - Complete join information"
    echo
    echo "=== Important Files ==="
    echo "• kubectl config: /root/.kube/config"
    echo "• etcd backup script: /opt/kubernetes/etcd-backup.sh"
    echo "• Cluster logs: $LOG_FILE"
    echo
    echo "=== Next Steps ==="
    echo "1. Copy /opt/kubernetes/join-info/control-plane-join.sh to k8s-cp2, k8s-cp3, k8s-cp4"
    echo "2. Run 04-ha-cluster-join.sh on each additional control plane"
    echo "3. Verify all nodes are Ready: kubectl get nodes"
    echo "4. Run 05-ha-storage-setup.sh to configure distributed storage"
    echo "5. Run 06-ha-ingress-setup.sh to setup ingress controller"
    echo
    echo "=== Useful Commands ==="
    echo "• Check cluster: kubectl cluster-info"
    echo "• Get nodes: kubectl get nodes -o wide"
    echo "• Get pods: kubectl get pods -A"
    echo "• Check etcd: kubectl get pods -n kube-system | grep etcd"
    echo "• Test VIP: kubectl --server=https://$VIP:6443 get nodes"
    echo
    echo -e "${GREEN}k8s-cp1 initialization completed successfully!${NC}"
    echo -e "${YELLOW}Remember to join the other control planes before proceeding!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    wait_for_vip
    
    log "Starting HA Kubernetes cluster initialization on k8s-cp1..."
    
    # Cluster initialization
    create_kubeadm_config
    pre_pull_images
    initialize_cluster
    configure_kubectl
    wait_for_api_server
    
    # Network and add-ons
    install_calico_cni
    remove_control_plane_taints
    install_metrics_server
    install_helm
    
    # HA setup
    create_storage_directories
    generate_join_commands
    create_backup_script
    
    # Verification
    verify_cluster_health
    
    # Restart HA services
    restart_ha_services
    
    show_completion_info
    
    success "HA Kubernetes cluster initialization completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script initializes the first control plane of an HA Kubernetes cluster."
        echo "Run this script ONLY on k8s-cp1 after load balancer setup."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac