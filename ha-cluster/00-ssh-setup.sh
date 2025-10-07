#!/bin/bash

# SSH Setup Script for HA Kubernetes Cluster
# Run this script on k8s-cp1 BEFORE running the master deployment script
# Purpose: Configure SSH key authentication between all cluster nodes

set -euo pipefail

LOG_FILE="/var/log/ssh-setup.log"

# Server configuration
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
    echo "    SSH Key Setup for HA Kubernetes Cluster"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will:"
    echo "• Generate SSH keys on k8s-cp1"
    echo "• Copy public key to all other servers"
    echo "• Copy deployment scripts to all servers"
    echo "• Test SSH connectivity"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_hostname() {
    local hostname=$(hostname)
    if [[ "$hostname" != "k8s-cp1" ]]; then
        error "This script should only be run on k8s-cp1. Current hostname: $hostname"
    fi
    success "Running on correct server: k8s-cp1"
}

get_root_password() {
    echo "=== Root Password Setup ==="
    echo "You need the root password for the other servers to set up SSH keys."
    echo
    read -s -p "Enter root password for k8s-cp2, k8s-cp3, k8s-cp4: " ROOT_PASSWORD
    echo
    echo
    
    if [[ -z "$ROOT_PASSWORD" ]]; then
        error "Root password cannot be empty"
    fi
    
    success "Root password collected"
}

install_sshpass() {
    log "Installing sshpass for automated SSH key distribution..."
    
    apt update
    apt install -y sshpass
    
    success "sshpass installed"
}

generate_ssh_keys() {
    log "Generating SSH key pair for root user..."
    
    # Create .ssh directory if it doesn't exist
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    # Generate SSH key if it doesn't exist
    if [[ ! -f /root/.ssh/id_rsa ]]; then
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "root@k8s-cp1"
        success "SSH key pair generated"
    else
        success "SSH key pair already exists"
    fi
    
    # Set proper permissions
    chmod 600 /root/.ssh/id_rsa
    chmod 644 /root/.ssh/id_rsa.pub
}

test_server_connectivity() {
    log "Testing basic connectivity to all servers..."
    
    local failed_servers=()
    
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            continue
        fi
        
        local node_ip="${CONTROL_PLANES[$node]}"
        log "Testing connectivity to $node ($node_ip)..."
        
        if ping -c 2 -W 5 "$node_ip" &>/dev/null; then
            success "Connectivity to $node: OK"
        else
            warning "Cannot ping $node ($node_ip)"
            failed_servers+=("$node")
        fi
    done
    
    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        error "Cannot reach servers: ${failed_servers[*]}. Check network configuration."
    fi
}

copy_ssh_keys() {
    log "Copying SSH public key to all servers..."
    
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            continue
        fi
        
        local node_ip="${CONTROL_PLANES[$node]}"
        log "Copying SSH key to $node ($node_ip)..."
        
        # Copy SSH key using sshpass
        if sshpass -p "$ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no root@"$node_ip" &>/dev/null; then
            success "SSH key copied to $node"
        else
            error "Failed to copy SSH key to $node. Check password and connectivity."
        fi
    done
}

test_ssh_connectivity() {
    log "Testing SSH key authentication..."
    
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            continue
        fi
        
        local node_ip="${CONTROL_PLANES[$node]}"
        log "Testing SSH to $node ($node_ip)..."
        
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node_ip" "echo 'SSH test successful from k8s-cp1'" &>/dev/null; then
            success "SSH authentication to $node: OK"
        else
            error "SSH authentication failed to $node"
        fi
    done
}

copy_scripts_to_servers() {
    log "Copying deployment scripts to all servers..."
    
    local script_dir="$(dirname "$(realpath "$0")")"
    
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            continue
        fi
        
        local node_ip="${CONTROL_PLANES[$node]}"
        log "Copying scripts to $node ($node_ip)..."
        
        # Create remote directory
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node_ip" "mkdir -p /root/ha-cluster" &>/dev/null; then
            # Copy all scripts
            if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$script_dir"/*.sh root@"$node_ip":/root/ha-cluster/ &>/dev/null; then
                # Make scripts executable
                if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node_ip" "chmod +x /root/ha-cluster/*.sh" &>/dev/null; then
                    success "Scripts copied to $node"
                else
                    error "Failed to make scripts executable on $node"
                fi
            else
                error "Failed to copy scripts to $node"
            fi
        else
            error "Failed to create directory on $node"
        fi
    done
}

setup_known_hosts() {
    log "Setting up known_hosts for all servers..."
    
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        
        # Add to known_hosts to avoid host key verification prompts
        ssh-keyscan -H "$node_ip" >> /root/.ssh/known_hosts 2>/dev/null || true
        if [[ "$node" != "k8s-cp1" ]]; then
            ssh-keyscan -H "$node" >> /root/.ssh/known_hosts 2>/dev/null || true
        fi
    done
    
    success "Known hosts configured"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 SSH Setup Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Configuration Summary ==="
    echo "SSH keys generated: /root/.ssh/id_rsa"
    echo "Public key distributed to all servers"
    echo "Scripts copied to all servers: /root/ha-cluster/"
    echo
    echo "=== SSH Connectivity Test ==="
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            echo "✓ $node (local)"
        else
            local node_ip="${CONTROL_PLANES[$node]}"
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$node_ip" "echo 'test'" &>/dev/null; then
                echo "✓ $node ($node_ip) - SSH OK"
            else
                echo "✗ $node ($node_ip) - SSH FAILED"
            fi
        fi
    done
    echo
    echo "=== Next Steps ==="
    echo "1. Verify all servers show 'SSH OK' above"
    echo "2. Run the master deployment script:"
    echo "   sudo ./09-ha-master-deploy.sh"
    echo
    echo "=== Useful Commands ==="
    echo "• Test SSH to k8s-cp2: ssh root@10.255.254.11"
    echo "• Test SSH to k8s-cp3: ssh root@10.255.254.12"
    echo "• Test SSH to k8s-cp4: ssh root@10.255.254.13"
    echo "• View SSH logs: tail -f $LOG_FILE"
    echo
    echo -e "${GREEN}SSH setup completed! Ready for cluster deployment.${NC}"
}

main() {
    banner
    check_root
    check_hostname
    
    log "Starting SSH setup for HA Kubernetes cluster..."
    
    # Setup SSH authentication
    get_root_password
    install_sshpass
    generate_ssh_keys
    test_server_connectivity
    copy_ssh_keys
    setup_known_hosts
    test_ssh_connectivity
    
    # Distribute scripts
    copy_scripts_to_servers
    
    show_completion_info
    
    success "SSH setup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script sets up SSH key authentication between k8s-cp1 and all other"
        echo "cluster nodes, enabling automated deployment."
        echo
        echo "Prerequisites:"
        echo "• Run this script on k8s-cp1"
        echo "• Root password for k8s-cp2, k8s-cp3, k8s-cp4"
        echo "• Network connectivity between all servers"
        echo
        echo "What this script does:"
        echo "• Generates SSH key pair on k8s-cp1"
        echo "• Copies public key to all other servers"
        echo "• Copies deployment scripts to all servers"
        echo "• Tests SSH connectivity"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac