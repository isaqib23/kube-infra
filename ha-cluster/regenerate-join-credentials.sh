#!/bin/bash

# Regenerate Join Credentials Script
# Run this on k8s-cp1 to generate fresh certificates and tokens for joining nodes

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

banner() {
    echo -e "${CYAN}"
    echo "================================================================"
    echo "    Regenerate Join Credentials for Control Plane Nodes"
    echo "================================================================"
    echo -e "${NC}"
    echo "This script generates fresh certificates and tokens for"
    echo "joining additional control plane nodes to the cluster."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    local hostname=$(hostname)
    if [[ "$hostname" != "k8s-cp1" ]]; then
        error "This script should only be run on k8s-cp1. Current hostname: $hostname"
    fi

    if ! kubectl cluster-info &>/dev/null; then
        error "kubectl cannot connect to cluster. Ensure cluster is initialized"
    fi

    success "Prerequisites check passed"
}

regenerate_certificates() {
    log "Regenerating certificate key..."
    echo

    # Upload new certificates
    local cert_output=$(kubeadm init phase upload-certs --upload-certs 2>&1)

    # Extract certificate key
    CERT_KEY=$(echo "$cert_output" | grep -A 1 "Using certificate key:" | tail -1)

    if [[ -z "$CERT_KEY" ]]; then
        error "Failed to generate certificate key"
    fi

    success "New certificate key generated (valid for 2 hours)"
    echo -e "${GREEN}Certificate Key: $CERT_KEY${NC}"
    echo
}

check_token_validity() {
    log "Checking existing tokens..."
    echo

    # List existing tokens
    kubeadm token list

    echo
    read -p "Do you want to create a new token? [Y/n]: " CREATE_TOKEN
    CREATE_TOKEN=${CREATE_TOKEN:-y}

    if [[ $CREATE_TOKEN =~ ^[Yy]$ ]]; then
        create_new_token
    else
        echo "Enter the existing token to use:"
        read -p "Token: " JOIN_TOKEN

        if [[ -z "$JOIN_TOKEN" ]]; then
            error "Token is required"
        fi
    fi
}

create_new_token() {
    log "Creating new join token (valid for 24 hours)..."

    JOIN_TOKEN=$(kubeadm token create --ttl 24h --print-join-command 2>/dev/null | grep -o 'token [^ ]*' | awk '{print $2}')

    if [[ -z "$JOIN_TOKEN" ]]; then
        error "Failed to create token"
    fi

    success "New token created: $JOIN_TOKEN"
    echo
}

get_ca_cert_hash() {
    log "Getting CA certificate hash..."

    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
        openssl rsa -pubin -outform der 2>/dev/null | \
        openssl dgst -sha256 -hex | sed 's/^.* //')

    if [[ -z "$CA_CERT_HASH" ]]; then
        error "Failed to get CA cert hash"
    fi

    CA_CERT_HASH="sha256:$CA_CERT_HASH"
    success "CA cert hash: $CA_CERT_HASH"
    echo
}

get_vip() {
    VIP="10.255.254.100"
    log "Using VIP: $VIP"
    echo
}

create_join_files() {
    log "Creating join information files..."

    # Create join-info directory
    mkdir -p /opt/kubernetes/join-info

    # Create control plane join script
    cat > /opt/kubernetes/join-info/control-plane-join.sh << EOF
#!/bin/bash
kubeadm join $VIP:6443 \\
    --token $JOIN_TOKEN \\
    --discovery-token-ca-cert-hash $CA_CERT_HASH \\
    --control-plane \\
    --certificate-key $CERT_KEY \\
    --cri-socket unix:///var/run/containerd/containerd.sock
EOF

    chmod +x /opt/kubernetes/join-info/control-plane-join.sh

    # Create text info file
    cat > /opt/kubernetes/join-info/join-info.txt << EOF
HA Kubernetes Cluster Join Information
Generated: $(date)
Valid until: $(date -d '+2 hours' 2>/dev/null || date -v+2H)

Control Plane Endpoint (VIP): $VIP:6443
Token: $JOIN_TOKEN
Token Expiry: 24 hours from now
CA Cert Hash: $CA_CERT_HASH
Certificate Key: $CERT_KEY
Certificate Key Expiry: 2 hours from now

For Control Plane Nodes (k8s-cp2, k8s-cp3, k8s-cp4):
1. Copy /opt/kubernetes/join-info/control-plane-join.sh to /tmp/ on the target node
2. Run: sudo ./04-ha-cluster-join.sh

Or manually execute:
kubeadm join $VIP:6443 \\
    --token $JOIN_TOKEN \\
    --discovery-token-ca-cert-hash $CA_CERT_HASH \\
    --control-plane \\
    --certificate-key $CERT_KEY \\
    --cri-socket unix:///var/run/containerd/containerd.sock
EOF

    success "Join information saved to /opt/kubernetes/join-info/"
    echo
}

copy_to_nodes() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Copy Join Script to Other Nodes${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo "To deploy join information to other nodes, run:"
    echo
    echo -e "${GREEN}  # For k8s-cp2:${NC}"
    echo "  scp /opt/kubernetes/join-info/control-plane-join.sh root@10.255.254.11:/tmp/"
    echo
    echo -e "${GREEN}  # For k8s-cp3:${NC}"
    echo "  scp /opt/kubernetes/join-info/control-plane-join.sh root@10.255.254.12:/tmp/"
    echo
    echo -e "${GREEN}  # For k8s-cp4:${NC}"
    echo "  scp /opt/kubernetes/join-info/control-plane-join.sh root@10.255.254.13:/tmp/"
    echo
}

show_summary() {
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Fresh Join Credentials Generated!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo "Files created:"
    echo "  • /opt/kubernetes/join-info/control-plane-join.sh"
    echo "  • /opt/kubernetes/join-info/join-info.txt"
    echo
    echo "Credentials:"
    echo "  • VIP: $VIP"
    echo "  • Token: $JOIN_TOKEN (valid: 24h)"
    echo "  • Certificate Key: $CERT_KEY (valid: 2h)"
    echo "  • CA Hash: $CA_CERT_HASH"
    echo
    echo -e "${YELLOW}IMPORTANT: Certificate key expires in 2 hours!${NC}"
    echo "Complete all control plane joins within this time window."
    echo
    echo "Next Steps:"
    echo "1. Copy join script to target nodes (see commands above)"
    echo "2. On each joining node, ensure it's clean:"
    echo "   sudo ./quick-reset-and-join.sh (if needed)"
    echo "3. Run the join script:"
    echo "   sudo ./04-ha-cluster-join.sh"
    echo
}

main() {
    banner
    check_root
    check_prerequisites

    log "Starting credential regeneration process..."
    echo

    get_vip
    regenerate_certificates
    check_token_validity
    get_ca_cert_hash
    create_join_files
    copy_to_nodes
    show_summary

    success "Credential regeneration completed successfully!"
}

main "$@"
