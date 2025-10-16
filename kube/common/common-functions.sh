#!/bin/bash

# Common Functions for Kubernetes Cluster Setup
# Shared across Production, Staging, and Development environments

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "${LOG_FILE:-/var/log/k8s-setup.log}"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "${LOG_FILE:-/var/log/k8s-setup.log}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "${LOG_FILE:-/var/log/k8s-setup.log}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}" | tee -a "${LOG_FILE:-/var/log/k8s-setup.log}"
    exit 1
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

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}

    log "Waiting for pods with label $label in namespace $namespace..."

    if kubectl wait --for=condition=ready --timeout=${timeout}s pod -l "$label" -n "$namespace"; then
        success "Pods are ready"
        return 0
    else
        warning "Some pods may not be ready yet"
        return 1
    fi
}

test_dns_resolution() {
    log "Testing DNS resolution..."

    if kubectl run test-dns --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default &>/dev/null; then
        success "DNS resolution working"
        return 0
    else
        warning "DNS resolution may have issues"
        return 1
    fi
}

get_cluster_info() {
    echo "=== Cluster Information ==="
    echo "Cluster: $(kubectl config current-context 2>/dev/null || echo 'Not configured')"
    echo "Server: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo 'Not configured')"
    echo "Nodes:"
    kubectl get nodes -o wide 2>/dev/null || echo "  No nodes found"
    echo
}

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        success "Backed up $file"
    fi
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_port_available() {
    local port=$1
    if netstat -tlnp 2>/dev/null | grep -q ":$port " || ss -tlnp 2>/dev/null | grep -q ":$port "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

export -f log success warning error check_root check_ubuntu_version
export -f wait_for_pods test_dns_resolution get_cluster_info backup_file
export -f validate_ip check_port_available
