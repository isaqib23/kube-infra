# Kubernetes on Dell PowerEdge R740 - Production Setup

This repository contains a complete Kubernetes deployment solution for Dell PowerEdge R740 servers running Ubuntu 24.04 LTS. The setup includes a production-ready cluster with monitoring, databases, and management tools.

## 🚀 Quick Start

### Prerequisites
- Dell PowerEdge R740 server with Ubuntu 24.04 LTS
- Minimum 8GB RAM and 4 CPU cores
- Root or sudo access
- Internet connectivity for package downloads

### One-Command Deployment
```bash
sudo ./deploy.sh
```

This will run an interactive setup that installs everything you need.

## 📋 What Gets Installed

### Core Kubernetes Components
- **Kubernetes 1.34** - Latest stable version
- **containerd 1.7.23** - Latest container runtime
- **Calico CNI v3.29.0** - Latest network plugin for pod communication
- **kubeadm, kubelet, kubectl** - Kubernetes management tools

### Management & Monitoring
- **Kubernetes Dashboard v7.13.0** - Latest web UI for cluster management
- **Helm** - Package manager for Kubernetes
- **Prometheus v2.55.1** - Latest metrics collection and alerting
- **Grafana v11.3.0** - Latest visualization and dashboards
- **AlertManager v0.28.1** - Latest alert routing and notifications
- **Loki v3.3.1 & Promtail v3.3.1** - Latest log aggregation and collection
- **Tempo v2.7.1** - Latest distributed tracing

### Database Services
- **PostgreSQL 17.0** - Latest production-ready SQL database
- **Redis 7.4.1** - Latest in-memory data store and cache

### Networking
- **NGINX Ingress Controller** - HTTP(S) load balancer and ingress

## 📁 Repository Structure

```
kube-infra/
├── deploy.sh              # Master deployment script
├── k8s-setup.sh           # Core Kubernetes installation
├── k8s-dashboard.sh       # Dashboard installation
├── prepare-databases.sh   # Database setup (PostgreSQL, Redis)
├── monitoring-setup.sh    # Monitoring stack (Prometheus, Grafana)
├── r740_server.md         # Dell R740 server documentation
└── README.md             # This file
```

## 🛠 Individual Component Installation

### 1. Core Kubernetes Setup
```bash
sudo ./k8s-setup.sh [hostname] [username]
```
- Installs Kubernetes with Calico CNI
- Configures single-node cluster
- Sets up kubectl access

### 2. Kubernetes Dashboard
```bash
sudo ./k8s-dashboard.sh
```
- Installs web-based dashboard
- Creates admin and readonly users
- Provides access tokens

### 3. Database Services
```bash
sudo ./prepare-databases.sh
```
- Deploys PostgreSQL with persistence
- Deploys Redis in master-replica configuration
- Creates connection secrets

### 4. Monitoring Stack
```bash
sudo ./monitoring-setup.sh
```
- Installs Prometheus for metrics
- Deploys Grafana with pre-built dashboards
- Sets up AlertManager for notifications
- Includes Loki for log aggregation

## 🔐 Access Information

### Kubernetes Dashboard
```bash
# Port forward to access dashboard
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443

# Get admin token
kubectl -n kubernetes-dashboard create token admin-user
```
Access: https://localhost:8443

### Grafana Monitoring
```bash
# Port forward to access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```
- URL: http://localhost:3000
- Username: `admin`
- Password: `GrafanaAdmin123!`

### Database Connections

#### PostgreSQL
```bash
# Connection details
Host: postgresql.postgresql.svc.cluster.local
Port: 5432
Database: appdb
Username: appuser
Password: AppUserPassword123!

# Admin access
Username: postgres
Password: PostgresAdminPassword123!
```

#### Redis
```bash
# Connection details
Host: redis-master.redis.svc.cluster.local
Port: 6379
Password: RedisPassword123!
```

## 🔧 Configuration Options

### Custom Deployment
```bash
# Interactive setup with custom options
sudo ./deploy.sh

# Non-interactive with defaults
sudo ./deploy.sh --skip-input

# Help
sudo ./deploy.sh --help
```

### Environment Variables
You can customize the deployment by editing the scripts or setting these variables:

```bash
export KUBE_VERSION="1.28"
export CONTAINERD_VERSION="1.7.8"
export CALICO_VERSION="v3.26.4"
```

## 📊 Monitoring & Alerting

### Pre-configured Dashboards
- Kubernetes cluster overview
- Node metrics and health
- Pod resource usage
- Database performance (PostgreSQL, Redis)
- Storage and networking metrics

### Default Alerts
- Pod crash looping
- Node not ready
- High CPU/memory usage
- Database connection issues
- Storage space warnings

## 🗄 Storage Configuration

### Persistent Volumes
The setup creates local storage classes for:
- Database data persistence
- Monitoring data retention
- Log storage

Storage paths on host:
```
/mnt/data/postgresql/  # PostgreSQL data
/mnt/data/redis/       # Redis data
/mnt/data/prometheus/  # Metrics data
/mnt/data/grafana/     # Dashboard configs
```

## 🌐 Network Configuration

### Service Mesh
- Calico CNI provides pod-to-pod networking
- NGINX Ingress handles external traffic
- Network policies can be applied for security

### Port Mappings
| Service | Internal Port | NodePort | Ingress |
|---------|--------------|----------|---------|
| Dashboard | 443 | - | k8s-dashboard.local |
| Grafana | 80 | - | grafana.local |
| Prometheus | 9090 | - | prometheus.local |
| PostgreSQL | 5432 | - | Internal only |
| Redis | 6379 | - | Internal only |

## 🔒 Security Best Practices

### Implemented Security Features
- RBAC (Role-Based Access Control) enabled
- Service accounts with minimal permissions
- Network policies for pod isolation
- Secrets management for database credentials
- Container security contexts

### Additional Security Recommendations
1. **Change default passwords** before production use
2. **Enable audit logging** for compliance
3. **Set up TLS certificates** for external access
4. **Implement network policies** to restrict pod communication
5. **Regular security updates** and vulnerability scanning

## 🚀 Scaling the Cluster

### Adding Worker Nodes
1. Run the master deployment on additional servers
2. Use the join command from the initial setup:
```bash
# Get join command
kubeadm token create --print-join-command

# Run on worker nodes
sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

### Resource Scaling
- **Horizontal Pod Autoscaler** - Automatically scale pods based on CPU/memory
- **Vertical Pod Autoscaler** - Adjust resource requests/limits
- **Cluster Autoscaler** - Add/remove nodes based on demand

## 🔍 Troubleshooting

### Common Issues

#### Pod stuck in Pending state
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check for resource constraints or node selector issues
```

#### Network connectivity issues
```bash
# Check CNI pods
kubectl get pods -n kube-system | grep calico

# Test pod-to-pod networking
kubectl run test --image=busybox --rm -it -- ping <pod-ip>
```

#### Database connection failures
```bash
# Check database pod logs
kubectl logs -f deployment/postgresql -n postgresql

# Test connectivity
kubectl run db-test --image=postgres:15 --rm -it -- psql -h postgresql.postgresql.svc.cluster.local -U appuser -d appdb
```

### Log Locations
- Kubernetes setup: `/var/log/k8s-setup.log`
- Dashboard setup: `/var/log/k8s-dashboard.log`
- Database setup: `/var/log/k8s-databases.log`
- Monitoring setup: `/var/log/k8s-monitoring.log`
- Master deployment: `/var/log/k8s-deployment.log`

## 🔧 Maintenance

### Regular Tasks
1. **Update Kubernetes components**:
   ```bash
   sudo apt update && sudo apt upgrade kubeadm kubelet kubectl
   ```

2. **Backup etcd**:
   ```bash
   kubectl create backup etcd-backup
   ```

3. **Monitor cluster health**:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   kubectl top nodes
   ```

4. **Update container images**:
   ```bash
   kubectl set image deployment/<deployment> <container>=<new-image>
   ```

### Backup Strategy
- **etcd backup**: Critical for cluster state
- **Persistent volume backup**: Database and application data
- **Configuration backup**: YAML manifests and secrets

## 📚 Additional Resources

### Documentation
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [Calico Documentation](https://docs.projectcalico.org/)
- [Helm Documentation](https://helm.sh/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)

### Dell R740 Specific
- See `r740_server.md` for detailed hardware configuration
- [Dell PowerEdge R740 Documentation](https://www.dell.com/support/manuals/en-us/poweredge-r740/)

## 🤝 Contributing

Feel free to submit issues and enhancement requests! When contributing:

1. Test changes on a development environment first
2. Update documentation for any configuration changes
3. Follow the existing script structure and logging format
4. Include error handling and validation

## 📄 License

This project is provided as-is for educational and production use. Please review and test thoroughly before deploying in critical environments.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review logs in `/var/log/k8s-*.log`
3. Consult the official Kubernetes documentation
4. Open an issue in this repository with detailed error information

---

**Built for Dell PowerEdge R740 • Ubuntu 24.04 LTS • Production Ready**