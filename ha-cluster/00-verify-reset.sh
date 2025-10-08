#!/bin/bash

# Reset Verification Script
# Purpose: Verify that 00-complete-reset.sh completed successfully
# Run this script after the complete reset to ensure clean state

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log() {
    echo -e "${BLUE}[INFO] $*${NC}"
}

pass() {
    echo -e "${GREEN}[PASS] ✓ $*${NC}"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}[FAIL] ✗ $*${NC}"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}[WARN] ⚠ $*${NC}"
    ((WARN_COUNT++))
}

banner() {
    echo -e "${BLUE}${BOLD}"
    echo "################################################################"
    echo "#                                                              #"
    echo "#              Reset Verification Script                       #"
    echo "#         Checking Complete Reset Success                      #"
    echo "#                                                              #"
    echo "################################################################"
    echo -e "${NC}"
    echo
}

check_kubernetes_removal() {
    echo -e "${BOLD}=== Checking Kubernetes Removal ===${NC}"
    
    # Check kubectl command
    if ! command -v kubectl &>/dev/null; then
        pass "kubectl command removed"
    else
        fail "kubectl command still exists: $(which kubectl)"
    fi
    
    # Check kubeadm command
    if ! command -v kubeadm &>/dev/null; then
        pass "kubeadm command removed"
    else
        fail "kubeadm command still exists: $(which kubeadm)"
    fi
    
    # Check kubelet command
    if ! command -v kubelet &>/dev/null; then
        pass "kubelet command removed"
    else
        fail "kubelet command still exists: $(which kubelet)"
    fi
    
    # Check Kubernetes packages
    local k8s_packages=$(dpkg -l | grep -E 'kube|kubernetes' | wc -l)
    if [[ $k8s_packages -eq 0 ]]; then
        pass "No Kubernetes packages found"
    else
        fail "Kubernetes packages still installed: $k8s_packages"
        dpkg -l | grep -E 'kube|kubernetes'
    fi
    
    # Check Kubernetes directories
    if [[ ! -d /etc/kubernetes ]]; then
        pass "/etc/kubernetes directory removed"
    else
        fail "/etc/kubernetes directory still exists"
    fi
    
    if [[ ! -d /var/lib/kubelet ]]; then
        pass "/var/lib/kubelet directory removed"
    else
        fail "/var/lib/kubelet directory still exists"
    fi
    
    if [[ ! -d /var/lib/etcd ]]; then
        pass "/var/lib/etcd directory removed"
    else
        fail "/var/lib/etcd directory still exists"
    fi
    
    # Check kubectl configs
    if [[ ! -d /root/.kube ]]; then
        pass "Root kubectl config removed"
    else
        fail "Root kubectl config still exists"
    fi
    
    echo
}

check_container_runtime_removal() {
    echo -e "${BOLD}=== Checking Container Runtime Removal ===${NC}"
    
    # Check containerd command
    if ! command -v containerd &>/dev/null; then
        pass "containerd command removed"
    else
        fail "containerd command still exists: $(which containerd)"
    fi
    
    # Check docker command
    if ! command -v docker &>/dev/null; then
        pass "docker command removed"
    else
        fail "docker command still exists: $(which docker)"
    fi
    
    # Check crictl command
    if ! command -v crictl &>/dev/null; then
        pass "crictl command removed"
    else
        warn "crictl command still exists (may be part of other packages)"
    fi
    
    # Check container packages
    local container_packages=$(dpkg -l | grep -E 'containerd|docker' | grep -v 'docker-compose' | wc -l)
    if [[ $container_packages -eq 0 ]]; then
        pass "No container runtime packages found"
    else
        fail "Container runtime packages still installed: $container_packages"
        dpkg -l | grep -E 'containerd|docker'
    fi
    
    # Check container directories
    if [[ ! -d /var/lib/containerd ]]; then
        pass "/var/lib/containerd directory removed"
    else
        fail "/var/lib/containerd directory still exists"
    fi
    
    if [[ ! -d /var/lib/docker ]]; then
        pass "/var/lib/docker directory removed"
    else
        fail "/var/lib/docker directory still exists"
    fi
    
    echo
}

check_ha_components_removal() {
    echo -e "${BOLD}=== Checking HA Components Removal ===${NC}"
    
    # Check haproxy command
    if ! command -v haproxy &>/dev/null; then
        pass "haproxy command removed"
    else
        fail "haproxy command still exists: $(which haproxy)"
    fi
    
    # Check keepalived command
    if ! command -v keepalived &>/dev/null; then
        pass "keepalived command removed"
    else
        fail "keepalived command still exists: $(which keepalived)"
    fi
    
    # Check HA packages
    local ha_packages=$(dpkg -l | grep -E 'haproxy|keepalived' | wc -l)
    if [[ $ha_packages -eq 0 ]]; then
        pass "No HA packages found"
    else
        fail "HA packages still installed: $ha_packages"
        dpkg -l | grep -E 'haproxy|keepalived'
    fi
    
    # Check HA directories
    if [[ ! -d /etc/haproxy ]]; then
        pass "/etc/haproxy directory removed"
    else
        fail "/etc/haproxy directory still exists"
        ls -la /etc/haproxy/ 2>/dev/null || true
    fi
    
    if [[ ! -d /etc/keepalived ]]; then
        pass "/etc/keepalived directory removed"
    else
        fail "/etc/keepalived directory still exists"
        ls -la /etc/keepalived/ 2>/dev/null || true
    fi
    
    if [[ ! -d /var/lib/haproxy ]]; then
        pass "/var/lib/haproxy directory removed"
    else
        fail "/var/lib/haproxy directory still exists"
    fi
    
    echo
}

check_services_status() {
    echo -e "${BOLD}=== Checking Services Status ===${NC}"
    
    # Check that Kubernetes services are not running
    if ! systemctl is-active --quiet kubelet 2>/dev/null; then
        pass "kubelet service not running"
    else
        fail "kubelet service is still running"
    fi
    
    # Check that container services are not running
    if ! systemctl is-active --quiet containerd 2>/dev/null; then
        pass "containerd service not running"
    else
        fail "containerd service is still running"
    fi
    
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        pass "docker service not running"
    else
        fail "docker service is still running"
    fi
    
    # Check that HA services are not running
    if ! systemctl is-active --quiet haproxy 2>/dev/null; then
        pass "haproxy service not running"
    else
        fail "haproxy service is still running"
    fi
    
    if ! systemctl is-active --quiet keepalived 2>/dev/null; then
        pass "keepalived service not running"
    else
        fail "keepalived service is still running"
    fi
    
    echo
}

check_network_configuration() {
    echo -e "${BOLD}=== Checking Network Configuration ===${NC}"
    
    # Check for Kubernetes network interfaces
    local k8s_interfaces=$(ip link show | grep -E 'cali|flannel|weave|cni|docker|br-' | wc -l || echo "0")
    if [[ $k8s_interfaces -eq 0 ]]; then
        pass "No Kubernetes network interfaces found"
    else
        fail "Kubernetes network interfaces still exist: $k8s_interfaces"
        ip link show | grep -E 'cali|flannel|weave|cni|docker|br-'
    fi
    
    # Check CNI directories
    if [[ ! -d /etc/cni ]]; then
        pass "/etc/cni directory removed"
    else
        fail "/etc/cni directory still exists"
    fi
    
    if [[ ! -d /var/lib/cni ]]; then
        pass "/var/lib/cni directory removed"
    else
        fail "/var/lib/cni directory still exists"
    fi
    
    # Check netplan configuration
    if [[ -f /etc/netplan/50-cloud-init.yaml ]]; then
        if grep -q "dhcp4: true" /etc/netplan/50-cloud-init.yaml; then
            pass "Netplan reset to DHCP configuration"
        else
            warn "Netplan may still have custom configuration"
        fi
    else
        warn "Netplan configuration file not found"
    fi
    
    echo
}

check_system_configuration() {
    echo -e "${BOLD}=== Checking System Configuration ===${NC}"
    
    # Check custom sysctl files
    if [[ ! -f /etc/sysctl.d/k8s.conf ]]; then
        pass "Kubernetes sysctl configuration removed"
    else
        fail "Kubernetes sysctl configuration still exists"
    fi
    
    # Check custom kernel modules
    if [[ ! -f /etc/modules-load.d/k8s.conf ]]; then
        pass "Kubernetes kernel modules configuration removed"
    else
        fail "Kubernetes kernel modules configuration still exists"
    fi
    
    # Check /etc/hosts
    if ! grep -q "k8s-cp" /etc/hosts; then
        pass "/etc/hosts reset to basic configuration"
    else
        warn "/etc/hosts still contains k8s entries (may need manual cleanup)"
    fi
    
    # Check systemd overrides
    if [[ ! -d /etc/systemd/system/kubelet.service.d ]]; then
        pass "kubelet systemd overrides removed"
    else
        fail "kubelet systemd overrides still exist"
    fi
    
    echo
}

check_ports() {
    echo -e "${BOLD}=== Checking Port Usage ===${NC}"
    
    # Check Kubernetes API port
    local port_6443=$(netstat -tlnp 2>/dev/null | grep ":6443" | wc -l || echo "0")
    if [[ $port_6443 -eq 0 ]]; then
        pass "Port 6443 (Kubernetes API) is free"
    else
        fail "Port 6443 is still in use"
        netstat -tlnp | grep ":6443"
    fi
    
    # Check etcd ports
    local port_2379=$(netstat -tlnp 2>/dev/null | grep ":2379" | wc -l || echo "0")
    if [[ $port_2379 -eq 0 ]]; then
        pass "Port 2379 (etcd) is free"
    else
        fail "Port 2379 is still in use"
    fi
    
    # Check HAProxy stats port
    local port_8404=$(netstat -tlnp 2>/dev/null | grep ":8404" | wc -l || echo "0")
    if [[ $port_8404 -eq 0 ]]; then
        pass "Port 8404 (HAProxy stats) is free"
    else
        fail "Port 8404 is still in use"
    fi
    
    echo
}

check_package_system() {
    echo -e "${BOLD}=== Checking Package System ===${NC}"
    
    # Check for orphaned configuration packages
    local orphaned_packages=$(dpkg -l | grep '^rc' | wc -l || echo "0")
    if [[ $orphaned_packages -eq 0 ]]; then
        pass "No orphaned configuration packages"
    else
        warn "$orphaned_packages orphaned configuration packages found"
        dpkg -l | grep '^rc' | head -5
    fi
    
    # Check for broken packages
    local broken_packages=$(dpkg --audit | wc -l || echo "0")
    if [[ $broken_packages -eq 0 ]]; then
        pass "No broken packages found"
    else
        fail "$broken_packages broken packages found"
    fi
    
    echo
}

check_preserved_components() {
    echo -e "${BOLD}=== Checking Preserved Components ===${NC}"
    
    # Check SSH access
    if systemctl is-active --quiet ssh; then
        pass "SSH service is running"
    else
        fail "SSH service is not running"
    fi
    
    # Check SSH keys
    if [[ -d /root/.ssh ]] && [[ -f /root/.ssh/authorized_keys || -f /root/.ssh/id_rsa ]]; then
        pass "Root SSH keys preserved"
    else
        warn "Root SSH keys may not be preserved"
    fi
    
    # Check basic system
    if [[ -f /etc/os-release ]] && grep -q "Ubuntu 24.04" /etc/os-release; then
        pass "Ubuntu 24.04 system preserved"
    else
        warn "OS version check failed"
    fi
    
    # Check package manager
    if command -v apt &>/dev/null; then
        pass "Package manager (apt) available"
    else
        fail "Package manager not available"
    fi
    
    echo
}

check_storage_directories() {
    echo -e "${BOLD}=== Checking Storage Directories ===${NC}"
    
    # Check k8s storage directories
    if [[ ! -d /mnt/k8s-storage ]]; then
        pass "/mnt/k8s-storage directory removed"
    else
        fail "/mnt/k8s-storage directory still exists"
    fi
    
    if [[ ! -d /opt/kubernetes ]]; then
        pass "/opt/kubernetes directory removed"
    else
        fail "/opt/kubernetes directory still exists"
    fi
    
    echo
}

show_summary() {
    echo
    echo -e "${BOLD}################################################################"
    echo "#                                                              #"
    echo "#                    VERIFICATION SUMMARY                     #"
    echo "#                                                              #"
    echo "################################################################${NC}"
    echo
    echo -e "${GREEN}PASSED: $PASS_COUNT tests${NC}"
    echo -e "${YELLOW}WARNINGS: $WARN_COUNT tests${NC}"
    echo -e "${RED}FAILED: $FAIL_COUNT tests${NC}"
    echo
    
    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}🎉 RESET VERIFICATION SUCCESSFUL! 🎉${NC}"
        echo
        echo -e "${GREEN}The server has been successfully reset to clean Ubuntu 24.04 state.${NC}"
        echo -e "${GREEN}You can now proceed with fresh HA deployment.${NC}"
        echo
        echo -e "${BLUE}Next steps:${NC}"
        echo "1. Run this verification on all other servers"
        echo "2. Start fresh deployment with 01-server-preparation.sh"
    elif [[ $FAIL_COUNT -le 2 ]] && [[ $PASS_COUNT -gt 15 ]]; then
        echo -e "${YELLOW}${BOLD}⚠️ RESET MOSTLY SUCCESSFUL WITH MINOR ISSUES ⚠️${NC}"
        echo
        echo -e "${YELLOW}The reset was mostly successful but has a few issues.${NC}"
        echo -e "${YELLOW}Review the failed tests above and clean up manually if needed.${NC}"
    else
        echo -e "${RED}${BOLD}❌ RESET VERIFICATION FAILED ❌${NC}"
        echo
        echo -e "${RED}The reset did not complete successfully.${NC}"
        echo -e "${RED}Review the failed tests above and re-run the reset script.${NC}"
    fi
    
    echo
    echo -e "${BLUE}Server: $(hostname)${NC}"
    echo -e "${BLUE}Verification completed: $(date)${NC}"
}

main() {
    banner
    
    log "Starting reset verification on $(hostname)..."
    echo
    
    check_kubernetes_removal
    check_container_runtime_removal
    check_ha_components_removal
    check_services_status
    check_network_configuration
    check_system_configuration
    check_ports
    check_storage_directories
    check_package_system
    check_preserved_components
    
    show_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script verifies that 00-complete-reset.sh completed successfully."
        echo "Run this after the complete reset to ensure clean state."
        echo
        echo "The script checks:"
        echo "• Kubernetes components removal"
        echo "• Container runtime removal" 
        echo "• HA components removal"
        echo "• Service status"
        echo "• Network configuration"
        echo "• System configuration"
        echo "• Port availability"
        echo "• Preserved components (SSH, OS, etc.)"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac