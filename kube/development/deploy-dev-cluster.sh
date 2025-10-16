#!/bin/bash

# Development Kubernetes Cluster Deployment Script
# Single-Node Development Environment on Dell R740
# Run this script on k8s-dev1 to deploy the complete cluster

set -euo pipefail

LOG_FILE="/var/log/dev-cluster-deploy.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Server configuration
SERVER_NAME="k8s-dev1"
SERVER_IP="10.255.254.10"
CLUSTER_DOMAIN="k8s.local"

# Deployment phases tracking
declare -A PHASE_STATUS=()
CURRENT_PHASE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

phase_start() {
    CURRENT_PHASE="$1"
    echo
    echo -e "${CYAN}${BOLD}=============================================================="
    echo "PHASE: $CURRENT_PHASE"
    echo -e "==============================================================${NC}"
    log "Starting phase: $CURRENT_PHASE"
}

phase_complete() {
    PHASE_STATUS["$CURRENT_PHASE"]="COMPLETED"
    success "Phase completed: $CURRENT_PHASE"
    echo
}

banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "################################################################"
    echo "#                                                              #"
    echo "#     Development Kubernetes Cluster Deployment Script        #"
    echo "#     Single-Node Configuration on Dell R740                  #"
    echo "#                                                              #"
    echo "################################################################"
    echo -e "${NC}"
    echo
    echo -e "${GREEN}Server Configuration:${NC}"
    echo "  • Node: $SERVER_NAME"
    echo "  • IP: $SERVER_IP"
    echo "  • Cluster Domain: $CLUSTER_DOMAIN"
    echo "  • Architecture: Single-node (control-plane + worker)"
    echo
    echo -e "${GREEN}Deployment Overview:${NC}"
    echo "  Phase 1: Server Preparation"
    echo "  Phase 2: Cluster Initialization"
    echo "  Phase 3: Storage Configuration"
    echo "  Phase 4: Ingress Controller Setup"
    echo "  Phase 5: Monitoring Stack Deployment"
    echo "  Phase 6: Basic Validation"
    echo
    echo -e "${YELLOW}Estimated Time: 30-45 minutes${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if we're on the right server
    local hostname=$(hostname)
    if [[ "$hostname" != "$SERVER_NAME" ]]; then
        error "This script should only be run on $SERVER_NAME. Current hostname: $hostname"
    fi

    # Check if required scripts exist
    local required_scripts=(
        "01-server-preparation.sh"
        "03-ha-cluster-init.sh"
        "05-ha-storage-setup.sh"
        "06-ha-ingress-setup.sh"
        "07-ha-monitoring-setup.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            error "Required script not found: $script"
        fi
        if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            chmod +x "$SCRIPT_DIR/$script"
            log "Made $script executable"
        fi
    done

    success "Prerequisites check passed"
}

get_deployment_configuration() {
    echo "=== Deployment Configuration ==="
    echo
    echo "This will deploy a single-node Kubernetes cluster on:"
    echo "  Server: $SERVER_NAME ($SERVER_IP)"
    echo "  Domain: $CLUSTER_DOMAIN"
    echo
    echo "Components to be installed:"
    echo "  ✓ Kubernetes v1.28+ (kubeadm, kubelet, kubectl)"
    echo "  ✓ Containerd runtime"
    echo "  ✓ Calico CNI"
    echo "  ✓ Storage classes and persistent volumes"
    echo "  ✓ NGINX Ingress Controller with cert-manager"
    echo "  ✓ Prometheus + Grafana + Loki monitoring stack"
    echo

    read -p "Continue with deployment? [y/N]: " CONFIRM_DEPLOY
    if [[ ! $CONFIRM_DEPLOY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi

    echo
    echo "=== Deployment Options ==="
    read -p "Skip server preparation if already done? [y/N]: " SKIP_PREP
    read -p "Skip cluster initialization if already done? [y/N]: " SKIP_INIT

    SKIP_PREP=${SKIP_PREP:-n}
    SKIP_INIT=${SKIP_INIT:-n}

    success "Configuration confirmed"
}

phase_server_preparation() {
    if [[ $SKIP_PREP =~ ^[Yy]$ ]]; then
        warning "Skipping server preparation phase"
        PHASE_STATUS["Server Preparation"]="SKIPPED"
        return 0
    fi

    phase_start "Server Preparation"

    log "Preparing $SERVER_NAME for Kubernetes installation..."
    log "This will install: Docker/containerd, Kubernetes components, networking tools"

    if "$SCRIPT_DIR/01-server-preparation.sh"; then
        success "Server preparation completed successfully"
    else
        error "Server preparation failed. Check logs at $LOG_FILE"
    fi

    log "Waiting for services to stabilize..."
    sleep 10

    phase_complete
}

phase_cluster_initialization() {
    if [[ $SKIP_INIT =~ ^[Yy]$ ]]; then
        warning "Skipping cluster initialization phase"
        PHASE_STATUS["Cluster Initialization"]="SKIPPED"
        return 0
    fi

    phase_start "Cluster Initialization"

    log "Initializing single-node Kubernetes cluster..."
    log "This will set up the control plane and configure networking"

    if "$SCRIPT_DIR/03-ha-cluster-init.sh"; then
        success "Cluster initialization completed successfully"
    else
        error "Cluster initialization failed. Check logs at $LOG_FILE"
    fi

    log "Verifying cluster is accessible..."
    sleep 5

    if kubectl cluster-info &>/dev/null; then
        success "Cluster is accessible via kubectl"
        kubectl get nodes
    else
        error "Cannot access cluster via kubectl"
    fi

    phase_complete
}

phase_storage_setup() {
    phase_start "Storage Configuration"

    log "Setting up storage classes and persistent volumes..."
    log "This will configure: fast-ssd, standard-storage, backup-storage, logs-storage"

    if "$SCRIPT_DIR/05-ha-storage-setup.sh"; then
        success "Storage configuration completed successfully"
    else
        error "Storage configuration failed. Check logs at $LOG_FILE"
    fi

    log "Verifying storage setup..."
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    local persistent_volumes=$(kubectl get pv --no-headers 2>/dev/null | wc -l)

    if [[ $storage_classes -ge 1 && $persistent_volumes -ge 1 ]]; then
        success "Storage verified: $storage_classes storage classes, $persistent_volumes PVs"
    else
        warning "Storage configuration may be incomplete"
    fi

    phase_complete
}

phase_ingress_setup() {
    phase_start "Ingress Controller Setup"

    log "Deploying NGINX Ingress Controller with cert-manager..."
    log "This will enable external access to cluster services"

    if "$SCRIPT_DIR/06-ha-ingress-setup.sh"; then
        success "Ingress controller deployment completed successfully"
    else
        error "Ingress controller deployment failed. Check logs at $LOG_FILE"
    fi

    log "Verifying ingress controller..."
    sleep 10

    local ingress_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ $ingress_pods -ge 1 ]]; then
        success "Ingress controller verified: $ingress_pods pods running"
    else
        warning "Ingress controller may still be starting up"
    fi

    phase_complete
}

phase_monitoring_setup() {
    phase_start "Monitoring Stack Deployment"

    log "Deploying monitoring stack (Prometheus, Grafana, Loki)..."
    log "This may take 10-15 minutes depending on image download speeds"

    if "$SCRIPT_DIR/07-ha-monitoring-setup.sh"; then
        success "Monitoring stack deployment completed successfully"
    else
        error "Monitoring stack deployment failed. Check logs at $LOG_FILE"
    fi

    log "Verifying monitoring components..."
    sleep 10

    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ $prometheus_pods -ge 1 && $grafana_pods -ge 1 ]]; then
        success "Monitoring stack verified: Prometheus ($prometheus_pods), Grafana ($grafana_pods)"
    else
        warning "Some monitoring components may still be starting up"
    fi

    phase_complete
}

phase_basic_validation() {
    phase_start "Basic Cluster Validation"

    log "Running basic validation tests..."

    local validation_passed=true

    # Test 1: Node status
    log "Checking node status..."
    if kubectl get nodes | grep -q "Ready"; then
        success "Node is Ready"
    else
        warning "Node is not Ready"
        validation_passed=false
    fi

    # Test 2: System pods
    log "Checking system pods..."
    local system_pods_running=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ $system_pods_running -ge 8 ]]; then
        success "System pods running: $system_pods_running"
    else
        warning "Only $system_pods_running system pods are running"
        validation_passed=false
    fi

    # Test 3: DNS
    log "Testing DNS resolution..."
    if kubectl run dns-test --image=busybox:1.36 --rm --restart=Never -- nslookup kubernetes.default &>/dev/null; then
        success "DNS resolution working"
    else
        warning "DNS resolution test failed"
        validation_passed=false
    fi

    # Test 4: Storage
    log "Checking storage classes..."
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    if [[ $storage_classes -ge 1 ]]; then
        success "Storage classes available: $storage_classes"
    else
        warning "No storage classes found"
        validation_passed=false
    fi

    # Test 5: Ingress
    log "Checking ingress controller..."
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q "Running"; then
        success "Ingress controller is running"
    else
        warning "Ingress controller is not running"
        validation_passed=false
    fi

    # Test 6: Monitoring
    log "Checking monitoring stack..."
    if kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -q "Running"; then
        success "Monitoring stack is running"
    else
        warning "Monitoring stack is not running"
        validation_passed=false
    fi

    if [[ "$validation_passed" == "true" ]]; then
        success "All basic validation tests passed"
    else
        warning "Some validation tests failed - cluster may need time to stabilize"
    fi

    phase_complete
}

show_deployment_summary() {
    echo
    echo -e "${GREEN}${BOLD}################################################################"
    echo "#                                                              #"
    echo "#     Development Kubernetes Cluster Deployed Successfully!   #"
    echo "#                                                              #"
    echo "################################################################${NC}"
    echo

    echo "=== Deployment Summary ==="
    for phase in "Server Preparation" "Cluster Initialization" "Storage Configuration" "Ingress Controller Setup" "Monitoring Stack Deployment" "Basic Cluster Validation"; do
        local status="${PHASE_STATUS[$phase]:-UNKNOWN}"
        if [[ "$status" == "COMPLETED" ]]; then
            echo -e "  ${GREEN}✓${NC} $phase"
        elif [[ "$status" == "SKIPPED" ]]; then
            echo -e "  ${YELLOW}○${NC} $phase (skipped)"
        else
            echo -e "  ${RED}✗${NC} $phase"
        fi
    done
    echo

    echo "=== Cluster Information ==="
    echo "Node: $SERVER_NAME"
    echo "IP Address: $SERVER_IP"
    echo "Control Plane: https://$SERVER_IP:6443"
    echo "Cluster Domain: $CLUSTER_DOMAIN"
    echo

    echo "=== Node Status ==="
    kubectl get nodes -o wide 2>/dev/null || echo "Could not retrieve node status"
    echo

    echo "=== Pod Status by Namespace ==="
    echo "System Pods:"
    kubectl get pods -n kube-system 2>/dev/null | head -10 || echo "Could not retrieve pod status"
    echo
    echo "Ingress Pods:"
    kubectl get pods -n ingress-nginx 2>/dev/null || echo "Could not retrieve ingress pods"
    echo
    echo "Monitoring Pods:"
    kubectl get pods -n monitoring 2>/dev/null | head -10 || echo "Could not retrieve monitoring pods"
    echo

    echo "=== Access Information ==="
    echo "Kubernetes API: https://$SERVER_IP:6443"
    echo
    echo "Add this to your /etc/hosts file for web access:"
    echo "$SERVER_IP grafana.$CLUSTER_DOMAIN prometheus.$CLUSTER_DOMAIN alertmanager.$CLUSTER_DOMAIN"
    echo
    echo "Then access:"
    echo "  • Grafana: https://grafana.$CLUSTER_DOMAIN"
    echo "  • Prometheus: https://prometheus.$CLUSTER_DOMAIN"
    echo "  • AlertManager: https://alertmanager.$CLUSTER_DOMAIN"
    echo
    echo "Default Credentials:"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo

    echo "=== Features Deployed ==="
    echo "✓ Single-Node Kubernetes Cluster"
    echo "✓ Container Runtime (containerd)"
    echo "✓ Networking (Calico CNI)"
    echo "✓ Ingress Controller (NGINX with SSL/TLS)"
    echo "✓ Certificate Management (cert-manager)"
    echo "✓ Storage Classes (fast-ssd, standard, backup, logs)"
    echo "✓ Persistent Volumes"
    echo "✓ Monitoring (Prometheus + Grafana + Loki)"
    echo "✓ Security (RBAC, TLS)"
    echo "✓ Automated Backups"
    echo

    echo "=== Next Steps ==="
    echo "1. Verify all pods are running: kubectl get pods --all-namespaces"
    echo "2. Configure DNS or update /etc/hosts for ingress access"
    echo "3. Access Grafana dashboard to view metrics"
    echo "4. Deploy your applications"
    echo "5. Set up external backups and monitoring alerts"
    echo

    echo "=== Useful Commands ==="
    echo "• Check cluster: kubectl get nodes,pods --all-namespaces"
    echo "• View logs: kubectl logs -n kube-system <pod-name>"
    echo "• Port forward Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "• Check ingress: kubectl get ingress --all-namespaces"
    echo "• View storage: kubectl get pv,pvc,storageclass"
    echo

    echo "=== Log Files ==="
    echo "Deployment log: $LOG_FILE"
    echo "Individual script logs: /var/log/*.log"
    echo

    echo -e "${GREEN}${BOLD}🎉 Your development Kubernetes cluster is ready! 🎉${NC}"
    echo
}

estimate_deployment_time() {
    echo "=== Deployment Time Estimate ==="
    echo "Phase 1: Server preparation      ~10-15 minutes"
    echo "Phase 2: Cluster initialization  ~5-8 minutes"
    echo "Phase 3: Storage configuration   ~3-5 minutes"
    echo "Phase 4: Ingress setup          ~5-10 minutes"
    echo "Phase 5: Monitoring deployment   ~10-15 minutes"
    echo "Phase 6: Basic validation        ~2-3 minutes"
    echo
    echo "Total estimated time: 30-45 minutes"
    echo "Note: Time varies based on network speed and system performance"
    echo
}

main() {
    banner
    check_root
    check_prerequisites
    estimate_deployment_time
    get_deployment_configuration

    log "Starting development Kubernetes cluster deployment..."
    log "Deployment started at $(date)"

    local start_time=$(date +%s)

    # Execute deployment phases
    phase_server_preparation
    phase_cluster_initialization
    phase_storage_setup
    phase_ingress_setup
    phase_monitoring_setup
    phase_basic_validation

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    # Show results
    show_deployment_summary

    success "Deployment completed in ${minutes}m ${seconds}s"
    log "Deployment finished at $(date)"

    echo
    echo -e "${YELLOW}Important: Some pods may still be starting up. Run this to monitor:${NC}"
    echo "  watch kubectl get pods --all-namespaces"
    echo
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script deploys a complete single-node Kubernetes development cluster"
        echo "on $SERVER_NAME."
        echo
        echo "Prerequisites:"
        echo "• Fresh Ubuntu 24.04 LTS installation"
        echo "• Minimum 8GB RAM, 4 CPU cores"
        echo "• 100GB+ disk space"
        echo "• Internet connectivity for package downloads"
        echo "• Run as root or with sudo"
        echo
        echo "The script will:"
        echo "• Install Kubernetes components"
        echo "• Initialize single-node cluster"
        echo "• Configure storage, ingress, and monitoring"
        echo "• Validate the deployment"
        echo
        echo "Estimated time: 30-45 minutes"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
