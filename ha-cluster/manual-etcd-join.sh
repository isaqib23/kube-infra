#!/bin/bash

# Manual etcd Join with Learner Sync Wait
# This script manually joins etcd with proper wait time for learner sync
# Run on k8s-cp2 after kubeadm has failed at etcd join

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
    echo "    Manual etcd Join with Learner Sync Wait"
    echo "=============================================================="
    echo -e "${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Configuration
CP1_IP="10.255.254.10"
CP2_IP="10.255.254.11"

wait_for_etcd_learner_sync() {
    log "Waiting for etcd learner to sync with leader..."
    echo "This may take 2-5 minutes. Please be patient."
    echo

    local max_wait=600  # 10 minutes
    local elapsed=0
    local check_interval=10

    while [[ $elapsed -lt $max_wait ]]; do
        # Check if etcd pod exists on k8s-cp2
        if [[ -f /etc/kubernetes/manifests/etcd.yaml ]]; then
            log "etcd manifest exists on k8s-cp2"

            # Wait for etcd pod to start
            sleep 20

            # Try to check if learner is in sync by querying member list from k8s-cp1
            # A synced learner will have matching raft index with leader
            local sync_check=$(ssh -o ConnectTimeout=5 root@$CP1_IP \
                "kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
                --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                member list -w json 2>/dev/null | grep -c 'isLearner.*true'" || echo "0")

            if [[ "$sync_check" == "1" ]]; then
                success "etcd learner detected. Continuing sync wait..."
                sleep 30
            else
                log "Checking etcd health..."
                sleep 10
            fi
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        echo -n "."
    done

    echo
    warning "Max wait time reached. Proceeding with manual promotion..."
}

promote_etcd_learner() {
    log "Manually promoting etcd learner to voting member..."

    # Get the learner member ID from k8s-cp1
    local member_info=$(ssh -o ConnectTimeout=5 root@$CP1_IP \
        "kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list -w table" 2>/dev/null)

    echo "$member_info"
    echo

    local learner_id=$(echo "$member_info" | grep "true" | awk '{print $1}' | head -1)

    if [[ -z "$learner_id" ]]; then
        warning "No learner member found. May already be promoted."
        return 0
    fi

    log "Found learner member ID: $learner_id"
    log "Attempting promotion..."

    # Try to promote
    ssh -o ConnectTimeout=5 root@$CP1_IP \
        "kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member promote $learner_id" 2>&1 || warning "Promotion command failed (may need more sync time)"

    sleep 5

    # Verify promotion
    local promoted_check=$(ssh -o ConnectTimeout=5 root@$CP1_IP \
        "kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list -w table" 2>/dev/null)

    echo "$promoted_check"

    if echo "$promoted_check" | grep -q "k8s-cp2.*false"; then
        success "etcd learner successfully promoted!"
    else
        error "Promotion may have failed. Check etcd member list manually."
    fi
}

main() {
    banner
    check_root

    log "Starting manual etcd learner sync and promotion..."
    echo

    wait_for_etcd_learner_sync
    promote_etcd_learner

    success "Manual etcd join completed!"
    echo
    echo "Next steps:"
    echo "1. Verify etcd cluster: kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl member list -w table"
    echo "2. Check k8s-cp2 node: kubectl get nodes"
    echo "3. If still not working, check etcd logs: kubectl logs -n kube-system etcd-k8s-cp2"
}

main "$@"
