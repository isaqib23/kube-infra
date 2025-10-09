#!/bin/bash

# HAProxy Diagnostic Script
# Run this to diagnose HAProxy issues

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== HAProxy Diagnostic Report ===${NC}"
echo

echo -e "${BLUE}1. Checking VIP assignment...${NC}"
if ip addr show | grep -q "10.255.254.100"; then
    echo -e "${GREEN}✓ VIP 10.255.254.100 is assigned to this server${NC}"
    ip addr show | grep "10.255.254.100"
else
    echo -e "${YELLOW}⚠ VIP 10.255.254.100 is NOT assigned to this server${NC}"
fi
echo

echo -e "${BLUE}2. Checking port 6443 usage...${NC}"
if netstat -tlnp | grep -q ":6443"; then
    echo -e "${YELLOW}⚠ Port 6443 is already in use:${NC}"
    netstat -tlnp | grep ":6443"
else
    echo -e "${GREEN}✓ Port 6443 is available${NC}"
fi
echo

echo -e "${BLUE}3. HAProxy service status...${NC}"
systemctl status haproxy --no-pager || true
echo

echo -e "${BLUE}4. HAProxy configuration (frontend kubernetes-api)...${NC}"
grep -A 10 "frontend kubernetes-api" /etc/haproxy/haproxy.cfg || echo "Not found"
echo

echo -e "${BLUE}5. HAProxy validation...${NC}"
haproxy -f /etc/haproxy/haproxy.cfg -c 2>&1 || echo "Validation failed"
echo

echo -e "${BLUE}6. Recent HAProxy logs...${NC}"
journalctl -u haproxy --no-pager -n 30 --since "5 minutes ago"
echo

echo -e "${BLUE}7. Keepalived status...${NC}"
systemctl status keepalived --no-pager || true
echo

echo -e "${BLUE}8. Kubernetes API server status...${NC}"
if netstat -tlnp | grep -q "kube-apiserver.*:6443"; then
    echo -e "${GREEN}✓ kube-apiserver is running on port 6443${NC}"
    netstat -tlnp | grep "kube-apiserver.*:6443"
else
    echo -e "${RED}✗ kube-apiserver is not listening on port 6443${NC}"
fi
echo

echo -e "${BLUE}=== Diagnostic Report Complete ===${NC}"
echo
echo "Recommendations:"
echo "1. If VIP is not assigned and HAProxy tries to bind to it → Edit HAProxy config to bind to server IP only"
echo "2. If port 6443 is in use by kube-apiserver → HAProxy should bind to a different IP or the VIP"
echo "3. If validation fails → Check the error message above for syntax issues"
