#!/bin/bash

# Install permanent swap disable on all Kubernetes nodes
# Run this script from k8s-cp1 after copying the files to all nodes

set -e

# Colors for output
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

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODES=(
    "10.255.254.10:k8s-cp1"
    "10.255.254.11:k8s-cp2"
    "10.255.254.12:k8s-cp3"
    "10.255.254.13:k8s-cp4"
)

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    Install Permanent Swap Disable on All Nodes"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will install the permanent swap disable mechanism"
    echo "on all 4 Kubernetes nodes to prevent swap from being re-enabled"
    echo "after server reboots."
    echo
}

install_on_local_node() {
    local node_name="$1"

    log "Installing permanent swap disable on $node_name (local)..."

    # Install locally without SSH
    cp "$SCRIPT_DIR/disable-swap-permanent.sh" /usr/local/bin/
    chmod +x /usr/local/bin/disable-swap-permanent.sh

    # Run the script
    /usr/local/bin/disable-swap-permanent.sh

    # Install systemd service
    cp "$SCRIPT_DIR/disable-swap-kubernetes.service" /etc/systemd/system/

    # Enable and start service
    systemctl daemon-reload
    systemctl enable disable-swap-kubernetes.service
    systemctl start disable-swap-kubernetes.service

    # Verify
    systemctl status disable-swap-kubernetes.service --no-pager

    echo ""
    echo "Swap status:"
    swapon --show || echo "No swap enabled (GOOD)"

    if [ $? -eq 0 ]; then
        success "Permanent swap disable installed on $node_name"
        return 0
    else
        error "Failed to install on $node_name"
        return 1
    fi
}

install_on_node() {
    local node_ip="$1"
    local node_name="$2"

    log "Installing permanent swap disable on $node_name ($node_ip)..."

    # Copy script to node
    log "Copying disable-swap-permanent.sh to $node_name..."
    if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/disable-swap-permanent.sh" root@$node_ip:/tmp/; then
        success "Script copied to $node_name"
    else
        error "Failed to copy script to $node_name"
        return 1
    fi

    # Copy systemd service to node
    log "Copying systemd service to $node_name..."
    if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/disable-swap-kubernetes.service" root@$node_ip:/tmp/; then
        success "Service file copied to $node_name"
    else
        error "Failed to copy service file to $node_name"
        return 1
    fi

    # Install and enable on node
    log "Installing and enabling on $node_name..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$node_ip 'bash -s' <<'ENDSSH'
        # Move script to proper location
        mv /tmp/disable-swap-permanent.sh /usr/local/bin/
        chmod +x /usr/local/bin/disable-swap-permanent.sh

        # Run the script
        /usr/local/bin/disable-swap-permanent.sh

        # Install systemd service
        mv /tmp/disable-swap-kubernetes.service /etc/systemd/system/

        # Enable and start service
        systemctl daemon-reload
        systemctl enable disable-swap-kubernetes.service
        systemctl start disable-swap-kubernetes.service

        # Verify
        systemctl status disable-swap-kubernetes.service --no-pager

        echo ""
        echo "Swap status:"
        swapon --show || echo "No swap enabled (GOOD)"
ENDSSH

    if [ $? -eq 0 ]; then
        success "Permanent swap disable installed on $node_name"
        return 0
    else
        error "Failed to install on $node_name"
        return 1
    fi
}

main() {
    banner

    # Check if required files exist
    if [ ! -f "$SCRIPT_DIR/disable-swap-permanent.sh" ]; then
        error "disable-swap-permanent.sh not found in $SCRIPT_DIR"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/disable-swap-kubernetes.service" ]; then
        error "disable-swap-kubernetes.service not found in $SCRIPT_DIR"
        exit 1
    fi

    success "Found required files"

    # Get local IP to detect which node we're on
    local local_ip=$(hostname -I | awk '{print $1}')
    log "Detected local IP: $local_ip"

    # Install on all nodes
    local failed_nodes=0
    for node_entry in "${NODES[@]}"; do
        IFS=':' read -r node_ip node_name <<< "$node_entry"

        echo ""

        # Check if this is the local node
        if [ "$node_ip" == "$local_ip" ] || [ "$node_name" == "$(hostname)" ]; then
            log "Detected local node: $node_name"
            install_on_local_node "$node_name"
            if [ $? -ne 0 ]; then
                ((failed_nodes++))
            fi
        else
            install_on_node "$node_ip" "$node_name"
            if [ $? -ne 0 ]; then
                ((failed_nodes++))
            fi
        fi

        echo ""
        sleep 2
    done

    echo ""
    echo -e "${GREEN}=============================================================="
    echo "    Installation Summary"
    echo -e "==============================================================${NC}"

    if [ $failed_nodes -eq 0 ]; then
        success "Permanent swap disable installed on all nodes successfully!"
        echo ""
        echo "Your Kubernetes cluster will now survive reboots without swap issues."
        echo ""
        echo "To verify, you can reboot any node and check:"
        echo "  sudo systemctl status disable-swap-kubernetes.service"
        echo "  sudo swapon --show"
        echo ""
    else
        error "Failed to install on $failed_nodes node(s)"
        echo "Please check the errors above and retry failed nodes manually."
        exit 1
    fi
}

main "$@"
