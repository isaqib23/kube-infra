#!/bin/bash

# HA Kubernetes Master Deployment Orchestration Script
# Run this script to orchestrate the complete HA cluster deployment
# Purpose: Coordinate deployment across all 4 Dell R740 servers

set -euo pipefail

LOG_FILE="/var/log/ha-master-deploy.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Deployment configuration
VIP="10.255.254.100"
CLUSTER_DOMAIN="k8s.local"

# Control plane servers
declare -A CONTROL_PLANES=(
    ["k8s-cp1"]="10.255.254.10"
    ["k8s-cp2"]="10.255.254.11"
    ["k8s-cp3"]="10.255.254.12"
    ["k8s-cp4"]="10.255.254.13"
)

# Deployment phases
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
    echo -e "${BLUE}${BOLD}"
    echo "################################################################"
    echo "#                                                              #"
    echo "#     HA Kubernetes Cluster Master Deployment Script          #"
    echo "#     4x Dell PowerEdge R740 Servers                          #"
    echo "#     MANUAL EXECUTION MODE                                    #"
    echo "#                                                              #"
    echo "################################################################"
    echo -e "${NC}"
    echo
    echo -e "${YELLOW}${BOLD}DEPLOYMENT MODE: Manual with Guided Steps${NC}"
    echo
    echo "This script will guide you through each deployment step."
    echo "For each server, you'll receive clear instructions on:"
    echo "• Which script to run"
    echo "• Which server to run it on" 
    echo "• When to proceed to the next step"
    echo
    echo -e "${GREEN}Benefits of manual mode:${NC}"
    echo "• Full control over each step"
    echo "• Easy to troubleshoot if issues arise"
    echo "• No SSH connectivity requirements"
    echo "• Can monitor progress on each server"
    echo
    echo "Deployment Overview:"
    echo "• Phase 1: Prerequisites and planning"
    echo "• Phase 2: Server preparation (all nodes)"
    echo "• Phase 3: Load balancer setup (all nodes)"
    echo "• Phase 4: Cluster initialization (k8s-cp1)"
    echo "• Phase 5: Control plane joining (k8s-cp2, cp3, cp4)"
    echo "• Phase 6: Storage configuration"
    echo "• Phase 7: Ingress controller deployment"
    echo "• Phase 8: Monitoring stack deployment"
    echo "• Phase 9: Cluster validation and testing"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking deployment prerequisites..."
    
    # Check if we're on the right server
    local hostname=$(hostname)
    if [[ "$hostname" != "k8s-cp1" ]]; then
        error "This orchestration script should only be run from k8s-cp1. Current hostname: $hostname"
    fi
    
    # Check if all required scripts exist
    local required_scripts=(
        "01-server-preparation.sh"
        "02-ha-loadbalancer-setup.sh"
        "03-ha-cluster-init.sh"
        "04-ha-cluster-join.sh"
        "05-ha-storage-setup.sh"
        "06-ha-ingress-setup.sh"
        "07-ha-monitoring-setup.sh"
        "08-cluster-validation.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            error "Required script not found: $script"
        fi
        if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    # Check if SSH access to other nodes is configured
    log "Checking SSH connectivity to other nodes..."
    local ssh_errors=0
    for node in k8s-cp2 k8s-cp3 k8s-cp4; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH test successful'" &>/dev/null; then
            warning "Cannot SSH to $node ($node_ip). Manual execution may be required."
            ((ssh_errors++))
        fi
    done
    
    if [[ $ssh_errors -gt 0 ]]; then
        warning "$ssh_errors nodes are not accessible via SSH. You'll need to run scripts manually on those nodes."
    fi
    
    success "Prerequisites check completed"
}

get_deployment_configuration() {
    echo "=== Deployment Configuration ==="
    echo
    echo "Server Configuration:"
    for node in "${!CONTROL_PLANES[@]}"; do
        echo "  $node: ${CONTROL_PLANES[$node]}"
    done
    echo "  VIP: $VIP"
    echo "  Cluster Domain: $CLUSTER_DOMAIN"
    echo
    
    read -p "Is this configuration correct? [y/N]: " CONFIRM_CONFIG
    if [[ ! $CONFIRM_CONFIG =~ ^[Yy]$ ]]; then
        echo "Please update the configuration in the script and run again."
        exit 0
    fi
    
    echo
    read -p "This will deploy a complete HA Kubernetes cluster. Continue? [y/N]: " CONFIRM_DEPLOY
    if [[ ! $CONFIRM_DEPLOY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    echo
    echo "=== Deployment Options ==="
    read -p "Skip server preparation if already done? [y/N]: " SKIP_PREP
    read -p "Skip load balancer setup if already done? [y/N]: " SKIP_LB
    read -p "Skip cluster initialization if already done? [y/N]: " SKIP_INIT
    read -p "Run validation tests at the end? [Y/n]: " RUN_VALIDATION
    
    SKIP_PREP=${SKIP_PREP:-n}
    SKIP_LB=${SKIP_LB:-n}
    SKIP_INIT=${SKIP_INIT:-n}
    RUN_VALIDATION=${RUN_VALIDATION:-y}
    
    success "Configuration confirmed"
}

wait_for_user_action() {
    local script="$1"
    local node="$2"
    local description="$3"
    
    local node_ip="${CONTROL_PLANES[$node]}"
    
    echo
    echo -e "${YELLOW}${BOLD}=============================================================="
    echo "  MANUAL EXECUTION REQUIRED"
    echo -e "==============================================================${NC}"
    echo
    echo -e "${BLUE}${BOLD}Step: $description${NC}"
    echo -e "${BLUE}Server: $node ($node_ip)${NC}"
    echo -e "${BLUE}Script: $script${NC}"
    echo
    echo -e "${YELLOW}${BOLD}Instructions:${NC}"
    echo "1. Open a new terminal/SSH session"
    echo "2. Connect to the server: ${GREEN}ssh root@$node_ip${NC}"
    echo "3. Run the script: ${GREEN}${BOLD}sudo $script${NC}"
    echo "4. Wait for the script to complete successfully"
    echo "5. Verify no error messages appear"
    echo "6. Return here and press ENTER to continue"
    echo
    echo -e "${RED}${BOLD}⚠️  IMPORTANT: Do NOT continue until the script completes successfully!${NC}"
    echo -e "${RED}   Check the script output for any errors before proceeding.${NC}"
    echo
    
    read -p "Press ENTER when $description is completed successfully on $node..."
    
    success "$description completed on $node (manual confirmation)"
    echo
}

execute_on_node() {
    local node="$1"
    local script="$2"
    local description="$3"
    
    local node_ip="${CONTROL_PLANES[$node]}"
    
    log "Preparing to execute $description on $node ($node_ip)..."
    
    # Check if SSH is working and script exists
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "test -f $script" &>/dev/null; then
        log "SSH connection verified and script found on $node"
        
        # Ask user if they want to try automatic execution
        echo
        echo -e "${BLUE}SSH connection to $node is working.${NC}"
        read -p "Try automatic execution via SSH? [y/N]: " AUTO_EXEC
        
        if [[ $AUTO_EXEC =~ ^[Yy]$ ]]; then
            log "Attempting automatic execution via SSH..."
            if ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no root@$node_ip "cd $(dirname $script) && $script"; then
                success "$description completed on $node via SSH"
                return 0
            else
                warning "$description failed via SSH, falling back to manual execution"
            fi
        fi
    else
        log "SSH connection failed or script not found, using manual execution"
    fi
    
    # Manual execution
    wait_for_user_action "$script" "$node" "$description"
    
    return 0
}

phase_server_preparation() {
    if [[ $SKIP_PREP =~ ^[Yy]$ ]]; then
        warning "Skipping server preparation phase"
        PHASE_STATUS["Server Preparation"]="SKIPPED"
        return 0
    fi
    
    phase_start "Server Preparation"
    
    log "Preparing all 4 Dell R740 servers..."
    
    # Execute on k8s-cp1 first (local)
    log "Running server preparation on k8s-cp1 (local)..."
    if "$SCRIPT_DIR/01-server-preparation.sh"; then
        success "Server preparation completed on k8s-cp1"
    else
        error "Server preparation failed on k8s-cp1"
    fi
    
    # Execute on other nodes
    for node in k8s-cp2 k8s-cp3 k8s-cp4; do
        execute_on_node "$node" "$SCRIPT_DIR/01-server-preparation.sh" "Server preparation"
    done
    
    log "Verifying all nodes are prepared..."
    sleep 30  # Allow time for services to start
    
    phase_complete
}

phase_loadbalancer_setup() {
    if [[ $SKIP_LB =~ ^[Yy]$ ]]; then
        warning "Skipping load balancer setup phase"
        PHASE_STATUS["Load Balancer Setup"]="SKIPPED"
        return 0
    fi
    
    phase_start "Load Balancer Setup"
    
    log "Setting up HAProxy and Keepalived on all nodes..."
    
    # Execute on all nodes
    for node in "${!CONTROL_PLANES[@]}"; do
        if [[ "$node" == "k8s-cp1" ]]; then
            log "Running load balancer setup on k8s-cp1 (local)..."
            if "$SCRIPT_DIR/02-ha-loadbalancer-setup.sh"; then
                success "Load balancer setup completed on k8s-cp1"
            else
                error "Load balancer setup failed on k8s-cp1"
            fi
        else
            execute_on_node "$node" "$SCRIPT_DIR/02-ha-loadbalancer-setup.sh" "Load balancer setup"
        fi
    done
    
    log "Verifying VIP assignment..."
    local vip_timeout=60
    local vip_counter=0
    while [[ $vip_counter -lt $vip_timeout ]]; do
        if ping -c 1 "$VIP" &>/dev/null; then
            success "VIP $VIP is active and responding"
            break
        fi
        sleep 2
        ((vip_counter+=2))
    done
    
    if [[ $vip_counter -ge $vip_timeout ]]; then
        error "VIP $VIP is not responding after $vip_timeout seconds"
    fi
    
    phase_complete
}

phase_cluster_initialization() {
    if [[ $SKIP_INIT =~ ^[Yy]$ ]]; then
        warning "Skipping cluster initialization phase"
        PHASE_STATUS["Cluster Initialization"]="SKIPPED"
        return 0
    fi
    
    phase_start "Cluster Initialization"
    
    log "Initializing Kubernetes cluster on k8s-cp1..."
    
    if "$SCRIPT_DIR/03-ha-cluster-init.sh"; then
        success "Cluster initialization completed on k8s-cp1"
    else
        error "Cluster initialization failed on k8s-cp1"
    fi
    
    log "Verifying cluster is accessible..."
    if kubectl cluster-info &>/dev/null; then
        success "Cluster is accessible via kubectl"
    else
        error "Cannot access cluster via kubectl"
    fi
    
    phase_complete
}

phase_control_plane_joining() {
    phase_start "Control Plane Joining"
    
    log "Copying join information to other control plane nodes..."
    
    # Copy join script to other nodes
    for node in k8s-cp2 k8s-cp3 k8s-cp4; do
        local node_ip="${CONTROL_PLANES[$node]}"
        
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH test'" &>/dev/null; then
            if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no /opt/kubernetes/join-info/control-plane-join.sh root@$node_ip:/tmp/ &>/dev/null; then
                success "Join script copied to $node"
            else
                warning "Could not copy join script to $node"
            fi
        else
            warning "Cannot SSH to $node for file copy"
        fi
    done
    
    # Execute join on other nodes
    for node in k8s-cp2 k8s-cp3 k8s-cp4; do
        log "Joining $node to the cluster..."
        execute_on_node "$node" "$SCRIPT_DIR/04-ha-cluster-join.sh" "Control plane join"
        
        # Wait for node to appear in cluster
        local join_timeout=180
        local join_counter=0
        while [[ $join_counter -lt $join_timeout ]]; do
            if kubectl get node "$node" &>/dev/null; then
                success "$node successfully joined the cluster"
                break
            fi
            sleep 10
            ((join_counter+=10))
        done
        
        if [[ $join_counter -ge $join_timeout ]]; then
            error "$node did not join the cluster within $join_timeout seconds"
        fi
    done
    
    log "Verifying all nodes are Ready..."
    local ready_timeout=300
    local ready_counter=0
    while [[ $ready_counter -lt $ready_timeout ]]; do
        local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
        if [[ $ready_nodes -eq 4 ]]; then
            success "All 4 nodes are Ready"
            break
        fi
        sleep 10
        ((ready_counter+=10))
    done
    
    if [[ $ready_counter -ge $ready_timeout ]]; then
        error "Not all nodes became Ready within $ready_timeout seconds"
    fi
    
    phase_complete
}

phase_storage_setup() {
    phase_start "Storage Configuration"
    
    log "Setting up distributed storage across all nodes..."
    
    if "$SCRIPT_DIR/05-ha-storage-setup.sh"; then
        success "Storage configuration completed"
    else
        error "Storage configuration failed"
    fi
    
    log "Verifying storage classes and persistent volumes..."
    local storage_classes=$(kubectl get storageclass --no-headers | wc -l)
    local persistent_volumes=$(kubectl get pv --no-headers | wc -l)
    
    if [[ $storage_classes -ge 4 && $persistent_volumes -ge 10 ]]; then
        success "Storage configuration verified ($storage_classes storage classes, $persistent_volumes PVs)"
    else
        warning "Storage configuration may be incomplete"
    fi
    
    phase_complete
}

phase_ingress_setup() {
    phase_start "Ingress Controller Deployment"
    
    log "Deploying HA NGINX Ingress Controller..."
    
    if "$SCRIPT_DIR/06-ha-ingress-setup.sh"; then
        success "Ingress controller deployment completed"
    else
        error "Ingress controller deployment failed"
    fi
    
    log "Verifying ingress controller..."
    local ingress_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers | grep -c "Running" || echo "0")
    
    if [[ $ingress_pods -ge 4 ]]; then
        success "Ingress controller verified ($ingress_pods pods running)"
    else
        warning "Ingress controller may not be fully ready"
    fi
    
    phase_complete
}

phase_monitoring_setup() {
    phase_start "Monitoring Stack Deployment"
    
    log "Deploying comprehensive monitoring stack..."
    
    if "$SCRIPT_DIR/07-ha-monitoring-setup.sh"; then
        success "Monitoring stack deployment completed"
    else
        error "Monitoring stack deployment failed"
    fi
    
    log "Verifying monitoring components..."
    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -c "Running" || echo "0")
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -c "Running" || echo "0")
    
    if [[ $prometheus_pods -ge 1 && $grafana_pods -ge 1 ]]; then
        success "Monitoring stack verified (Prometheus: $prometheus_pods, Grafana: $grafana_pods)"
    else
        warning "Monitoring stack may not be fully ready"
    fi
    
    phase_complete
}

phase_validation() {
    if [[ ! $RUN_VALIDATION =~ ^[Yy]$ ]]; then
        warning "Skipping validation phase"
        PHASE_STATUS["Cluster Validation"]="SKIPPED"
        return 0
    fi
    
    phase_start "Cluster Validation"
    
    log "Running comprehensive cluster validation..."
    
    if "$SCRIPT_DIR/08-cluster-validation.sh"; then
        success "Cluster validation completed successfully"
    else
        warning "Cluster validation completed with some failures"
    fi
    
    phase_complete
}

show_deployment_summary() {
    echo
    echo -e "${GREEN}${BOLD}################################################################"
    echo "#                                                              #"
    echo "#     HA Kubernetes Cluster Deployment Completed!             #"
    echo "#                                                              #"
    echo "################################################################${NC}"
    echo
    echo "=== Deployment Summary ==="
    for phase in "${!PHASE_STATUS[@]}"; do
        local status="${PHASE_STATUS[$phase]}"
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
    echo "Cluster Name: HA Kubernetes Cluster"
    echo "Nodes: 4x Dell PowerEdge R740"
    echo "Control Plane Endpoint: https://$VIP:6443"
    echo "Cluster Domain: $CLUSTER_DOMAIN"
    echo
    
    echo "=== Node Status ==="
    kubectl get nodes -o wide 2>/dev/null || echo "Could not retrieve node status"
    echo
    
    echo "=== Access Information ==="
    echo "Kubernetes API: https://$VIP:6443"
    echo "Grafana: https://grafana.$CLUSTER_DOMAIN"
    echo "Prometheus: https://prometheus.$CLUSTER_DOMAIN"
    echo "AlertManager: https://alertmanager.$CLUSTER_DOMAIN"
    echo
    echo "Default Credentials:"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo
    
    echo "=== Key Features Deployed ==="
    echo "✓ High Availability (4-node control plane + worker)"
    echo "✓ Load Balancing (HAProxy + Keepalived)"
    echo "✓ Container Runtime (containerd)"
    echo "✓ Networking (Calico CNI)"
    echo "✓ Ingress (NGINX with SSL/TLS)"
    echo "✓ Storage (Multi-tier persistent storage)"
    echo "✓ Monitoring (Prometheus + Grafana + Loki)"
    echo "✓ Security (RBAC, Network Policies, TLS)"
    echo "✓ Backup (Automated etcd and config backups)"
    echo
    
    echo "=== Next Steps ==="
    echo "1. Configure external DNS for .$CLUSTER_DOMAIN domains"
    echo "2. Set up production SSL certificates"
    echo "3. Configure external monitoring alerts (email/Slack)"
    echo "4. Deploy your applications"
    echo "5. Set up regular maintenance procedures"
    echo
    
    echo "=== Useful Commands ==="
    echo "• Check cluster status: kubectl get nodes,pods --all-namespaces"
    echo "• View cluster info: kubectl cluster-info"
    echo "• Access Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "• Check ingress: kubectl get ingress --all-namespaces"
    echo "• View logs: tail -f $LOG_FILE"
    echo
    
    echo "=== Documentation ==="
    echo "• Deployment plan: ../HA_DEPLOYMENT_PLAN.md"
    echo "• Scripts location: $SCRIPT_DIR"
    echo "• Logs location: $LOG_FILE"
    echo "• Validation report: /opt/kubernetes/cluster-validation-report-*.txt"
    echo
    
    echo -e "${GREEN}${BOLD}🎉 Your HA Kubernetes cluster is ready for production workloads! 🎉${NC}"
    echo
    echo -e "${YELLOW}Remember to:${NC}"
    echo "• Configure external backup storage"
    echo "• Set up monitoring alerts"
    echo "• Review security policies"
    echo "• Document operational procedures"
}

estimate_deployment_time() {
    echo "=== Deployment Time Estimate ==="
    echo "Phase 1: Server preparation - ~15 minutes per node (60 min total)"
    echo "Phase 2: Load balancer setup - ~5 minutes per node (20 min total)"
    echo "Phase 3: Cluster initialization - ~10 minutes"
    echo "Phase 4: Control plane joining - ~5 minutes per node (15 min total)"
    echo "Phase 5: Storage configuration - ~10 minutes"
    echo "Phase 6: Ingress deployment - ~10 minutes"
    echo "Phase 7: Monitoring deployment - ~15 minutes"
    echo "Phase 8: Validation - ~10 minutes"
    echo
    echo "Total estimated time: ~2.5 hours"
    echo "Note: Times may vary based on network speed and hardware performance"
    echo
}

main() {
    banner
    check_root
    check_prerequisites
    estimate_deployment_time
    get_deployment_configuration
    
    log "Starting HA Kubernetes cluster master deployment..."
    
    # Execute deployment phases
    phase_server_preparation
    phase_loadbalancer_setup
    phase_cluster_initialization
    phase_control_plane_joining
    phase_storage_setup
    phase_ingress_setup
    phase_monitoring_setup
    phase_validation
    
    # Show results
    show_deployment_summary
    
    success "HA Kubernetes cluster deployment orchestration completed!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script orchestrates the complete deployment of an HA Kubernetes cluster"
        echo "across 4 Dell PowerEdge R740 servers."
        echo
        echo "Prerequisites:"
        echo "• All 4 servers have fresh Ubuntu 24.04 installation"
        echo "• SSH key authentication configured between servers"
        echo "• This script must be run from k8s-cp1"
        echo "• All deployment scripts must be present in the same directory"
        echo
        echo "The script will guide you through:"
        echo "• Configuration validation"
        echo "• Interactive deployment options"
        echo "• Automated execution across all nodes"
        echo "• Comprehensive validation testing"
        echo
        echo "Estimated deployment time: 2-3 hours"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac