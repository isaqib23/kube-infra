#!/bin/bash

# HA Load Balancer Setup Script for Kubernetes Cluster
# Run this script on ALL 4 Dell R740 servers
# Purpose: Configure HAProxy and Keepalived for Kubernetes API HA

set -euo pipefail

LOG_FILE="/var/log/ha-loadbalancer-setup.log"

# HA Configuration
VIP="10.255.254.100"
VIP_INTERFACE="eno1"  # Dell R740 standard interface
VRRP_ROUTER_ID="51"
VRRP_PASSWORD="k8s-ha24"

# Server configuration
declare -A SERVER_CONFIG=(
    ["k8s-cp1"]="10.255.254.10:150"  # IP:Priority
    ["k8s-cp2"]="10.255.254.11:140"
    ["k8s-cp3"]="10.255.254.12:130"
    ["k8s-cp4"]="10.255.254.13:120"
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
    echo "    HA Load Balancer Setup - HAProxy + Keepalived"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script configures HAProxy and Keepalived for Kubernetes"
    echo "API server high availability across 4 control plane nodes."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if keepalived and haproxy are installed
    if ! command -v keepalived &> /dev/null; then
        error "keepalived is not installed. Run 01-server-preparation.sh first"
    fi
    
    if ! command -v haproxy &> /dev/null; then
        error "haproxy is not installed. Run 01-server-preparation.sh first"
    fi
    
    # Check if this is one of our cluster nodes
    CURRENT_HOSTNAME=$(hostname)
    if [[ ! ${SERVER_CONFIG[$CURRENT_HOSTNAME]+_} ]]; then
        error "Unknown hostname: $CURRENT_HOSTNAME. Expected one of: ${!SERVER_CONFIG[*]}"
    fi
    
    # Extract IP and priority for this server
    IFS=':' read -r SERVER_IP SERVER_PRIORITY <<< "${SERVER_CONFIG[$CURRENT_HOSTNAME]}"
    
    success "Prerequisites check passed for $CURRENT_HOSTNAME ($SERVER_IP)"
}

detect_network_interface() {
    log "Detecting primary network interface..."
    
    # Get the interface used for the default route
    VIP_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$VIP_INTERFACE" ]]; then
        # Fallback: find first non-loopback interface
        VIP_INTERFACE=$(ip link show | grep -E '^[0-9]+:' | grep -v 'lo:' | head -1 | cut -d':' -f2 | tr -d ' ')
    fi
    
    if [[ -z "$VIP_INTERFACE" ]]; then
        error "Could not detect network interface. Please set VIP_INTERFACE manually"
    fi
    
    success "Detected network interface: $VIP_INTERFACE"
}

configure_keepalived() {
    log "Configuring Keepalived for VIP management..."
    
    # Determine VRRP state based on priority
    local vrrp_state="BACKUP"
    if [[ "$SERVER_PRIORITY" == "150" ]]; then
        vrrp_state="MASTER"
    fi
    
    # Create keepalived configuration
    cat > /etc/keepalived/keepalived.conf << EOF
! Configuration File for keepalived
! Kubernetes HA Cluster VIP Management

global_defs {
    router_id LVS_DEVEL
    vrrp_skip_check_adv_addr
    script_user root
    enable_script_security
}

# Script to check if local HAProxy is running
vrrp_script chk_haproxy {
    script "/bin/bash -c 'if systemctl is-active --quiet haproxy; then exit 0; else exit 1; fi'"
    interval 2
    weight -2
    fall 3
    rise 2
}

# VRRP instance for Kubernetes API VIP
vrrp_instance VI_1 {
    state $vrrp_state
    interface $VIP_INTERFACE
    virtual_router_id $VRRP_ROUTER_ID
    priority $SERVER_PRIORITY
    advert_int 1
    # Remove authentication in strict mode
    # authentication {
    #     auth_type PASS
    #     auth_pass $VRRP_PASSWORD
    # }
    virtual_ipaddress {
        $VIP/24
    }
    track_script {
        chk_haproxy
    }
    notify_master "/bin/echo 'Became MASTER for VIP $VIP' | systemd-cat -t keepalived"
    notify_backup "/bin/echo 'Became BACKUP for VIP $VIP' | systemd-cat -t keepalived"
    notify_fault "/bin/echo 'Fault detected for VIP $VIP' | systemd-cat -t keepalived"
}
EOF
    
    success "Keepalived configuration created for $CURRENT_HOSTNAME (priority: $SERVER_PRIORITY, state: $vrrp_state)"
}

configure_haproxy() {
    log "Configuring HAProxy for Kubernetes API load balancing..."
    
    # Backup original configuration
    if [[ -f /etc/haproxy/haproxy.cfg ]]; then
        cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Create HAProxy configuration
    cat > /etc/haproxy/haproxy.cfg << EOF
#---------------------------------------------------------------------
# HAProxy Configuration for Kubernetes HA Cluster
# Dell R740 4-Node Setup
#---------------------------------------------------------------------

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Increase default limits for high-performance server
    maxconn 4096
    tune.ssl.default-dh-param 2048

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option log-health-checks
    option redispatch
    retries 3
    timeout http-request 10s
    timeout queue 1m
    timeout connect 10s
    timeout client 1m
    timeout server 1m
    timeout http-keep-alive 10s
    timeout check 10s
    maxconn 3000

#---------------------------------------------------------------------
# Statistics interface (optional)
#---------------------------------------------------------------------
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

#---------------------------------------------------------------------
# Kubernetes API Server Frontend
#---------------------------------------------------------------------
frontend kubernetes-api
    # Only bind to VIP on MASTER node, bind to local IP on BACKUP nodes
    bind $SERVER_IP:6443
    bind 127.0.0.1:6443
    mode tcp
    option tcplog
    default_backend kubernetes-api-backend

#---------------------------------------------------------------------
# Kubernetes API Server Backend
#---------------------------------------------------------------------
backend kubernetes-api-backend
    mode tcp
    option tcp-check
    balance roundrobin
    
    # Health check for Kubernetes API
    tcp-check connect
    tcp-check send "GET /healthz HTTP/1.0\r\n\r\n"
    tcp-check expect string "ok"
    
    # Control plane servers
EOF

    # Add all control plane servers to backend
    for server in "${!SERVER_CONFIG[@]}"; do
        IFS=':' read -r ip priority <<< "${SERVER_CONFIG[$server]}"
        echo "    server $server $ip:6443 check inter 5s rise 2 fall 3" >> /etc/haproxy/haproxy.cfg
    done
    
    # Add additional backends for other services if needed
    cat >> /etc/haproxy/haproxy.cfg << EOF

#---------------------------------------------------------------------
# HTTP Ingress Frontend (for future use)
#---------------------------------------------------------------------
frontend http-ingress
    bind $SERVER_IP:80
    bind 127.0.0.1:80
    mode http
    redirect scheme https code 301 if !{ ssl_fc }
    default_backend ingress-http-backend

#---------------------------------------------------------------------
# HTTPS Ingress Frontend (for future use)
#---------------------------------------------------------------------
frontend https-ingress
    bind $SERVER_IP:443
    bind 127.0.0.1:443
    mode tcp
    option tcplog
    default_backend ingress-https-backend

#---------------------------------------------------------------------
# HTTP Ingress Backend
#---------------------------------------------------------------------
backend ingress-http-backend
    mode http
    balance roundrobin
    option httpchk GET /healthz
    # Servers will be added by ingress setup script
    server placeholder 127.0.0.1:30080 check backup

#---------------------------------------------------------------------
# HTTPS Ingress Backend
#---------------------------------------------------------------------
backend ingress-https-backend
    mode tcp
    balance roundrobin
    # Servers will be added by ingress setup script
    server placeholder 127.0.0.1:30443 check backup
EOF
    
    success "HAProxy configuration created with load balancing for all control planes"
}

create_haproxy_service_override() {
    log "Creating HAProxy service override for HA setup..."
    
    # Create systemd override directory
    mkdir -p /etc/systemd/system/haproxy.service.d
    
    # Create override configuration
    cat > /etc/systemd/system/haproxy.service.d/override.conf << EOF
[Unit]
# Ensure HAProxy starts after network is fully up
After=network-online.target
Wants=network-online.target

[Service]
# Restart HAProxy if it fails
Restart=always
RestartSec=5
StartLimitInterval=0

# Run configuration check before starting
ExecStartPre=/usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -c -q
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    success "HAProxy service override created"
}

configure_rsyslog() {
    log "Configuring rsyslog for HAProxy and Keepalived logging..."
    
    # Create rsyslog configuration for HAProxy
    cat > /etc/rsyslog.d/49-haproxy.conf << EOF
# HAProxy log handling
\$ModLoad imudp
\$UDPServerRun 514
\$UDPServerAddress 127.0.0.1
local0.*    /var/log/haproxy.log
& stop
EOF
    
    # Create rsyslog configuration for Keepalived
    cat > /etc/rsyslog.d/50-keepalived.conf << EOF
# Keepalived log handling
local1.*    /var/log/keepalived.log
& stop
EOF
    
    # Restart rsyslog
    systemctl restart rsyslog
    
    success "Rsyslog configured for HA services"
}

setup_log_rotation() {
    log "Setting up log rotation for HA services..."
    
    # Create logrotate configuration for HAProxy
    cat > /etc/logrotate.d/haproxy << EOF
/var/log/haproxy.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    create 644 syslog adm
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    # Create logrotate configuration for Keepalived
    cat > /etc/logrotate.d/keepalived << EOF
/var/log/keepalived.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    create 644 syslog adm
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    success "Log rotation configured"
}

validate_configuration() {
    log "Validating HAProxy and Keepalived configurations..."
    
    # Validate HAProxy configuration
    if ! haproxy -f /etc/haproxy/haproxy.cfg -c; then
        error "HAProxy configuration validation failed"
    fi
    
    # Check keepalived configuration syntax
    if ! keepalived -t -f /etc/keepalived/keepalived.conf; then
        error "Keepalived configuration validation failed"
    fi
    
    success "Configuration validation passed"
}

start_services() {
    log "Starting and enabling HA services..."
    
    # Enable and start HAProxy
    systemctl enable haproxy
    systemctl restart haproxy
    
    # Enable and start Keepalived
    systemctl enable keepalived
    systemctl restart keepalived
    
    # Wait a moment for services to start
    sleep 5
    
    # Check service status
    if ! systemctl is-active --quiet haproxy; then
        error "HAProxy failed to start. Check logs: journalctl -u haproxy"
    fi
    
    if ! systemctl is-active --quiet keepalived; then
        error "Keepalived failed to start. Check logs: journalctl -u keepalived"
    fi
    
    success "HA services started successfully"
}

test_vip_assignment() {
    log "Testing VIP assignment..."
    
    # Wait for VIP assignment
    local timeout=30
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if ip addr show | grep -q "$VIP"; then
            success "VIP $VIP assigned to this server"
            return 0
        fi
        sleep 1
        ((counter++))
    done
    
    warning "VIP not assigned to this server (this is normal for backup nodes)"
    return 0
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Load Balancer Setup Completed!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Configuration Summary ==="
    echo "Server: $CURRENT_HOSTNAME ($SERVER_IP)"
    echo "VIP: $VIP"
    echo "Priority: $SERVER_PRIORITY"
    echo "Interface: $VIP_INTERFACE"
    echo
    echo "=== Service Status ==="
    echo "HAProxy: $(systemctl is-active haproxy)"
    echo "Keepalived: $(systemctl is-active keepalived)"
    echo
    echo "=== VIP Status ==="
    if ip addr show | grep -q "$VIP"; then
        echo "✓ VIP $VIP is assigned to this server (MASTER)"
    else
        echo "○ VIP $VIP is not assigned to this server (BACKUP)"
    fi
    echo
    echo "=== Useful Commands ==="
    echo "Check HAProxy status: systemctl status haproxy"
    echo "Check Keepalived status: systemctl status keepalived"
    echo "View HAProxy stats: http://any-server-ip:8404/stats"
    echo "Check VIP assignment: ip addr show | grep $VIP"
    echo "HAProxy logs: tail -f /var/log/haproxy.log"
    echo "Keepalived logs: tail -f /var/log/keepalived.log"
    echo
    echo "=== Next Steps ==="
    echo "1. Run this script on all remaining servers"
    echo "2. Verify VIP failover by stopping services on MASTER"
    echo "3. Run 03-ha-cluster-init.sh on k8s-cp1 to initialize cluster"
    echo
    echo -e "${GREEN}Load balancer setup completed on $CURRENT_HOSTNAME!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    detect_network_interface
    
    log "Starting HA load balancer setup on $CURRENT_HOSTNAME..."
    
    # Configure HA components
    configure_keepalived
    configure_haproxy
    create_haproxy_service_override
    configure_rsyslog
    setup_log_rotation
    
    # Validate and start services
    validate_configuration
    start_services
    test_vip_assignment
    
    show_completion_info
    
    success "HA load balancer setup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script configures HAProxy and Keepalived for Kubernetes API HA."
        echo "Run this script on ALL 4 Dell R740 servers after server preparation."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac