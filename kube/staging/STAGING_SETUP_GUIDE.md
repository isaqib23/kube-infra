# Staging Environment Setup Guide
## 2-Server Kubernetes Cluster Deployment

---

## Overview

This guide covers the deployment of a **2-node Staging Kubernetes cluster** on Dell PowerEdge R740 servers. The staging environment provides limited high availability suitable for pre-production testing.

### Environment Specifications

| Component | Specification |
|-----------|--------------|
| **Servers** | 2x Dell PowerEdge R740 |
| **Network** | 10.255.253.0/24 |
| **VIP** | 10.255.253.100 |
| **Nodes** | k8s-stg1, k8s-stg2 |
| **Architecture** | 2-node control-plane with etcd |
| **HA Level** | Limited (2/2 quorum - zero fault tolerance) |

### Server Configuration

| Server | IP Address | Priority | Role |
|--------|-----------|----------|------|
| k8s-stg1 | 10.255.253.10 | 150 | Control Plane + Worker (Primary) |
| k8s-stg2 | 10.255.253.11 | 140 | Control Plane + Worker |
| k8s-stg-api | 10.255.253.100 | - | Virtual IP (Floating) |

---

## Important Notes

### Limitations

⚠️ **Zero Fault Tolerance**: This 2-node cluster requires BOTH nodes to be operational for etcd quorum. If one node fails, the cluster will stop functioning.

### Differences from Production

- **2 nodes** instead of 4
- **No fault tolerance** (requires both nodes operational)
- **Shorter data retention** (7 days vs 30 days)
- **Lighter monitoring** (reduced resource allocation)

---

## Prerequisites

### Hardware Requirements

- 2x Dell PowerEdge R740 servers
- Each server with minimum:
  - 32 CPU cores
  - 128GB RAM
  - 500GB storage
- 2x Network switches for redundancy (same as production)
- Redundant power supplies per server

### Software Requirements

- Fresh Ubuntu 24.04 LTS on both servers
- Root/sudo access
- Static IP addresses configured
- Internet connectivity for package downloads

---

## Deployment Steps

### Phase 1: Server Preparation

Run on **BOTH** servers (k8s-stg1 and k8s-stg2):

```bash
# On each server
cd /path/to/staging/
sudo ./01-server-preparation.sh
```

This script will:
- Configure hostname and network
- Install Kubernetes components (v1.34)
- Install containerd
- Install HAProxy and Keepalived
- Configure firewall rules
- Disable swap
- Set up kernel parameters

**Expected time**: 15-20 minutes per server

### Phase 2: Load Balancer Setup

Run on **BOTH** servers:

```bash
# On each server
sudo ./02-ha-loadbalancer-setup.sh
```

This script will:
- Configure Keepalived for VIP management
- Configure HAProxy for API load balancing
- Set up logging and log rotation
- Start HA services

**Verification**:
```bash
# Check VIP assignment (should be on k8s-stg1)
ip addr show | grep 10.255.253.100

# Check HAProxy status
systemctl status haproxy

# Check Keepalived status
systemctl status keepalived
```

### Phase 3: Cluster Initialization

Run **ONLY** on k8s-stg1 (first control plane):

```bash
# On k8s-stg1 only
sudo ./03-ha-cluster-init.sh
```

This script will:
- Initialize Kubernetes cluster
- Install Calico CNI
- Install metrics server
- Install Helm
- Generate join commands
- Set up etcd backup

**Expected time**: 15-20 minutes

**Verification**:
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Test API via VIP
kubectl --server=https://10.255.253.100:6443 get nodes
```

### Phase 4: Join Second Control Plane

Run **ONLY** on k8s-stg2:

```bash
# On k8s-stg2 only
sudo ./04-ha-cluster-join.sh
```

This script will:
- Join k8s-stg2 as second control plane
- Add to etcd cluster
- Configure kubectl access

**Expected time**: 10-15 minutes

**Verification**:
```bash
# On any node, check both nodes are Ready
kubectl get nodes

# Check etcd cluster members
kubectl exec -n kube-system etcd-k8s-stg1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

### Phase 5: Storage Setup

Run on **BOTH** servers:

```bash
# On each server
sudo ./05-ha-storage-setup.sh
```

This creates local storage classes:
- `fast-ssd-storage` - High-performance storage
- `standard-storage` - General purpose
- `backup-storage` - For backups (reduced retention)
- `logs-storage` - For log aggregation

### Phase 6: Ingress Controller

Run **ONCE** (on k8s-stg1):

```bash
# On k8s-stg1
sudo ./06-ha-ingress-setup.sh
```

Deploys NGINX Ingress Controller with:
- 2 replicas (one per node)
- NodePort 30080 (HTTP) and 30443 (HTTPS)
- Cert-manager for TLS

### Phase 7: Monitoring Stack

Run **ONCE** (on k8s-stg1):

```bash
# On k8s-stg1
sudo ./07-ha-monitoring-setup.sh
```

Deploys:
- Prometheus (7-day retention)
- Grafana
- AlertManager
- Loki + Promtail
- Node Exporter

**Access**:
```bash
# Port-forward to access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Default: admin / prom-operator
```

### Phase 8: Validation

Run on **k8s-stg1**:

```bash
sudo ./08-cluster-validation.sh
```

Validates:
- Node health
- Pod status
- Network connectivity
- DNS resolution
- Storage classes
- Ingress functionality

---

## Post-Deployment

### Accessing the Cluster

**From any node**:
```bash
kubectl get nodes
kubectl get pods -A
```

**From remote machine**:
```bash
# Copy kubeconfig from k8s-stg1
scp root@10.255.253.10:/root/.kube/config ~/.kube/staging-config

# Use it
export KUBECONFIG=~/.kube/staging-config
kubectl get nodes
```

### Daily Operations

**Health Checks**:
```bash
# Check nodes
kubectl get nodes

# Check critical pods
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# Check etcd health
kubectl exec -n kube-system etcd-k8s-stg1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

**Backup Verification**:
```bash
# Check recent backups
ls -lh /opt/kubernetes/backups/

# Manual backup
sudo /opt/kubernetes/etcd-backup.sh
```

---

## Disaster Recovery

### ⚠️ Critical: Both Nodes Required

Unlike production (which can survive 1 node failure), staging requires **BOTH** nodes operational at all times.

### Recovering from Single Node Failure

If one node fails:

1. **Immediate impact**: Cluster becomes read-only (etcd loses quorum)
2. **Action**: Restore the failed node ASAP
3. **Recovery**:
   ```bash
   # On recovered node
   systemctl start kubelet
   systemctl start containerd

   # Verify it rejoins
   kubectl get nodes
   ```

### Complete Cluster Recovery

If both nodes fail:

1. Restore k8s-stg1 first from etcd backup
2. Then restore k8s-stg2
3. See production documentation for detailed etcd restore procedures

---

## Scaling to Production

When ready to promote to production:

1. Add 2 more servers (k8s-cp3, k8s-cp4)
2. Update network to 10.255.254.0/24
3. Re-run production scripts
4. Or migrate workloads to separate production cluster

---

## Troubleshooting

### Common Issues

**Issue**: VIP not accessible
```bash
# Check Keepalived on both nodes
systemctl status keepalived

# Check VIP assignment
ip addr show | grep 10.255.253.100

# Restart if needed
systemctl restart keepalived
```

**Issue**: etcd unhealthy
```bash
# Check both etcd members
kubectl get pods -n kube-system | grep etcd

# Describe for errors
kubectl describe pod -n kube-system etcd-k8s-stg1
kubectl describe pod -n kube-system etcd-k8s-stg2
```

**Issue**: Pods stuck in Pending
```bash
# Check node resources
kubectl top nodes
kubectl describe node k8s-stg1
kubectl describe node k8s-stg2

# Check for taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

---

## Support and Escalation

For staging environment issues:

1. Check this documentation
2. Review logs: `/var/log/staging-k8s-setup.log`
3. Check Kubernetes events: `kubectl get events -A --sort-by='.lastTimestamp'`
4. Escalate to infrastructure team if unresolved

---

## Appendix: Quick Reference

### Staging Server IPs
```
k8s-stg1:     10.255.253.10
k8s-stg2:     10.255.253.11
VIP:          10.255.253.100
Gateway:      10.255.253.1
```

### Key Services
```
Kubernetes API:   https://10.255.253.100:6443
HAProxy Stats:    http://10.255.253.10:8404/stats
Ingress HTTP:     NodePort 30080
Ingress HTTPS:    NodePort 30443
```

### Useful Commands
```bash
# Cluster info
kubectl cluster-info

# All pods
kubectl get pods -A

# Node status
kubectl get nodes -o wide

# Describe node
kubectl describe node k8s-stg1

# etcd health
kubectl exec -n kube-system etcd-k8s-stg1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

---

**Document Version**: 1.0
**Environment**: Staging (2-node)
**Last Updated**: October 2025
**Status**: Ready for Deployment
