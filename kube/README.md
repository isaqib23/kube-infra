# Kubernetes Infrastructure - Multi-Environment Setup
## Production, Staging, and Development Clusters

---

## Overview

This repository contains automated deployment scripts and documentation for Kubernetes clusters across three environments:

- **Production**: 4-server high availability cluster
- **Staging**: 2-server limited HA cluster
- **Development**: Single-node development cluster

All environments run on Dell PowerEdge R740 servers with Ubuntu 24.04 LTS.

---

## Directory Structure

```
kube/
├── production/          # 4-server production cluster (10.255.254.0/24)
│   ├── Scripts (01-09)
│   ├── INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md
│   ├── HA_DEPLOYMENT_PLAN.md
│   └── r740_server.md
│
├── staging/             # 2-server staging cluster (10.255.253.0/24)
│   ├── Scripts (01-09)
│   ├── STAGING_SETUP_GUIDE.md
│   └── env-config.sh
│
├── development/         # 1-server dev cluster (10.255.252.0/24)
│   ├── Scripts (01-09, except 04)
│   ├── DEVELOPMENT_SETUP_GUIDE.md
│   └── env-config.sh
│
└── common/              # Shared utilities
    ├── common-functions.sh
    └── adapt-scripts.sh
```

---

## Environment Comparison

| Feature | Production | Staging | Development |
|---------|-----------|---------|-------------|
| **Servers** | 4 | 2 | 1 |
| **Network** | 10.255.254.0/24 | 10.255.253.0/24 | 10.255.252.0/24 |
| **VIP** | 10.255.254.100 | 10.255.253.100 | None |
| **HA** | Full (3/4 quorum) | Limited (2/2) | None |
| **Fault Tolerance** | 1 node | 0 nodes | 0 nodes |
| **Use Case** | Production workloads | Pre-prod testing | Development & testing |
| **Monitoring Retention** | 30 days | 7 days | 3 days |
| **Backups** | Daily, 30 days | Daily, 7 days | Disabled |

---

## Quick Start

### Production (4 servers)

```bash
cd production/

# On all 4 servers
./01-server-preparation.sh
./02-ha-loadbalancer-setup.sh

# On k8s-cp1 only
./03-ha-cluster-init.sh

# On k8s-cp2, k8s-cp3, k8s-cp4
./04-ha-cluster-join.sh

# Continue with storage, ingress, monitoring, validation
./05-ha-storage-setup.sh
./06-ha-ingress-setup.sh
./07-ha-monitoring-setup.sh
./08-cluster-validation.sh
```

See [INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md](production/INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md) for full details.

### Staging (2 servers)

```bash
cd staging/

# On both k8s-stg1 and k8s-stg2
./01-server-preparation.sh
./02-ha-loadbalancer-setup.sh

# On k8s-stg1 only
./03-ha-cluster-init.sh

# On k8s-stg2 only
./04-ha-cluster-join.sh

# Continue with remaining scripts
./05-ha-storage-setup.sh
./06-ha-ingress-setup.sh
./07-ha-monitoring-setup.sh
./08-cluster-validation.sh
```

See [STAGING_SETUP_GUIDE.md](staging/STAGING_SETUP_GUIDE.md) for full details.

### Development (1 server)

```bash
cd development/

# On k8s-dev1
./01-server-preparation.sh
./03-ha-cluster-init.sh  # Note: Skip 02 (no HA needed)
./05-ha-storage-setup.sh
./06-ha-ingress-setup.sh
./07-ha-monitoring-setup.sh
./08-cluster-validation.sh
```

See [DEVELOPMENT_SETUP_GUIDE.md](development/DEVELOPMENT_SETUP_GUIDE.md) for full details.

---

## Network Configuration

### Production
- **Network**: 10.255.254.0/24
- **Nodes**: k8s-cp1 (.10), k8s-cp2 (.11), k8s-cp3 (.12), k8s-cp4 (.13)
- **VIP**: 10.255.254.100
- **Gateway**: 10.255.254.1
- **Switches**: 2 (redundant)

### Staging
- **Network**: 10.255.253.0/24
- **Nodes**: k8s-stg1 (.10), k8s-stg2 (.11)
- **VIP**: 10.255.253.100
- **Gateway**: 10.255.253.1
- **Switches**: 2 (redundant)

### Development
- **Network**: 10.255.252.0/24
- **Node**: k8s-dev1 (.10)
- **VIP**: None (single node)
- **Gateway**: 10.255.252.1
- **Switches**: 2 (redundant, shared infrastructure)

---

## Deployment Scripts

### Common Scripts (All Environments)

1. **01-server-preparation.sh**
   - OS configuration
   - Network setup
   - Kubernetes installation
   - Firewall configuration

2. **02-ha-loadbalancer-setup.sh**
   - HAProxy configuration
   - Keepalived setup
   - VIP management
   - *(Skip for single-node dev)*

3. **03-ha-cluster-init.sh**
   - Cluster initialization
   - Calico CNI installation
   - Metrics server
   - Helm installation

4. **04-ha-cluster-join.sh**
   - Join additional control planes
   - *(Not used in dev environment)*

5. **05-ha-storage-setup.sh**
   - Storage class creation
   - PV provisioning
   - Backup storage

6. **06-ha-ingress-setup.sh**
   - NGINX Ingress Controller
   - Cert-manager
   - TLS configuration

7. **07-ha-monitoring-setup.sh**
   - Prometheus stack
   - Grafana
   - Loki + Promtail
   - AlertManager

8. **08-cluster-validation.sh**
   - Health checks
   - Network tests
   - DNS validation
   - Storage verification

9. **09-ha-master-deploy.sh**
   - Master orchestration script
   - Automated deployment

---

## Prerequisites

### Hardware
- Dell PowerEdge R740 servers
- Minimum per server:
  - 32 CPU cores
  - 128GB RAM
  - 500GB storage
- Network switches (2 for redundancy)
- Redundant power supplies

### Software
- Ubuntu 24.04 LTS (fresh installation)
- Root/sudo access
- Static IP addresses configured
- Internet connectivity for package downloads

---

## Component Versions

| Component | Version |
|-----------|---------|
| Kubernetes | 1.34.0 |
| Containerd | 1.7.28 |
| Calico CNI | v3.30.1 |
| HAProxy | Latest (from apt) |
| Keepalived | Latest (from apt) |
| NGINX Ingress | Latest (from Helm) |
| Prometheus Stack | Latest (from Helm) |

---

## Access and Credentials

### Production
```bash
# SSH
ssh root@10.255.254.10  # k8s-cp1
ssh root@10.255.254.11  # k8s-cp2
ssh root@10.255.254.12  # k8s-cp3
ssh root@10.255.254.13  # k8s-cp4

# Kubernetes API
kubectl --server=https://10.255.254.100:6443 get nodes
```

### Staging
```bash
# SSH
ssh root@10.255.253.10  # k8s-stg1
ssh root@10.255.253.11  # k8s-stg2

# Kubernetes API
kubectl --server=https://10.255.253.100:6443 get nodes
```

### Development
```bash
# SSH
ssh root@10.255.252.10  # k8s-dev1

# Kubernetes API (direct, no VIP)
kubectl --server=https://10.255.252.10:6443 get nodes
```

---

## Common Operations

### Accessing Kubernetes

**From any cluster node**:
```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

**From remote machine**:
```bash
# Production
scp root@10.255.254.10:/root/.kube/config ~/.kube/prod-config
export KUBECONFIG=~/.kube/prod-config

# Staging
scp root@10.255.253.10:/root/.kube/config ~/.kube/staging-config
export KUBECONFIG=~/.kube/staging-config

# Development
scp root@10.255.252.10:/root/.kube/config ~/.kube/dev-config
export KUBECONFIG=~/.kube/dev-config
```

### Health Checks

```bash
# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check etcd health (production/staging)
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

### Monitoring Access

```bash
# Port-forward Grafana (any environment)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser to http://localhost:3000
# Default credentials: admin / prom-operator
```

---

## Backup and Recovery

### Production
- **etcd backups**: Daily at 02:00 AM
- **Retention**: 30 days
- **Location**: `/opt/kubernetes/backups/`
- **Manual backup**: `/opt/kubernetes/etcd-backup.sh`

### Staging
- **etcd backups**: Daily at 02:00 AM
- **Retention**: 7 days
- **Location**: `/opt/kubernetes/backups/`

### Development
- **etcd backups**: Disabled
- **Manual backup**: Available if needed

---

## Troubleshooting

### Common Issues

**VIP not accessible** (Production/Staging):
```bash
systemctl status keepalived
ip addr show | grep <VIP>
journalctl -u keepalived -f
```

**Pods stuck in Pending**:
```bash
kubectl describe pod <pod-name>
kubectl top nodes
kubectl get events -A --sort-by='.lastTimestamp'
```

**DNS resolution issues**:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
kubectl run test-dns --image=busybox:1.28 --rm -it -- nslookup kubernetes.default
```

**etcd unhealthy** (Production/Staging):
```bash
kubectl get pods -n kube-system | grep etcd
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl member list
```

See environment-specific documentation for detailed troubleshooting.

---

## Upgrading Between Environments

### Development → Staging
1. Export application manifests from dev
2. Review and adjust resource allocations
3. Deploy to staging for testing
4. Validate with real workload patterns

### Staging → Production
1. Full testing completed in staging
2. Performance testing validated
3. Security review completed
4. Backup strategy verified
5. Deploy to production with monitoring

**Never skip staging when moving to production!**

---

## Support and Documentation

### Environment-Specific Guides
- **Production**: [INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md](production/INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md)
- **Staging**: [STAGING_SETUP_GUIDE.md](staging/STAGING_SETUP_GUIDE.md)
- **Development**: [DEVELOPMENT_SETUP_GUIDE.md](development/DEVELOPMENT_SETUP_GUIDE.md)

### Additional Resources
- Kubernetes Official Docs: https://kubernetes.io/docs/
- Calico Documentation: https://docs.tigera.io/calico/latest/
- Helm Documentation: https://helm.sh/docs/

---

## Contributing

When modifying scripts:

1. **Test in development first**
2. **Validate in staging**
3. **Review before production**
4. **Update documentation**
5. **Keep environment configs in sync**

---

## Maintenance Schedule

### Daily
- Monitor cluster health
- Check backup completion
- Review alerts

### Weekly
- Review resource usage
- Check certificate expiry
- Security updates (if needed)

### Monthly
- System updates (rolling, during maintenance window)
- Capacity planning review
- Disaster recovery test (staging)

### Quarterly
- Full DR drill (production)
- Security audit
- Performance review

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | October 2025 | Initial multi-environment setup |

---

## License and Ownership

**Organization**: [Your Organization]
**Infrastructure Team**: [Team Contact]
**Support**: [Support Email/Channel]

---

**Last Updated**: October 2025
**Status**: Production Ready
