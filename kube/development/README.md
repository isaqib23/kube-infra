# Development Kubernetes Cluster Deployment

## Overview
Single-node Kubernetes development cluster on Dell PowerEdge R740 server.

**Server:** k8s-dev1 (10.255.252.10)

## Quick Start

Run the all-in-one deployment script:

```bash
sudo ./deploy-dev-cluster.sh
```

This single script will automatically deploy everything in order:
1. Server preparation (packages, containerd, kubernetes)
2. Cluster initialization (kubeadm init + CNI)
3. Storage setup (storage classes + PVs)
4. Ingress controller (NGINX + cert-manager)
5. Monitoring stack (Prometheus + Grafana + Loki)
6. Basic validation

**Estimated time:** 30-45 minutes

## Manual Step-by-Step (Optional)

If you prefer to run scripts individually:

```bash
# 1. Prepare server
sudo ./01-server-preparation.sh

# 2. Initialize cluster
sudo ./03-ha-cluster-init.sh

# 3. Configure storage
sudo ./05-ha-storage-setup.sh

# 4. Setup ingress
sudo ./06-ha-ingress-setup.sh

# 5. Deploy monitoring
sudo ./07-ha-monitoring-setup.sh
```

## Prerequisites

- Fresh Ubuntu 24.04 LTS installation
- Minimum: 8GB RAM, 4 CPU cores, 100GB disk
- Internet connectivity
- Run as root or with sudo

## Configuration

Edit `env-config.sh` to customize:
- Server name and IP
- Cluster domain
- Network settings

Current defaults:
- Server: k8s-dev1
- IP: 10.255.252.10
- Domain: k8s.local

## Access After Deployment

### Kubernetes API
```bash
kubectl cluster-info
```

### Monitoring Dashboards

Add to `/etc/hosts`:
```
10.255.252.10 grafana.k8s.local prometheus.k8s.local alertmanager.k8s.local
```

Then access:
- Grafana: https://grafana.k8s.local
- Prometheus: https://prometheus.k8s.local
- AlertManager: https://alertmanager.k8s.local

**Credentials:** admin / admin123

### Port Forwarding (Alternative)
```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

## Verification

Check cluster status:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get pv,pvc
kubectl get ingress --all-namespaces
```

## Logs

- Main deployment: `/var/log/dev-cluster-deploy.log`
- Individual scripts: `/var/log/*.log`

## Architecture

**Single-Node Configuration:**
- Control plane + worker on same node
- No HAProxy/Keepalived (not needed for single-node)
- No VIP (direct IP access)
- Taint removed from control plane to allow workload pods

**Components:**
- Container Runtime: containerd
- CNI: Calico
- Ingress: NGINX
- Storage: Local path provisioner + hostPath PVs
- Monitoring: Prometheus Operator stack
- Certificates: cert-manager

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Network issues
```bash
kubectl get pods -n kube-system | grep calico
journalctl -u kubelet
```

### Storage issues
```bash
kubectl get storageclass
kubectl get pv
```

## Scripts Reference

- `deploy-dev-cluster.sh` - All-in-one deployment orchestrator
- `01-server-preparation.sh` - Install system packages and Kubernetes
- `03-ha-cluster-init.sh` - Initialize cluster with kubeadm
- `05-ha-storage-setup.sh` - Configure storage classes and PVs  
- `06-ha-ingress-setup.sh` - Deploy NGINX ingress + cert-manager
- `07-ha-monitoring-setup.sh` - Deploy monitoring stack
- `env-config.sh` - Environment configuration variables

## Next Steps After Deployment

1. Verify all pods are running
2. Configure external DNS or /etc/hosts
3. Access Grafana to view cluster metrics
4. Deploy your applications
5. Set up external backups
6. Configure monitoring alerts

## Support

Check logs at:
- `/var/log/dev-cluster-deploy.log`
- `/var/log/ha-*.log`
- `journalctl -u kubelet`
- `kubectl logs` for pod-specific issues
