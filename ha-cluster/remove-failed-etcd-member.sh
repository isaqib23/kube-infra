#!/bin/bash

# Remove Failed etcd Member Script
# Run this on k8s-cp1 to clean up failed join attempts

set -euo pipefail

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
    exit 1
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    Remove Failed etcd Member"
    echo "=============================================================="
    echo -e "${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

list_etcd_members() {
    log "Current etcd members:"
    echo

    kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list -w table

    echo
}

remove_failed_members() {
    log "Checking for failed/learner members..."

    # Get list of members with their IDs and states
    local members=$(kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list -w json)

    # Parse and identify learner members
    local learner_ids=$(echo "$members" | grep -o '"ID":[0-9]*' | grep -o '[0-9]*' || echo "")
    local learner_names=$(echo "$members" | grep -o '"name":"[^"]*"' | grep -o ':[^:]*$' | tr -d ':"' || echo "")

    if [[ -z "$learner_ids" ]]; then
        success "No failed members found"
        return 0
    fi

    # Show members
    list_etcd_members

    # Ask user which member to remove
    echo -e "${YELLOW}Enter the MEMBER ID to remove (or 'skip' to skip):${NC}"
    read -p "Member ID: " member_id

    if [[ "$member_id" == "skip" ]] || [[ -z "$member_id" ]]; then
        log "Skipping member removal"
        return 0
    fi

    log "Removing member $member_id..."

    kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member remove "$member_id"

    success "Member removed"
    echo

    log "Updated etcd member list:"
    list_etcd_members
}

main() {
    banner
    check_root

    list_etcd_members
    remove_failed_members

    success "etcd cleanup completed!"
    echo
    echo "Now you can run the updated join script on k8s-cp2"
}

main "$@"
