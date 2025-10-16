# Development Environment Setup Guide
## Single-Node Kubernetes Cluster Deployment

---

## Overview

This guide covers the deployment of a **single-node Development Kubernetes cluster** on a Dell PowerEdge R740 server. This environment is designed for development and testing purposes with no high availability requirements.

### Environment Specifications

| Component | Specification |
|-----------|--------------|
| **Servers** | 1x Dell PowerEdge R740 |
| **Network** | 10.255.252.0/24 |
| **Node** | k8s-dev1 |
| **IP** | 10.255.252.10 |
| **Architecture** | Single-node (control-plane + worker) |
| **HA** | None (single point of failure) |

### Key Characteristics

✅ **Pros**:
- Simple to deploy and manage
- All resources available for workloads
- Fast iteration for development
- Lower complexity

⚠️ **Limitations**:
- No high availability
- No load balancing
- Single point of failure
- Not suitable for production workloads

---

## Prerequisites

### Hardware Requirements

- 1x Dell PowerEdge R740 server with:
  - 32 CPU cores minimum
  - 128GB RAM minimum
  - 500GB storage minimum
  - Redundant power supplies

### Software Requirements

- Fresh Ubuntu 24.04 LTS
- Root/sudo access
- Static IP address: 10.255.252.10
- Internet connectivity

---

## Deployment Steps

### Phase 1: Server Preparation

```bash
cd /path/to/development/
sudo ./01-server-preparation.sh
```

This script will:
- Configure hostname to k8s-dev1
- Set static IP 10.255.252.10
- Install Kubernetes components (v1.34)
- Install containerd
- Configure firewall rules
- Disable swap
- Set up kernel parameters

**Expected time**: 15-20 minutes

**Verification**:
```bash
# Check hostname
hostname
# Output: k8s-dev1

# Check IP
ip addr show | grep 10.255.252.10

# Check Kubernetes installation
kubeadm version
kubectl version --client
```

### Phase 2: Cluster Initialization

**Note**: For single-node, we skip the load balancer setup (02-ha-loadbalancer-setup.sh) as there's no HA requirement.

```bash
# Initialize single-node cluster
sudo ./03-ha-cluster-init.sh
```

This script will:
- Initialize Kubernetes cluster (single control-plane)
- Install Calico CNI for networking
- Install metrics server
- Install Helm package manager
- Remove control-plane taints (allow workloads on control-plane)
- Create storage directories

**Expected time**: 15-20 minutes

**Verification**:
```bash
# Check cluster status
kubectl get nodes
# Output should show k8s-dev1 in Ready state

# Check all system pods
kubectl get pods --all-namespaces

# Verify kubectl is configured
kubectl cluster-info
```

### Phase 3: Storage Setup

```bash
sudo ./05-ha-storage-setup.sh
```

Creates local storage classes:
- `fast-ssd-storage` - High-performance storage
- `standard-storage` - General purpose
- `logs-storage` - For log aggregation

**No backup storage class** (backups disabled for dev environment)

### Phase 4: Ingress Controller

```bash
sudo ./06-ha-ingress-setup.sh
```

Deploys NGINX Ingress Controller with:
- Single replica (sufficient for dev)
- NodePort 30080 (HTTP) and 30443 (HTTPS)
- Cert-manager for TLS certificates

**Test ingress**:
```bash
# Check ingress pods
kubectl get pods -n ingress-nginx

# Test HTTP access
curl http://10.255.252.10:30080
```

### Phase 5: Monitoring Stack

```bash
sudo ./07-ha-monitoring-setup.sh
```

Deploys lightweight monitoring:
- Prometheus (3-day retention)
- Grafana
- Loki + Promtail (minimal log retention)
- Node Exporter

**Access Grafana**:
```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser to http://localhost:3000
# Default credentials: admin / prom-operator
```

### Phase 6: Validation

```bash
sudo ./08-cluster-validation.sh
```

Validates:
- Node health
- Pod status across all namespaces
- DNS resolution
- Network connectivity
- Storage classes
- Ingress controller

---

## Post-Deployment Configuration

### Accessing the Cluster

**Locally on the server**:
```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

**From remote workstation**:
```bash
# Copy kubeconfig
scp root@10.255.252.10:/root/.kube/config ~/.kube/dev-config

# Use the config
export KUBECONFIG=~/.kube/dev-config
kubectl get nodes
```

### Deploying Applications

**Example: Deploy a test application**

```bash
# Create a deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Expose as service
kubectl expose deployment nginx --port=80 --target-port=80

# Create ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.dev.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF

# Test (add nginx.dev.local to /etc/hosts pointing to 10.255.252.10)
curl http://nginx.dev.local:30080
```

---

## Development Workflow

### Typical Development Cycle

1. **Deploy application**:
   ```bash
   kubectl apply -f my-app.yaml
   ```

2. **Monitor logs**:
   ```bash
   kubectl logs -f deployment/my-app
   ```

3. **Update deployment**:
   ```bash
   kubectl set image deployment/my-app my-app=my-app:v2
   ```

4. **Debug issues**:
   ```bash
   kubectl describe pod my-app-xxxx
   kubectl exec -it my-app-xxxx -- /bin/bash
   ```

5. **Clean up**:
   ```bash
   kubectl delete deployment my-app
   ```

### Using Helm for Deployments

```bash
# Add repository
helm repo add bitnami https://charts.bitnami.com/bitnami

# Install application
helm install my-redis bitnami/redis

# List releases
helm list

# Upgrade
helm upgrade my-redis bitnami/redis --set auth.password=newpassword

# Uninstall
helm uninstall my-redis
```

---

## Daily Operations

### Health Checks

```bash
# Check node status
kubectl get nodes

# Check pod health
kubectl get pods -A

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Check disk space
df -h /var/lib/containerd
df -h /mnt/k8s-storage
```

### Managing Resources

**View resource consumption**:
```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu
```

**Clean up completed pods**:
```bash
kubectl delete pods --field-selector status.phase=Succeeded -A
kubectl delete pods --field-selector status.phase=Failed -A
```

**Prune unused images**:
```bash
sudo crictl rmi --prune
```

---

## Troubleshooting

### Common Issues

**Issue**: Pods stuck in Pending
```bash
# Check node resources
kubectl describe node k8s-dev1
kubectl top node k8s-dev1

# Check pod events
kubectl describe pod <pod-name>

# Check for taints (should be none for dev)
kubectl describe node k8s-dev1 | grep Taint
```

**Issue**: Cannot pull images
```bash
# Check containerd
sudo systemctl status containerd

# Check network connectivity
ping 8.8.8.8
curl -I https://registry.k8s.io

# Manual image pull test
sudo crictl pull nginx:latest
```

**Issue**: DNS not working
```bash
# Test DNS from a pod
kubectl run test-dns --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Issue**: Disk space low
```bash
# Check space
df -h

# Clean up old images
sudo crictl rmi --prune

# Clean up old logs
sudo journalctl --vacuum-time=7d

# Clean up pod logs
sudo find /var/log/pods -name "*.log" -mtime +7 -delete
```

---

## Upgrading Kubernetes

### Pre-Upgrade Checklist

- [ ] Backup etcd: `sudo /opt/kubernetes/etcd-backup.sh`
- [ ] Note current version: `kubectl version`
- [ ] Review release notes for target version
- [ ] Schedule maintenance window

### Upgrade Procedure

```bash
# 1. Upgrade kubeadm
sudo apt-mark unhold kubeadm
sudo apt update
sudo apt install kubeadm=1.XX.X-00
sudo apt-mark hold kubeadm

# 2. Verify upgrade plan
sudo kubeadm upgrade plan

# 3. Apply upgrade
sudo kubeadm upgrade apply v1.XX.X

# 4. Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt install kubelet=1.XX.X-00 kubectl=1.XX.X-00
sudo apt-mark hold kubelet kubectl

# 5. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 6. Verify
kubectl get nodes
kubectl version
```

---

## Resetting the Cluster

If you need to start fresh:

```bash
# 1. Drain the node (if cluster is running)
kubectl drain k8s-dev1 --delete-emptydir-data --force --ignore-daemonsets

# 2. Reset Kubernetes
sudo kubeadm reset -f

# 3. Clean up
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/etcd
sudo rm -rf /root/.kube

# 4. Restart containerd
sudo systemctl restart containerd

# 5. Re-initialize
sudo ./03-ha-cluster-init.sh
```

---

## Best Practices for Development

### Resource Management

1. **Set resource requests and limits**:
   ```yaml
   resources:
     requests:
       memory: "128Mi"
       cpu: "100m"
     limits:
       memory: "256Mi"
       cpu: "200m"
   ```

2. **Use namespaces for isolation**:
   ```bash
   kubectl create namespace my-project
   kubectl config set-context --current --namespace=my-project
   ```

3. **Clean up regularly**:
   ```bash
   # Delete unused resources
   kubectl delete pods --field-selector status.phase=Succeeded -A
   kubectl delete pods --field-selector status.phase=Failed -A
   ```

### Development Tips

1. **Use kubectl aliases**:
   ```bash
   alias k=kubectl
   alias kgp='kubectl get pods'
   alias kgs='kubectl get services'
   alias kdp='kubectl describe pod'
   ```

2. **Enable kubectl autocompletion**:
   ```bash
   echo 'source <(kubectl completion bash)' >>~/.bashrc
   source ~/.bashrc
   ```

3. **Use kubectx and kubens** for easier context switching

4. **Install k9s** for a better terminal UI:
   ```bash
   wget https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
   tar -xzf k9s_Linux_amd64.tar.gz
   sudo mv k9s /usr/local/bin/
   ```

---

## Monitoring and Debugging

### View Logs

```bash
# Pod logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow logs
kubectl logs <pod-name> --previous  # Previous container

# Multiple containers
kubectl logs <pod-name> -c <container-name>

# All pods in deployment
kubectl logs -l app=my-app --all-containers=true
```

### Execute Commands in Pods

```bash
# Interactive shell
kubectl exec -it <pod-name> -- /bin/bash

# Run command
kubectl exec <pod-name> -- ls -la /app

# For multi-container pods
kubectl exec -it <pod-name> -c <container-name> -- /bin/bash
```

### Port Forwarding

```bash
# Forward local port to pod
kubectl port-forward pod/<pod-name> 8080:80

# Forward to service
kubectl port-forward service/<service-name> 8080:80

# Forward to deployment
kubectl port-forward deployment/<deployment-name> 8080:80
```

---

## Security Considerations

### For Development Environment

While this is a development environment, still follow basic security:

1. **Don't expose the cluster to public internet**
2. **Use RBAC** even in dev
3. **Don't commit secrets** to git
4. **Use ConfigMaps and Secrets** properly
5. **Keep the cluster updated**

### Creating Service Accounts

```bash
# Create service account
kubectl create serviceaccount my-app-sa

# Create role
kubectl create role my-app-role --verb=get,list --resource=pods

# Create role binding
kubectl create rolebinding my-app-binding \
  --role=my-app-role \
  --serviceaccount=default:my-app-sa
```

---

## Appendix: Quick Reference

### Development Server Info
```
Hostname:     k8s-dev1
IP Address:   10.255.252.10
Gateway:      10.255.252.1
Network:      10.255.252.0/24
```

### Key Endpoints
```
Kubernetes API:    https://10.255.252.10:6443
Ingress HTTP:      http://10.255.252.10:30080
Ingress HTTPS:     https://10.255.252.10:30443
```

### Useful Commands
```bash
# Cluster info
kubectl cluster-info

# Node info
kubectl describe node k8s-dev1

# All resources
kubectl get all -A

# Resource usage
kubectl top nodes
kubectl top pods -A

# Events
kubectl get events -A --sort-by='.lastTimestamp'

# Logs
journalctl -u kubelet -f
journalctl -u containerd -f
```

### Storage Paths
```
Containerd:       /var/lib/containerd
Kubernetes:       /etc/kubernetes
etcd:             /var/lib/etcd
Logs:             /var/log/kubernetes
Backups:          /opt/kubernetes/backups
Storage:          /mnt/k8s-storage
```

---

## Transitioning to Staging/Production

When your application is ready for staging:

1. **Export manifests**:
   ```bash
   kubectl get all -o yaml > my-app-manifests.yaml
   ```

2. **Test in staging environment** first

3. **Update configurations** for staging/production:
   - Adjust resource requests/limits
   - Add proper resource quotas
   - Configure proper monitoring
   - Set up proper backup strategy

4. **Never deploy directly from dev to production**

---

**Document Version**: 1.0
**Environment**: Development (Single-node)
**Last Updated**: October 2025
**Status**: Ready for Deployment
