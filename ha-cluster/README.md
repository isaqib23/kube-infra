# High Availability Kubernetes Cluster Scripts
## 4x Dell PowerEdge R740 Servers

This directory contains all the scripts and configurations needed to deploy a production-ready High Availability Kubernetes cluster on 4 Dell PowerEdge R740 servers.

## Architecture Overview
- **4 servers**: All acting as both control-plane and worker nodes
- **Stacked etcd**: Distributed across all 4 nodes
- **Load Balancing**: HAProxy + Keepalived for API HA
- **Networking**: Calico CNI with BGP for HA networking
- **Storage**: Distributed storage with multiple tiers
- **Monitoring**: Full observability stack with HA configuration

## Script Execution Order

### Phase 1: Preparation
1. **`01-server-preparation.sh`** - Run on all 4 servers to prepare the base system
2. **`02-ha-loadbalancer-setup.sh`** - Configure HAProxy and Keepalived on all servers

### Phase 2: Cluster Bootstrap
3. **`03-ha-cluster-init.sh`** - Initialize the first control plane (run on k8s-cp1)
4. **`04-ha-cluster-join.sh`** - Join remaining control planes (run on k8s-cp2, cp3, cp4)

### Phase 3: Infrastructure Services
5. **`05-ha-storage-setup.sh`** - Configure distributed storage (run on k8s-cp1)
6. **`06-ha-ingress-setup.sh`** - Deploy HA ingress controller (run on k8s-cp1)
7. **`07-ha-monitoring-setup.sh`** - Deploy monitoring stack (run on k8s-cp1)

### Phase 4: Validation
8. **`08-cluster-validation.sh`** - Comprehensive cluster testing (run on k8s-cp1)
9. **`09-ha-master-deploy.sh`** - Master orchestration script (coordinates all phases)

## Configuration Files
- **`configs/`** - HAProxy, Keepalived, and other configuration templates
- **`templates/`** - Kubernetes manifest templates for HA setup
- **`validation/`** - Test workloads and validation scripts

## Server Information
```
k8s-cp1: 192.168.1.10 (Primary control plane)
k8s-cp2: 192.168.1.11 (Secondary control plane)
k8s-cp3: 192.168.1.12 (Secondary control plane)
k8s-cp4: 192.168.1.13 (Secondary control plane)
VIP:     192.168.1.100 (Virtual IP for API access)
```

## Prerequisites
- 4x Dell PowerEdge R740 servers with fresh Ubuntu 24.04 installation
- Network connectivity between all servers
- Root/sudo access on all servers
- DNS resolution for hostnames (or /etc/hosts configured)

## Quick Start
1. Clone this repository to k8s-cp1
2. Run `./09-ha-master-deploy.sh` for automated deployment
3. Or follow the step-by-step approach using individual scripts

## Support
- Review `../HA_DEPLOYMENT_PLAN.md` for detailed planning information
- Check individual script headers for specific requirements
- Validate network connectivity before starting deployment