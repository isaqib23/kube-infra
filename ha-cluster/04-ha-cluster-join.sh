#!/bin/bash

# HA Kubernetes Cluster Join Script
# Run this script on k8s-cp2, k8s-cp3, and k8s-cp4
# Purpose: Join additional control planes to the HA cluster

set -euo pipefail

LOG_FILE="/var/log/ha-cluster-join.log"

# Cluster configuration
VIP="10.255.254.100"
CLUSTER_NAME="ha-k8s-cluster"

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
    echo "    HA Kubernetes Cluster Join - Control Plane"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script joins an additional control plane node to the"
    echo "existing HA Kubernetes cluster."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Get current hostname
    local hostname=$(hostname)
    
    # Verify this is NOT k8s-cp1
    if [[ "$hostname" == "k8s-cp1" ]]; then
        error "This script should NOT be run on k8s-cp1. Use 03-ha-cluster-init.sh instead"
    fi
    
    # Verify this is one of the expected control planes
    if [[ ! ${CONTROL_PLANES[$hostname]+_} ]]; then
        error "Unknown hostname: $hostname. Expected one of: k8s-cp2, k8s-cp3, k8s-cp4"
    fi
    
    # Check if kubeadm is installed
    if ! command -v kubeadm &> /dev/null; then
        error "kubeadm is not installed. Run 01-server-preparation.sh first"
    fi
    
    # Check if HAProxy and Keepalived are installed
    if ! command -v haproxy &> /dev/null; then
        error "HAProxy is not installed. Run 02-ha-loadbalancer-setup.sh first"
    fi

    if ! command -v keepalived &> /dev/null; then
        error "Keepalived is not installed. Run 02-ha-loadbalancer-setup.sh first"
    fi

    # Note: HAProxy may be disabled on some nodes to avoid VIP:6443 conflicts
    # This is normal and expected
    
    # Ensure Keepalived is running for VIP management
    if ! systemctl is-active --quiet keepalived; then
        log "Starting Keepalived for VIP management..."
        systemctl start keepalived
        sleep 5
    fi
    
    # Check if VIP is accessible
    if ! ping -c 3 "$VIP" &> /dev/null; then
        error "Cannot reach VIP $VIP. Ensure k8s-cp1 is initialized and VIP is active"
    fi
    
    success "Prerequisites check passed for $hostname"
}

get_join_information() {
    log "Getting join information..."

    # Try to get join info automatically if available
    if [[ -f /tmp/control-plane-join.sh ]]; then
        log "Found join script in /tmp/control-plane-join.sh"

        # Parse the join command to extract parameters (handles multi-line)
        # Extract token
        JOIN_TOKEN=$(grep -A 10 "kubeadm join" /tmp/control-plane-join.sh | grep -o -- '--token [^ \\]*' | awk '{print $2}')

        # Extract CA cert hash
        CA_CERT_HASH=$(grep -A 10 "kubeadm join" /tmp/control-plane-join.sh | grep -o -- '--discovery-token-ca-cert-hash [^ \\]*' | awk '{print $2}')

        # Extract certificate key
        CERT_KEY=$(grep -A 10 "kubeadm join" /tmp/control-plane-join.sh | grep -o -- '--certificate-key [^ \\]*' | awk '{print $2}')

        if [[ -n "$JOIN_TOKEN" && -n "$CA_CERT_HASH" && -n "$CERT_KEY" ]]; then
            success "Automatically extracted join information from /tmp/control-plane-join.sh"
            log "Token: ${JOIN_TOKEN}"
            log "CA Hash: ${CA_CERT_HASH:0:30}..."
            log "Cert Key: ${CERT_KEY:0:30}..."
            return 0
        else
            warning "Could not parse join information from file"
            log "Token found: ${JOIN_TOKEN:-EMPTY}"
            log "CA Hash found: ${CA_CERT_HASH:-EMPTY}"
            log "Cert Key found: ${CERT_KEY:-EMPTY}"
        fi
    fi

    # If auto-extraction failed, ask for manual input
    echo
    echo "=== Join Information Required ==="
    echo "You need the join command from k8s-cp1."
    echo "This can be found in /opt/kubernetes/join-info/control-plane-join.sh on k8s-cp1"
    echo
    echo "Or provide the join parameters manually:"
    echo
    get_manual_join_info
}

get_manual_join_info() {
    echo "Please provide the following information from k8s-cp1:"
    echo
    
    read -p "Enter join token: " JOIN_TOKEN
    read -p "Enter CA cert hash (sha256:...): " CA_CERT_HASH
    read -p "Enter certificate key: " CERT_KEY
    
    if [[ -z "$JOIN_TOKEN" || -z "$CA_CERT_HASH" || -z "$CERT_KEY" ]]; then
        error "All join parameters are required"
    fi
    
    # Ensure CA cert hash has sha256: prefix
    if [[ ! "$CA_CERT_HASH" =~ ^sha256: ]]; then
        CA_CERT_HASH="sha256:$CA_CERT_HASH"
    fi
    
    log "Join information collected manually"
}

test_cluster_connectivity() {
    log "Testing cluster connectivity..."
    
    # Test API server connectivity via VIP
    if ! curl -k "https://$VIP:6443/healthz" &> /dev/null; then
        error "Cannot connect to Kubernetes API at $VIP:6443"
    fi
    
    success "Cluster connectivity verified"
}

pre_pull_images() {
    log "Pre-pulling Kubernetes images..."
    
    # Pull images to speed up join process
    kubeadm config images pull --kubernetes-version=$(kubeadm version -o short)
    
    success "Kubernetes images pre-pulled"
}

join_cluster() {
    log "Joining cluster as control plane..."
    
    local hostname=$(hostname)
    local server_ip=${CONTROL_PLANES[$hostname]}
    
    # Create join command
    local join_command="kubeadm join $VIP:6443 \
        --token $JOIN_TOKEN \
        --discovery-token-ca-cert-hash $CA_CERT_HASH \
        --control-plane \
        --certificate-key $CERT_KEY \
        --apiserver-advertise-address $server_ip \
        --cri-socket unix:///var/run/containerd/containerd.sock \
        --v=5"
    
    log "Executing join command..."
    eval $join_command
    
    success "Successfully joined cluster as control plane"
}

configure_kubectl() {
    log "Configuring kubectl..."

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

    # Configure kubectl for rao user if exists
    if id "rao" &>/dev/null; then
        log "Configuring kubectl for rao user..."
        mkdir -p /home/rao/.kube
        cp -i /etc/kubernetes/admin.conf /home/rao/.kube/config
        chown rao:rao /home/rao/.kube/config
    fi

    success "kubectl configured"
}

wait_for_node_ready() {
    log "Waiting for node to become Ready..."
    
    local hostname=$(hostname)
    local timeout=300
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        local node_status=$(kubectl get node "$hostname" --no-headers 2>/dev/null | awk '{print $2}' || echo "NotFound")
        
        if [[ "$node_status" == "Ready" ]]; then
            success "Node $hostname is Ready"
            return 0
        fi
        
        sleep 10
        ((counter+=10))
        echo -n "."
    done
    
    error "Node $hostname did not become Ready within $timeout seconds"
}

remove_control_plane_taints() {
    log "Removing control plane taints to allow workload scheduling..."
    
    local hostname=$(hostname)
    
    # Remove taints from this control plane node
    kubectl taint node "$hostname" node-role.kubernetes.io/control-plane:NoSchedule- || true
    kubectl taint node "$hostname" node-role.kubernetes.io/master:NoSchedule- || true
    
    success "Control plane taints removed from $hostname"
}

verify_etcd_cluster() {
    log "Verifying etcd cluster health..."
    
    # Wait for etcd pod to be running
    local timeout=180
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if kubectl get pod -n kube-system -l component=etcd,tier=control-plane --field-selector spec.nodeName=$(hostname) --no-headers 2>/dev/null | grep -q "Running"; then
            break
        fi
        sleep 5
        ((counter+=5))
        echo -n "."
    done
    
    if [[ $counter -ge $timeout ]]; then
        error "etcd pod did not start within $timeout seconds"
    fi
    
    # Check etcd cluster member list
    local etcd_members=$(ETCDCTL_API=3 etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list 2>/dev/null | wc -l || echo "0")
    
    if [[ $etcd_members -gt 0 ]]; then
        success "etcd cluster health verified ($etcd_members members)"
    else
        warning "Could not verify etcd cluster health (may be normal during startup)"
    fi
}

verify_cluster_status() {
    log "Verifying cluster status..."
    
    # Check if this node is listed in cluster
    local hostname=$(hostname)
    if ! kubectl get nodes | grep -q "$hostname"; then
        error "Node $hostname not found in cluster"
    fi
    
    # Check control plane pods
    local cp_pods_running=$(kubectl get pods -n kube-system -l tier=control-plane --field-selector spec.nodeName=$hostname --no-headers | grep -c "Running" || echo "0")
    
    if [[ $cp_pods_running -ge 3 ]]; then
        success "Control plane pods running: $cp_pods_running"
    else
        warning "Some control plane pods may still be starting"
    fi
    
    # Test API access via VIP
    if kubectl --server="https://$VIP:6443" get nodes &> /dev/null; then
        success "API server accessible via VIP"
    else
        warning "API server not yet accessible via VIP (may need time to propagate)"
    fi
    
    success "Cluster status verification completed"
}

create_storage_directories() {
    log "Creating storage directories..."
    
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

update_haproxy_configuration() {
    log "Checking HAProxy configuration for Kubernetes integration..."

    # Check if kube-apiserver is listening on port 6443
    if netstat -tlnp 2>/dev/null | grep -q ":6443.*kube-apiserver" || \
       ss -tlnp 2>/dev/null | grep -q ":6443.*kube-apiserver"; then

        warning "kube-apiserver is listening on *:6443"

        # Check if this node has the VIP
        if ip addr show | grep -q "$VIP"; then
            warning "This node has VIP - HAProxy would conflict with kube-apiserver"
            log "Disabling HAProxy to avoid port conflict..."
            systemctl stop haproxy 2>/dev/null || true
            systemctl disable haproxy 2>/dev/null || true
            success "HAProxy disabled (node has VIP, kube-apiserver handles it)"
        else
            log "This node does NOT have VIP - HAProxy can run optionally"
            log "Keeping HAProxy disabled for consistency"
            systemctl stop haproxy 2>/dev/null || true
            systemctl disable haproxy 2>/dev/null || true
            success "HAProxy disabled (optional - kube-apiserver + keepalived is sufficient)"
        fi
    else
        # kube-apiserver not detected on 6443 yet (shouldn't happen but handle it)
        warning "kube-apiserver not detected on port 6443, keeping HAProxy as-is"
    fi

    # Always verify API is accessible
    if curl -k "https://$VIP:6443/healthz" &>/dev/null; then
        success "Kubernetes API accessible via VIP"
    else
        warning "API not yet accessible via VIP (may need time to propagate)"
    fi
}

setup_etcd_backup() {
    log "Setting up etcd backup script..."
    
    mkdir -p /opt/kubernetes/backups
    
    cat > /opt/kubernetes/etcd-backup.sh << EOF
#!/bin/bash
# etcd Backup Script for HA Kubernetes Cluster
# This runs on $(hostname)

BACKUP_DIR="/opt/kubernetes/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/etcd-snapshot-$(hostname)-\$DATE.db"

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
find \$BACKUP_DIR -name "etcd-snapshot-$(hostname)-*.db" -mtime +7 -delete

echo "etcd backup completed on $(hostname): \$BACKUP_FILE"
EOF
    
    chmod +x /opt/kubernetes/etcd-backup.sh
    
    success "etcd backup script created"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 Control Plane Join Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Node Information ==="
    echo "Hostname: $(hostname)"
    echo "IP Address: ${CONTROL_PLANES[$(hostname)]}"
    echo "Role: Control Plane + Worker"
    echo
    echo "=== Cluster Status ==="
    kubectl get nodes -o wide
    echo
    echo "=== Control Plane Pods on This Node ==="
    kubectl get pods -n kube-system -l tier=control-plane --field-selector spec.nodeName=$(hostname) -o wide
    echo
    echo "=== etcd Members ==="
    ETCDCTL_API=3 etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list --write-out=table 2>/dev/null || echo "etcd member list not available yet"
    echo
    echo "=== Next Steps ==="
    echo "1. Repeat this process on remaining control planes (if any)"
    echo "2. Verify all nodes are Ready: kubectl get nodes"
    echo "3. Check etcd cluster health: kubectl get pods -n kube-system | grep etcd"
    echo "4. Proceed with storage setup: 05-ha-storage-setup.sh (run on k8s-cp1)"
    echo
    echo "=== Useful Commands ==="
    echo "• Check this node: kubectl get node $(hostname) -o wide"
    echo "• Check all nodes: kubectl get nodes"
    echo "• Check etcd health: kubectl get pods -n kube-system | grep etcd"
    echo "• Test VIP access: kubectl --server=https://$VIP:6443 get nodes"
    echo "• View logs: journalctl -u kubelet -f"
    echo
    echo -e "${GREEN}$(hostname) successfully joined the HA cluster!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    
    local hostname=$(hostname)
    log "Starting cluster join process for $hostname..."
    
    # Join preparation
    get_join_information
    test_cluster_connectivity
    pre_pull_images
    
    # Join cluster
    join_cluster
    configure_kubectl
    wait_for_node_ready
    remove_control_plane_taints
    
    # Verification and setup
    verify_etcd_cluster
    verify_cluster_status
    create_storage_directories
    update_haproxy_configuration
    setup_etcd_backup
    
    show_completion_info
    
    success "Control plane join completed successfully on $hostname!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script joins additional control planes to an HA Kubernetes cluster."
        echo "Run this script on k8s-cp2, k8s-cp3, and k8s-cp4 after k8s-cp1 initialization."
        echo
        echo "Before running, ensure you have the join information from k8s-cp1:"
        echo "• Copy /opt/kubernetes/join-info/control-plane-join.sh from k8s-cp1 to /tmp/ on this server"
        echo "• Or prepare the join token, CA cert hash, and certificate key manually"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac