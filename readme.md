### High Availability Kubernetes Cluster Configuration Artifact: All-in-One Stacked Setup on 4 Bare Metal Servers with 2 Redundant Switches

This artifact provides a comprehensive, step-by-step configuration guide to deploy a highly available (HA) Kubernetes cluster on 4 bare metal servers, where **all servers act as both control-plane and worker nodes** (stacked topology). This maximizes resource utilization by allowing workloads to run on control-plane nodes after removing taints. For HA, we'll use a stacked etcd setup across all 4 nodes (etcd runs on the control-planes), a virtual IP (VIP) for the control-plane endpoint managed by Keepalived, and HAProxy for load balancing. Note: Etcd with 4 nodes (even number) can tolerate 1 failure (quorum=3), but an odd number (e.g., 3) is preferred to avoid tie risks in larger failures—consider this for production.

**Assumptions and Prerequisites**:
- Servers: 4 identical bare metal machines (e.g., Server1-4), each with ≥4 CPUs, ≥16GB RAM, ≥2 NICs (ideally 4 for separation), and a compatible Linux OS (Ubuntu 24.04 LTS or CentOS Stream 9 recommended).
- Switches: 2 redundant switches (e.g., Switch A and B) supporting LACP bonding, VLANs, and STP/MLAG for inter-switch failover.
- Networking: Private subnet (e.g., 192.168.1.0/24). VIP: 192.168.1.100. Pod CIDR: 10.244.0.0/16 (adjust as needed).
- Kubernetes Version: Target v1.31 (latest stable as of October 2025; check for updates).
- Tools: kubeadm for bootstrapping, containerd as CRI, Calico as CNI (for BGP-based HA networking).
- Security: Run as root/sudo. Disable swap on all servers: `sudo swapoff -a` and comment out in `/etc/fstab`.
- Hostnames: Set unique hostnames (e.g., k8s-cp1 to k8s-cp4) via `/etc/hostname` and `/etc/hosts`.
- Firewall: Allow necessary ports (e.g., ufw allow 6443,2379-2380,10250 on Ubuntu).
- Backups: Plan for regular etcd snapshots.

**Hardware Wiring Diagram** (Textual Representation):
```
Switch A <---- LACP Bond ----> NIC1 on each Server1-4
Switch B <---- LACP Bond ----> NIC2 on each Server1-4
Inter-Switch Link (ISL) with STP/MLAG between Switch A and B for redundancy.
Optional: Separate bonds for management (VLAN10), Pod traffic (VLAN20).
```
Configure NIC bonding on each server (e.g., via netplan on Ubuntu or nmcli on CentOS) for active-backup or LACP mode.

#### Step 1: Install Dependencies on All 4 Servers
Run on each server to install Kubernetes components, container runtime, and HA tools.

For Ubuntu:
```
sudo apt update && sudo apt install -y apt-transport-https ca-certificates curl gnupg keepalived haproxy
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubelet=1.31.1 kubeadm=1.31.1 kubectl=1.31.1 containerd
sudo apt-mark hold kubelet kubeadm kubectl
```

For CentOS:
```
sudo yum install -y yum-utils keepalived haproxy
sudo yum-config-manager --add-repo https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
sudo yum install -y kubelet-1.31.1 kubeadm-1.31.1 kubectl-1.31.1 containerd --disableexcludes=kubernetes
sudo yum versionlock add kubelet kubeadm kubectl
```

Configure containerd on all:
```
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml  # For cgroup v2
sudo systemctl restart containerd && sudo systemctl enable containerd kubelet
```

#### Step 2: Configure Load Balancing and VIP on All Control-Plane Servers (All 4)
All servers are control-planes in this stacked setup. Use Keepalived for VRRP-based VIP failover and HAProxy to balance API traffic.

- **Keepalived Config** (`/etc/keepalived/keepalived.conf` on each server; adjust priorities: Server1=150, Server2=140, Server3=130, Server4=120):
  ```
  vrrp_instance VI_1 {
      state MASTER  # Set to BACKUP on Server2-4
      interface bond0  # Your bonded management interface
      virtual_router_id 51
      priority 150  # Decrease for backups
      advert_int 1
      authentication {
          auth_type PASS
          auth_pass mysecretpass
      }
      virtual_ipaddress {
          192.168.1.100/24  # VIP
      }
  }
  ```
  Start: `sudo systemctl enable --now keepalived`

- **HAProxy Config** (`/etc/haproxy/haproxy.cfg` on each; list all control-plane IPs):
  ```
  global
      log /dev/log local0
      log /dev/log local1 notice
      chroot /var/lib/haproxy
      stats socket /run/haproxy/admin.sock mode 660 level admin
      stats timeout 30s
      user haproxy
      group haproxy
      daemon

  defaults
      log global
      mode http
      option httplog
      option dontlognull
      timeout connect 5000
      timeout client  50000
      timeout server  50000

  frontend kubernetes-api
      bind 192.168.1.100:6443  # VIP:6443
      mode tcp
      option tcplog
      default_backend kubernetes-api-backend

  backend kubernetes-api-backend
      mode tcp
      option tcp-check
      balance roundrobin
      server cp1 192.168.1.1:6443 check  # Server1 IP
      server cp2 192.168.1.2:6443 check  # Server2 IP
      server cp3 192.168.1.3:6443 check  # Server3 IP
      server cp4 192.168.1.4:6443 check  # Server4 IP
  ```
  Start: `sudo systemctl enable --now haproxy`

#### Step 3: Initialize the First Control-Plane Node (Server1)
```
sudo kubeadm init --control-plane-endpoint "192.168.1.100:6443" --pod-network-cidr=10.244.0.0/16 --upload-certs --kubernetes-version=1.31.1
```
- Copy kubeconfig:
  ```
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  ```
- Note the join commands (one for control-planes with `--control-plane --certificate-key <key>`, one for workers).

#### Step 4: Join Remaining Control-Plane Nodes (Servers 2-4)
On each:
```
sudo kubeadm join 192.168.1.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <cert-key>
```
- Copy kubeconfig to each as in Step 3.

#### Step 5: Install CNI for Pod Networking (on Server1)
Use Calico for HA-friendly networking:
```
curl https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml -O
kubectl apply -f calico.yaml
```
Verify: `kubectl get nodes` (all 4 should show as Ready after a few minutes).

#### Step 6: Enable Workloads on All Nodes (Remove Taints)
On Server1 (propagates via kubectl):
```
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl taint nodes $node node-role.kubernetes.io/control-plane:NoSchedule- || true
done
```
This makes all 4 nodes schedulable for Pods, turning them into worker-capable control-planes.

#### Step 7: Verify and Test HA
- Check cluster: `kubectl get nodes -o wide` (all Ready).
- Etcd health: `kubectl get pods -n kube-system | grep etcd` (4 etcd Pods).
- Failover test: Stop kubelet on one node (`sudo systemctl stop kubelet`), verify API access via VIP and Pod rescheduling.
- Network test: Disconnect one switch, ensure bonding fails over (check with `ip link` and ping).
- Deploy a test Deployment with replicas=4 and anti-affinity to spread across nodes.

#### Step 8: Additional HA Configurations
- **Etcd Backups**: Script on Server1 (cron job):
  ```
  #!/bin/bash
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db
  ```
- **Monitoring**: Deploy Prometheus:
  ```
  kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/raw/main/bundle.yaml
  ```
- **Storage HA**: For persistent volumes, install Rook:
  ```
  git clone --single-branch --branch v1.15.1 https://github.com/rook/rook.git
  cd rook/deploy/examples
  kubectl apply -f crds.yaml -f common.yaml -f operator.yaml -f cluster.yaml
  ```
- **Upgrades**: Use `kubeadm upgrade plan` and apply sequentially.

This setup provides HA for control-plane (via VIP and etcd quorum) and network (via switches/bonding), with all nodes running workloads. Scale by adding more nodes. For troubleshooting, check `journalctl -u kubelet` or Kubernetes docs. If your hardware/OS differs, adjust accordingly.