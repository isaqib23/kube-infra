#!/bin/bash

# Cleanup Failed Monitoring Installation
# Run this before re-running 07-ha-monitoring-setup.sh

set -e

# Colors
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

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}"
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    Cleanup Failed Monitoring Installation"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will remove the failed monitoring stack"
    echo "so you can re-run 07-ha-monitoring-setup.sh with fixes."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

main() {
    banner
    check_root

    log "Starting cleanup of failed monitoring installation..."

    # Step 1: Uninstall Helm releases
    log "Uninstalling Helm releases..."

    if helm list -n monitoring | grep -q "kube-prometheus-stack"; then
        helm uninstall kube-prometheus-stack -n monitoring || warning "Failed to uninstall kube-prometheus-stack"
        success "kube-prometheus-stack uninstalled"
    else
        warning "kube-prometheus-stack not found"
    fi

    if helm list -n monitoring | grep -q "loki-stack"; then
        helm uninstall loki-stack -n monitoring || warning "Failed to uninstall loki-stack"
        success "loki-stack uninstalled"
    else
        warning "loki-stack not found"
    fi

    if helm list -n monitoring | grep -q "loki"; then
        helm uninstall loki -n monitoring || warning "Failed to uninstall loki"
        success "loki uninstalled"
    fi

    if helm list -n monitoring | grep -q "promtail"; then
        helm uninstall promtail -n monitoring || warning "Failed to uninstall promtail"
        success "promtail uninstalled"
    fi

    # Step 2: Wait for pods to terminate
    log "Waiting for pods to terminate..."
    sleep 30

    # Step 3: Delete PVCs with permission issues
    log "Deleting PVCs with permission issues..."

    kubectl delete pvc -n monitoring kube-prometheus-stack-grafana --ignore-not-found=true
    kubectl delete pvc -n monitoring prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 --ignore-not-found=true
    kubectl delete pvc -n monitoring prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-1 --ignore-not-found=true

    success "Broken PVCs deleted"

    # Step 4: Delete custom resources
    log "Deleting custom monitoring resources..."

    kubectl delete prometheusrules -n monitoring kubernetes-ha-cluster-alerts --ignore-not-found=true
    kubectl delete servicemonitor -n monitoring haproxy-exporter --ignore-not-found=true
    kubectl delete daemonset -n monitoring haproxy-exporter --ignore-not-found=true
    kubectl delete svc -n monitoring haproxy-exporter --ignore-not-found=true
    kubectl delete configmap -n monitoring ha-cluster-dashboard --ignore-not-found=true

    success "Custom resources deleted"

    # Step 5: Delete secrets
    log "Deleting monitoring secrets..."

    kubectl delete secret -n monitoring alertmanager-kube-prometheus-stack-alertmanager --ignore-not-found=true
    kubectl delete secret -n monitoring grafana-basic-auth --ignore-not-found=true
    kubectl delete secret -n monitoring prometheus-basic-auth --ignore-not-found=true
    kubectl delete secret -n monitoring alertmanager-basic-auth --ignore-not-found=true

    success "Secrets deleted"

    # Step 6: Verify cleanup
    log "Verifying cleanup..."

    local remaining_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $remaining_pods -eq 0 ]]; then
        success "All monitoring pods removed"
    else
        warning "$remaining_pods pods still terminating (this is normal, they will finish soon)"
    fi

    local remaining_pvcs=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $remaining_pvcs -eq 0 ]]; then
        success "All PVCs removed"
    else
        warning "$remaining_pvcs PVCs still exist"
        kubectl get pvc -n monitoring
    fi

    echo
    echo -e "${GREEN}=============================================================="
    echo "✓ Cleanup Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "Next steps:"
    echo "1. Copy the updated 07-ha-monitoring-setup.sh to k8s-cp1"
    echo "2. Run: sudo bash 07-ha-monitoring-setup.sh"
    echo
    echo "The script has been fixed to resolve:"
    echo "• Grafana legacy alerting error (now uses unified_alerting)"
    echo "• Prometheus permission denied error (fsGroup fixed)"
    echo
    success "Ready to re-run monitoring setup!"
}

main "$@"
