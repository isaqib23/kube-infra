#!/bin/bash

# Staging Environment Configuration
# 2-Server Kubernetes Cluster Setup

export ENVIRONMENT="staging"
export KUBE_VERSION="1.34"
export CONTAINERD_VERSION="1.7.28"
export CALICO_VERSION="v3.30.1"

# Cluster configuration
export CLUSTER_NAME="staging-k8s-cluster"
export POD_NETWORK_CIDR="192.168.0.0/16"
export SERVICE_CIDR="10.96.0.0/12"

# Network configuration
export NETWORK_SUBNET="10.255.253.0/24"
export GATEWAY="10.255.253.1"
export VIP="10.255.253.100"

# Server configuration (2 servers for staging)
declare -gA SERVER_CONFIG=(
    ["k8s-stg1"]="10.255.253.10:150"  # IP:Priority
    ["k8s-stg2"]="10.255.253.11:140"
)

# Control plane endpoints
declare -gA CONTROL_PLANES=(
    ["k8s-stg1"]="10.255.253.10"
    ["k8s-stg2"]="10.255.253.11"
)

# Network interface (Dell R740 standard)
export VIP_INTERFACE="eno1"

# HA Configuration
export VRRP_ROUTER_ID="52"  # Different from production (51)
export VRRP_PASSWORD="k8s-stg24"

# Logging
export LOG_FILE="/var/log/staging-k8s-setup.log"

# Feature flags for staging
export ENABLE_MONITORING="true"
export ENABLE_INGRESS="true"
export ENABLE_BACKUP="true"
export MONITORING_RETENTION_DAYS="7"  # Shorter retention for staging

# Storage configuration
export STORAGE_BASE_PATH="/mnt/k8s-storage"

echo "Staging environment configuration loaded"
echo "Cluster: $CLUSTER_NAME"
echo "Servers: ${!SERVER_CONFIG[@]}"
echo "VIP: $VIP"
