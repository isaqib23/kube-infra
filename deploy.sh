#!/bin/bash

# Master Deployment Script for Kubernetes on Dell R740
# Orchestrates the complete setup process

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/k8s-deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "    Kubernetes Production Setup for Dell PowerEdge R740"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script will install and configure:"
    echo "• Kubernetes cluster with containerd runtime"
    echo "• Calico CNI for networking"
    echo "• NGINX Ingress Controller"
    echo "• Helm package manager"
    echo "• Kubernetes Dashboard"
    echo "• PostgreSQL and Redis databases"
    echo "• Prometheus monitoring stack"
    echo "• Grafana dashboards"
    echo
}

check_requirements() {
    log "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
    
    # Check Ubuntu version
    if ! grep -q "24.04" /etc/os-release; then
        error "This script requires Ubuntu 24.04"
    fi
    
    # Check if scripts exist
    local scripts=("k8s-setup.sh" "k8s-dashboard.sh" "prepare-databases.sh" "monitoring-setup.sh")
    for script in "${scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            error "Required script not found: $script"
        fi
        chmod +x "$SCRIPT_DIR/$script"
    done
    
    # Check minimum system resources
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    local total_cores=$(nproc)
    
    if [[ $total_mem -lt 8 ]]; then
        warning "Recommended minimum 8GB RAM, found ${total_mem}GB"
    fi
    
    if [[ $total_cores -lt 4 ]]; then
        warning "Recommended minimum 4 CPU cores, found ${total_cores}"
    fi
    
    success "System requirements check completed"
}

show_configuration_options() {
    echo "=== Configuration Options ==="
    echo
    echo "1. Hostname for master node (default: k8s-master)"
    echo "2. Non-root user for kubectl access (default: ubuntu)"
    echo "3. Pod network CIDR (default: 192.168.0.0/16)"
    echo "4. Install databases (PostgreSQL, Redis)"
    echo "5. Install monitoring (Prometheus, Grafana)"
    echo "6. Install Kubernetes Dashboard"
    echo
}

get_user_input() {
    echo "=== Deployment Configuration ==="
    echo
    
    read -p "Master node hostname [k8s-master]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-k8s-master}
    
    read -p "Non-root user for kubectl [ubuntu]: " USERNAME
    USERNAME=${USERNAME:-ubuntu}
    
    read -p "Pod network CIDR [192.168.0.0/16]: " POD_CIDR
    POD_CIDR=${POD_CIDR:-192.168.0.0/16}
    
    echo
    read -p "Install databases (PostgreSQL, Redis)? [y/N]: " INSTALL_DATABASES
    INSTALL_DATABASES=${INSTALL_DATABASES:-n}
    
    read -p "Install monitoring stack (Prometheus, Grafana)? [y/N]: " INSTALL_MONITORING
    INSTALL_MONITORING=${INSTALL_MONITORING:-n}
    
    read -p "Install Kubernetes Dashboard? [y/N]: " INSTALL_DASHBOARD
    INSTALL_DASHBOARD=${INSTALL_DASHBOARD:-n}
    
    read -p "Install advanced storage setup? [y/N]: " INSTALL_STORAGE
    INSTALL_STORAGE=${INSTALL_STORAGE:-n}
    
    read -p "Install advanced ingress setup? [y/N]: " INSTALL_INGRESS
    INSTALL_INGRESS=${INSTALL_INGRESS:-n}
    
    echo
    echo "=== Deployment Summary ==="
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Pod CIDR: $POD_CIDR"
    echo "Databases: $([[ $INSTALL_DATABASES =~ ^[Yy]$ ]] && echo "Yes" || echo "No")"
    echo "Monitoring: $([[ $INSTALL_MONITORING =~ ^[Yy]$ ]] && echo "Yes" || echo "No")"
    echo "Dashboard: $([[ $INSTALL_DASHBOARD =~ ^[Yy]$ ]] && echo "Yes" || echo "No")"
    echo "Storage Setup: $([[ $INSTALL_STORAGE =~ ^[Yy]$ ]] && echo "Yes" || echo "No")"
    echo "Ingress Setup: $([[ $INSTALL_INGRESS =~ ^[Yy]$ ]] && echo "Yes" || echo "No")"
    echo
    
    read -p "Continue with this configuration? [y/N]: " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
}

install_kubernetes() {
    log "Starting Kubernetes installation..."
    
    if ! "$SCRIPT_DIR/k8s-setup.sh" "$HOSTNAME" "$USERNAME"; then
        error "Kubernetes installation failed"
    fi
    
    success "Kubernetes installation completed"
}

install_dashboard() {
    if [[ $INSTALL_DASHBOARD =~ ^[Yy]$ ]]; then
        log "Installing Kubernetes Dashboard..."
        
        if ! "$SCRIPT_DIR/k8s-dashboard.sh"; then
            error "Dashboard installation failed"
        fi
        
        success "Kubernetes Dashboard installation completed"
    fi
}

install_databases() {
    if [[ $INSTALL_DATABASES =~ ^[Yy]$ ]]; then
        log "Installing databases..."
        
        if ! "$SCRIPT_DIR/prepare-databases.sh"; then
            error "Database installation failed"
        fi
        
        success "Database installation completed"
    fi
}

install_monitoring() {
    if [[ $INSTALL_MONITORING =~ ^[Yy]$ ]]; then
        log "Installing monitoring stack..."
        
        if ! "$SCRIPT_DIR/monitoring-setup.sh"; then
            error "Monitoring installation failed"
        fi
        
        success "Monitoring stack installation completed"
    fi
}

install_storage() {
    if [[ $INSTALL_STORAGE =~ ^[Yy]$ ]]; then
        log "Installing advanced storage setup..."
        
        if ! "$SCRIPT_DIR/storage-setup.sh"; then
            error "Storage setup failed"
        fi
        
        success "Advanced storage setup completed"
    fi
}

install_ingress() {
    if [[ $INSTALL_INGRESS =~ ^[Yy]$ ]]; then
        log "Installing advanced ingress setup..."
        
        if ! "$SCRIPT_DIR/ingress-setup.sh"; then
            error "Ingress setup failed"
        fi
        
        success "Advanced ingress setup completed"
    fi
}

create_storage_directories() {
    log "Creating storage directories..."
    
    mkdir -p /mnt/data/{postgresql,redis,prometheus,grafana}
    chown -R 1001:1001 /mnt/data/postgresql
    chown -R 999:999 /mnt/data/redis
    chown -R 65534:65534 /mnt/data/prometheus
    chown -R 472:472 /mnt/data/grafana
    
    success "Storage directories created"
}

verify_installation() {
    log "Verifying installation..."
    
    # Check if kubectl is working
    if ! sudo -u "$USERNAME" kubectl get nodes &>/dev/null; then
        error "kubectl is not working for user $USERNAME"
    fi
    
    # Check node status
    local node_status=$(kubectl get nodes --no-headers | awk '{print $2}')
    if [[ "$node_status" != "Ready" ]]; then
        error "Node is not in Ready state: $node_status"
    fi
    
    # Check core pods
    local core_pods_ready=$(kubectl get pods -n kube-system --no-headers | grep -c "Running\|Completed")
    if [[ $core_pods_ready -lt 5 ]]; then
        warning "Some core pods may not be running properly"
    fi
    
    success "Installation verification completed"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 Kubernetes Deployment Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Cluster Information ==="
    kubectl get nodes -o wide
    echo
    echo "=== Access Commands ==="
    echo "View cluster status: kubectl get nodes"
    echo "View all pods: kubectl get pods -A"
    echo "View services: kubectl get svc -A"
    echo
    
    if [[ $INSTALL_DASHBOARD =~ ^[Yy]$ ]]; then
        echo "=== Dashboard Access ==="
        echo "Port forward: kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443"
        echo "URL: https://localhost:8443"
        echo
    fi
    
    if [[ $INSTALL_MONITORING =~ ^[Yy]$ ]]; then
        echo "=== Monitoring Access ==="
        echo "Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
        echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
        echo
    fi
    
    echo "=== Next Steps ==="
    echo "1. Test your cluster: kubectl create deployment test --image=nginx"
    echo "2. Add worker nodes using the join command from the setup log"
    echo "3. Configure ingress hostnames in /etc/hosts"
    echo "4. Set up SSL certificates for production use"
    echo "5. Configure backup for etcd and persistent volumes"
    echo
    echo "=== Documentation ==="
    echo "Setup logs: $LOG_FILE"
    echo "Dell R740 specs: $SCRIPT_DIR/r740_server.md"
    echo
    echo -e "${GREEN}Deployment completed at $(date)${NC}"
}

cleanup_on_failure() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check logs at $LOG_FILE"
        echo "To reset and try again:"
        echo "1. Run: kubeadm reset -f"
        echo "2. Remove: rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd"
        echo "3. Restart: systemctl restart containerd"
    fi
}

main() {
    # Set up error handling
    trap cleanup_on_failure ERR
    
    banner
    check_requirements
    show_configuration_options
    get_user_input
    
    log "Starting Kubernetes deployment on Dell R740..."
    
    # Create required directories
    create_storage_directories
    
    # Core Kubernetes installation
    install_kubernetes
    
    # Optional components
    install_storage
    install_ingress
    install_dashboard
    install_databases
    install_monitoring
    
    # Final verification
    verify_installation
    
    # Show completion information
    show_completion_info
    
    success "All deployment tasks completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --skip-input   Skip interactive configuration (use defaults)"
        echo
        echo "This script will set up a complete Kubernetes environment on Ubuntu 24.04"
        echo "including optional databases and monitoring components."
        exit 0
        ;;
    --skip-input)
        HOSTNAME="k8s-master"
        USERNAME="ubuntu"
        POD_CIDR="192.168.0.0/16"
        INSTALL_DATABASES="y"
        INSTALL_MONITORING="y"
        INSTALL_DASHBOARD="y"
        INSTALL_STORAGE="y"
        INSTALL_INGRESS="y"
        
        banner
        check_requirements
        log "Using default configuration (skip-input mode)"
        main
        ;;
    *)
        main "$@"
        ;;
esac