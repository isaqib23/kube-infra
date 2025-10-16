#!/bin/bash

# Development Environment Configuration
# Single-Node Kubernetes Cluster Setup

export ENVIRONMENT="development"
export KUBE_VERSION="1.34"
export CONTAINERD_VERSION="1.7.28"
export CALICO_VERSION="v3.30.1"

# Cluster configuration
export CLUSTER_NAME="dev-k8s-cluster"
export POD_NETWORK_CIDR="192.168.0.0/16"
export SERVICE_CIDR="10.96.0.0/12"

# Network configuration (single node, no VIP needed)
export NETWORK_SUBNET="10.255.252.0/24"
export GATEWAY="10.255.252.1"
export SERVER_IP="10.255.252.10"
export SERVER_NAME="k8s-dev1"

# No VIP for single-node cluster
export VIP=""
export VIP_INTERFACE="eno1"

# Logging
export LOG_FILE="/var/log/dev-k8s-setup.log"

# Feature flags for development
export ENABLE_MONITORING="true"
export ENABLE_INGRESS="true"
export ENABLE_BACKUP="false"  # No backup needed for dev
export MONITORING_RETENTION_DAYS="3"  # Minimal retention for dev

# Storage configuration
export STORAGE_BASE_PATH="/mnt/k8s-storage"

# Development-specific settings
export ENABLE_METRICS_SERVER="true"
export ENABLE_DASHBOARD="true"

echo "Development environment configuration loaded"
echo "Cluster: $CLUSTER_NAME"
echo "Server: $SERVER_NAME ($SERVER_IP)"
echo "Single-node setup (no HA)"
