# Quick Start Guide - Multi-Environment Kubernetes

This is a condensed guide to get you started quickly with any environment.

---

## Choose Your Environment

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                   │
│  PRODUCTION     ────►  4 servers  ────►  Full HA                │
│  (10.255.254.x)        k8s-cp1-4          3/4 quorum             │
│                                                                   │
│  STAGING        ────►  2 servers  ────►  Limited HA             │
│  (10.255.253.x)        k8s-stg1-2         2/2 quorum             │
│                                                                   │
│  DEVELOPMENT    ────►  1 server   ────►  No HA                  │
│  (10.255.252.x)        k8s-dev1           Single node            │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Production (4 Servers)

### Network Setup
```
Server IPs:     10.255.254.10-13
VIP:            10.255.254.100
Gateway:        10.255.254.1
```

### Deployment Sequence
```bash
# On ALL 4 servers (k8s-cp1, k8s-cp2, k8s-cp3, k8s-cp4)
cd production/
sudo ./01-server-preparation.sh      # 15 min per server
sudo ./02-ha-loadbalancer-setup.sh   # 5 min per server

# On k8s-cp1 ONLY
sudo ./03-ha-cluster-init.sh         # 20 min

# On k8s-cp2, k8s-cp3, k8s-cp4 (one at a time)
sudo ./04-ha-cluster-join.sh         # 10 min each

# On k8s-cp1 (or any node)
sudo ./05-ha-storage-setup.sh        # 5 min
sudo ./06-ha-ingress-setup.sh        # 5 min
sudo ./07-ha-monitoring-setup.sh     # 10 min
sudo ./08-cluster-validation.sh      # 5 min
```

**Total time: ~2-3 hours**

### Verify
```bash
kubectl get nodes
# Should show 4 nodes in Ready state

kubectl get pods -A
# All pods should be Running

kubectl --server=https://10.255.254.100:6443 get nodes
# Should work via VIP
```

---

## Staging (2 Servers)

### Network Setup
```
Server IPs:     10.255.253.10-11
VIP:            10.255.253.100
Gateway:        10.255.253.1
```

### Deployment Sequence
```bash
# On BOTH servers (k8s-stg1, k8s-stg2)
cd staging/
sudo ./01-server-preparation.sh      # 15 min per server
sudo ./02-ha-loadbalancer-setup.sh   # 5 min per server

# On k8s-stg1 ONLY
sudo ./03-ha-cluster-init.sh         # 20 min

# On k8s-stg2 ONLY
sudo ./04-ha-cluster-join.sh         # 10 min

# On k8s-stg1 (or either node)
sudo ./05-ha-storage-setup.sh        # 5 min
sudo ./06-ha-ingress-setup.sh        # 5 min
sudo ./07-ha-monitoring-setup.sh     # 10 min
sudo ./08-cluster-validation.sh      # 5 min
```

**Total time: ~1.5-2 hours**

### Verify
```bash
kubectl get nodes
# Should show 2 nodes in Ready state

kubectl --server=https://10.255.253.100:6443 get nodes
```

⚠️ **Warning**: Both nodes must be operational. Zero fault tolerance!

---

## Development (1 Server)

### Network Setup
```
Server IP:      10.255.252.10
No VIP:         (single node)
Gateway:        10.255.252.1
```

### Deployment Sequence
```bash
# On k8s-dev1 ONLY
cd development/
sudo ./01-server-preparation.sh      # 15 min
sudo ./03-ha-cluster-init.sh         # 20 min (skip 02!)
sudo ./05-ha-storage-setup.sh        # 5 min
sudo ./06-ha-ingress-setup.sh        # 5 min
sudo ./07-ha-monitoring-setup.sh     # 10 min
sudo ./08-cluster-validation.sh      # 5 min
```

**Total time: ~1 hour**

### Verify
```bash
kubectl get nodes
# Should show 1 node in Ready state

kubectl get pods -A
# All pods should be Running
```

---

## Common Post-Deployment Tasks

### Access Cluster from Remote Machine

```bash
# Copy kubeconfig
scp root@<first-node-ip>:/root/.kube/config ~/.kube/<env>-config

# For production
scp root@10.255.254.10:/root/.kube/config ~/.kube/prod-config
export KUBECONFIG=~/.kube/prod-config

# For staging
scp root@10.255.253.10:/root/.kube/config ~/.kube/staging-config
export KUBECONFIG=~/.kube/staging-config

# For development
scp root@10.255.252.10:/root/.kube/config ~/.kube/dev-config
export KUBECONFIG=~/.kube/dev-config
```

### Access Monitoring (Grafana)

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Default credentials: admin / prom-operator
```

### Deploy Test Application

```bash
# Create deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# Get NodePort
kubectl get svc nginx
# Access via http://<any-node-ip>:<nodeport>
```

---

## Troubleshooting Quick Reference

### Check Cluster Health
```bash
kubectl get nodes                    # Node status
kubectl get pods -A                  # All pods
kubectl get componentstatuses        # Component health
kubectl top nodes                    # Resource usage
```

### Check etcd (Production/Staging)
```bash
kubectl get pods -n kube-system | grep etcd
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

### Check VIP (Production/Staging)
```bash
# Check which node has VIP
ip addr show | grep <VIP>

# Check Keepalived status
systemctl status keepalived
journalctl -u keepalived -f
```

### View Logs
```bash
# Kubelet logs
journalctl -u kubelet -f

# Containerd logs
journalctl -u containerd -f

# Pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs -f <pod-name> -n <namespace>  # Follow
```

### Common Fixes

**Pods stuck in Pending**:
```bash
kubectl describe pod <pod-name>
kubectl top nodes  # Check resources
```

**DNS not working**:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Node NotReady**:
```bash
kubectl describe node <node-name>
systemctl status kubelet
systemctl restart kubelet
```

---

## Critical Warnings

### Production
- ✅ Can survive 1 node failure
- ⚠️ Do NOT reboot more than 1 node at a time
- ⚠️ Always test in staging first

### Staging
- ⚠️ Requires BOTH nodes operational
- ⚠️ Zero fault tolerance
- ⚠️ Cluster stops if any node fails

### Development
- ⚠️ Single point of failure
- ⚠️ No backups by default
- ⚠️ Not for production workloads

---

## Next Steps

After deployment:

1. **Test cluster access** from remote machine
2. **Access Grafana** and explore dashboards
3. **Deploy a test application**
4. **Set up RBAC** for team members
5. **Configure backups** (if not already done)
6. **Set up ingress** for your applications
7. **Configure monitoring alerts**

---

## Getting Help

1. **Check documentation**:
   - Production: `production/INFRASTRUCTURE_HANDOVER_DOCUMENTATION.md`
   - Staging: `staging/STAGING_SETUP_GUIDE.md`
   - Development: `development/DEVELOPMENT_SETUP_GUIDE.md`

2. **Check logs**:
   - `/var/log/<env>-k8s-setup.log`
   - `journalctl -u kubelet`
   - `kubectl get events -A`

3. **Validate configuration**:
   - `./08-cluster-validation.sh`

---

## Quick Command Reference

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Resource usage
kubectl top nodes
kubectl top pods -A

# Describe resources
kubectl describe node <node-name>
kubectl describe pod <pod-name>

# Logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow

# Execute in pod
kubectl exec -it <pod-name> -- /bin/bash

# Port forward
kubectl port-forward pod/<pod-name> 8080:80

# Apply manifests
kubectl apply -f manifest.yaml

# Delete resources
kubectl delete pod <pod-name>
kubectl delete deployment <deployment-name>
```

---

**For detailed information, see the environment-specific guides!**
