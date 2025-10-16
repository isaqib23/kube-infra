# Physical Infrastructure Handover Documentation
## High Availability Kubernetes Cluster on Dell PowerEdge R740 Servers

---

## Document Information

**Project:** HA Kubernetes Cluster Deployment
**Infrastructure Provider:** [Your Organization]
**Deployment Date:** October 2025
**Handover Date:** [Current Date]
**Document Version:** 1.0
**Status:** Production-Ready Cluster

---

## Executive Summary

This document provides comprehensive information about the physical infrastructure and deployed High Availability (HA) Kubernetes cluster for handover to the next development team. The infrastructure consists of **4 Dell PowerEdge R740 servers** connected via **2 network switches** in a redundant configuration, running a fully operational **4-node Kubernetes cluster** with stacked etcd topology.

**Current State:**
- ✅ All 4 servers operational and clustered
- ✅ Kubernetes HA cluster deployed and validated
- ✅ Network redundancy configured
- ✅ Monitoring and logging stack operational
- ✅ Storage classes configured
- ✅ Ingress controller deployed
- ✅ Automated backups configured

**Handover Scope:**
- Physical server hardware and specifications
- Network topology and switch configuration
- Kubernetes cluster architecture
- Access credentials and management interfaces
- Operational procedures
- Troubleshooting guides

---

## Table of Contents

1. [Physical Infrastructure Overview](#1-physical-infrastructure-overview)
2. [Network Architecture](#2-network-architecture)
3. [Server Hardware Specifications](#3-server-hardware-specifications)
4. [Kubernetes Cluster Architecture](#4-kubernetes-cluster-architecture)
5. [Access and Credentials](#5-access-and-credentials)
6. [Deployed Components](#6-deployed-components)
7. [Storage Configuration](#7-storage-configuration)
8. [Network Services](#8-network-services)
9. [Monitoring and Logging](#9-monitoring-and-logging)
10. [Backup and Disaster Recovery](#10-backup-and-disaster-recovery)
11. [Operational Procedures](#11-operational-procedures)
12. [Troubleshooting Guide](#12-troubleshooting-guide)
13. [Next Steps and Recommendations](#13-next-steps-and-recommendations)
14. [Support and Escalation](#14-support-and-escalation)

---

## 1. Physical Infrastructure Overview

### 1.1 Infrastructure Components

| Component | Quantity | Model/Specification | Location | Status |
|-----------|----------|---------------------|----------|--------|
| Dell PowerEdge R740 Servers | 4 | 2U Rack Server | Rack 1, U10-U17 | Operational |
| Network Switches | 2 | [Switch Model] | Rack 1, U8-U9 | Operational |
| Power Distribution Units (PDUs) | 2 | Redundant PDUs | Rack 1 | Operational |
| UPS System | 1 | [UPS Model] | Server Room | Operational |

### 1.2 Physical Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                        Rack 1 - Server Room                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  U17  ┌─────────────────────────────────────────────────┐       │
│       │  k8s-cp4 (10.255.254.13) - Dell R740          │       │
│  U16  └─────────────────────────────────────────────────┘       │
│                                                                   │
│  U15  ┌─────────────────────────────────────────────────┐       │
│       │  k8s-cp3 (10.255.254.12) - Dell R740          │       │
│  U14  └─────────────────────────────────────────────────┘       │
│                                                                   │
│  U13  ┌─────────────────────────────────────────────────┐       │
│       │  k8s-cp2 (10.255.254.11) - Dell R740          │       │
│  U12  └─────────────────────────────────────────────────┘       │
│                                                                   │
│  U11  ┌─────────────────────────────────────────────────┐       │
│       │  k8s-cp1 (10.255.254.10) - Dell R740 (Primary)│       │
│  U10  └─────────────────────────────────────────────────┘       │
│                                                                   │
│  U9   ┌─────────────────────────────────────────────────┐       │
│       │  Switch B (Secondary/Backup)                   │       │
│       └─────────────────────────────────────────────────┘       │
│                                                                   │
│  U8   ┌─────────────────────────────────────────────────┐       │
│       │  Switch A (Primary)                            │       │
│       └─────────────────────────────────────────────────┘       │
│                                                                   │
│       PDU-A (Left)                          PDU-B (Right)        │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Power Configuration

**Power Redundancy:**
- Each server has **2 redundant PSUs** (Platinum/Titanium efficiency)
- Each PSU connected to separate PDUs
- PDUs connected to separate UPS circuits

**Power Consumption:**
- Per Server Average: ~400-600W (under normal load)
- Total Cluster Power: ~2400W max
- UPS Runtime: [X] minutes at full load

**Power-On Sequence:**
1. Ensure PDUs are powered
2. Power on Switch A
3. Power on Switch B
4. Power on servers: k8s-cp1 → k8s-cp2 → k8s-cp3 → k8s-cp4
5. Wait 5 minutes for cluster convergence

### 1.4 Cabling Matrix

| Server | Port | Connection | Cable Type | VLAN |
|--------|------|------------|------------|------|
| k8s-cp1 | eno1 | Switch A Port 1 | Cat6 Ethernet | VLAN 254 |
| k8s-cp1 | eno2 | Switch B Port 1 | Cat6 Ethernet | VLAN 254 |
| k8s-cp1 | iDRAC | Management Switch | Cat6 Ethernet | VLAN 1 (Mgmt) |
| k8s-cp2 | eno1 | Switch A Port 2 | Cat6 Ethernet | VLAN 254 |
| k8s-cp2 | eno2 | Switch B Port 2 | Cat6 Ethernet | VLAN 254 |
| k8s-cp2 | iDRAC | Management Switch | Cat6 Ethernet | VLAN 1 (Mgmt) |
| k8s-cp3 | eno1 | Switch A Port 3 | Cat6 Ethernet | VLAN 254 |
| k8s-cp3 | eno2 | Switch B Port 3 | Cat6 Ethernet | VLAN 254 |
| k8s-cp3 | iDRAC | Management Switch | Cat6 Ethernet | VLAN 1 (Mgmt) |
| k8s-cp4 | eno1 | Switch A Port 4 | Cat6 Ethernet | VLAN 254 |
| k8s-cp4 | eno2 | Switch B Port 4 | Cat6 Ethernet | VLAN 254 |
| k8s-cp4 | iDRAC | Management Switch | Cat6 Ethernet | VLAN 1 (Mgmt) |
| Switch A | Uplink | Core Network | Fiber/Cat6 | Trunk |
| Switch B | Uplink | Core Network | Fiber/Cat6 | Trunk |
| Switch A | ISL | Switch B Port 24 | Cat6/Fiber | Trunk |

---

## 2. Network Architecture

### 2.1 Network Topology

```
                        ┌─────────────────────┐
                        │  Core Network       │
                        │  (Gateway: .1)      │
                        └──────────┬──────────┘
                                   │
                      ┌────────────┴────────────┐
                      │                         │
          ┌───────────▼──────────┐  ┌──────────▼──────────┐
          │   Switch A           │  │   Switch B          │
          │   (Primary)          │──│   (Secondary)       │
          │                      │  │                     │
          └───┬──┬──┬──┬─────────┘  └─────────┬──┬──┬──┬─┘
              │  │  │  │                       │  │  │  │
              │  │  │  └───────────────────────┘  │  │  │
              │  │  └─────────────────────────────┘  │  │
              │  └───────────────────────────────────┘  │
              └─────────────────────────────────────────┘
              │       │       │       │
         ┌────▼──┐ ┌──▼───┐ ┌▼────┐ ┌▼────┐
         │k8s-cp1│ │k8s-cp2│ │k8s-cp3│ │k8s-cp4│
         │  .10  │ │  .11  │ │  .12  │ │  .13  │
         └───────┘ └───────┘ └───────┘ └───────┘
                   │
            VIP: 10.255.254.100 (Floating)
                   │
         ┌─────────▼──────────┐
         │  Kubernetes API    │
         │  HAProxy + Keepalived│
         └────────────────────┘
```

### 2.2 IP Address Allocation

#### Management Network: 10.255.254.0/24

| Hostname | IP Address | MAC Address | Interface | Purpose |
|----------|------------|-------------|-----------|---------|
| Gateway | 10.255.254.1 | - | - | Network Gateway |
| k8s-cp1 | 10.255.254.10 | [MAC] | eno1 | Control Plane 1 |
| k8s-cp2 | 10.255.254.11 | [MAC] | eno1 | Control Plane 2 |
| k8s-cp3 | 10.255.254.12 | [MAC] | eno1 | Control Plane 3 |
| k8s-cp4 | 10.255.254.13 | [MAC] | eno1 | Control Plane 4 |
| **k8s-api (VIP)** | **10.255.254.100** | **Virtual** | **Floating** | **HA API Endpoint** |

#### Pod Network: 192.168.0.0/16 (Calico CNI)
- Managed by Calico
- Automatic IP allocation for pods
- Cross-node pod communication via VXLAN

#### Service Network: 10.96.0.0/12
- Kubernetes ClusterIP services
- Automatically managed by kube-proxy

### 2.3 Network Switch Configuration

#### Switch A (Primary)
- **Role:** Primary data path
- **Management IP:** [Switch A IP]
- **Uplink:** Port 23 → Core Network
- **ISL (Inter-Switch Link):** Port 24 → Switch B
- **Access Ports:** 1-4 (Servers)

**Port Configuration:**
```
Port 1-4: Access Mode, VLAN 254, Speed Auto, Duplex Auto
Port 23: Trunk Mode, All VLANs, Speed 10G/1G, Uplink
Port 24: Trunk Mode, All VLANs, Speed 10G/1G, ISL
```

**VLAN Configuration:**
```
VLAN 1: Management (Default)
VLAN 254: Kubernetes Cluster Network (10.255.254.0/24)
```

**Spanning Tree:**
```
Protocol: RSTP
Priority: 4096 (Root Bridge)
```

#### Switch B (Secondary)
- **Role:** Backup/Secondary data path
- **Management IP:** [Switch B IP]
- **Uplink:** Port 23 → Core Network
- **ISL (Inter-Switch Link):** Port 24 → Switch A
- **Access Ports:** 1-4 (Servers)

**Port Configuration:**
```
Port 1-4: Access Mode, VLAN 254, Speed Auto, Duplex Auto
Port 23: Trunk Mode, All VLANs, Speed 10G/1G, Uplink
Port 24: Trunk Mode, All VLANs, Speed 10G/1G, ISL
```

**Spanning Tree:**
```
Protocol: RSTP
Priority: 8192 (Secondary Bridge)
```

### 2.4 Firewall Configuration

**Inbound Rules (Applied on all servers):**

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Admin Network | SSH Access |
| 6443 | TCP | 10.255.254.0/24 | Kubernetes API |
| 2379-2380 | TCP | 10.255.254.0/24 | etcd Client/Peer |
| 10250 | TCP | 10.255.254.0/24 | Kubelet API |
| 10257 | TCP | 10.255.254.0/24 | kube-controller-manager |
| 10259 | TCP | 10.255.254.0/24 | kube-scheduler |
| 30000-32767 | TCP | Any | NodePort Services |
| 179 | TCP | 10.255.254.0/24 | Calico BGP |
| 4789 | UDP | 10.255.254.0/24 | Calico VXLAN |
| 8404 | TCP | 10.255.254.0/24 | HAProxy Stats |

**Outbound Rules:**
- Allow all outbound traffic (default)

### 2.5 DNS Configuration

**Server DNS Settings:**
```
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 10.255.254.1
search local
```

**Kubernetes Internal DNS:**
- CoreDNS deployed in kube-system namespace
- Cluster domain: `cluster.local`
- DNS service IP: `10.96.0.10`

**Required External DNS Entries (Optional):**
```
k8s-api.local          → 10.255.254.100
grafana.local          → [Ingress IP]
prometheus.local       → [Ingress IP]
dashboard.local        → [Ingress IP]
```

---

## 3. Server Hardware Specifications

### 3.1 Dell PowerEdge R740 - Common Configuration

**Form Factor:** 2U Rack Server

#### Processor Configuration
- **CPUs:** 2x Intel Xeon Scalable Processors (3rd Gen - Cascade Lake)
- **Cores per CPU:** [X] cores (Total: [Y] cores)
- **Threads:** [Y*2] with Hyper-Threading
- **Base Frequency:** [X] GHz
- **Turbo Frequency:** [Y] GHz
- **Features:**
  - Intel Virtualization Technology (VT-x, VT-d) - Enabled
  - Intel Turbo Boost - Enabled
  - Intel Hyper-Threading - Enabled
  - Intel AES-NI - Enabled

#### Memory Configuration
- **Total RAM:** 128GB per server (512GB total cluster)
- **Type:** DDR4 RDIMM
- **Speed:** 2666 MT/s
- **Configuration:** [X]x [Y]GB DIMMs
- **ECC:** Enabled

#### Storage Configuration
- **Boot Drive:** [X]x [Y]GB SSD in RAID 1
- **Data Drives:** [X]x [Y]TB SSD/HDD
- **RAID Controller:** Dell PERC H730P (2GB NV Cache)
- **RAID Configuration:**
  - RAID 1: Boot drives (OS)
  - RAID 10/5/6: Data drives (Kubernetes storage)

#### Network Interfaces
- **Onboard NICs:**
  - eno1: 1GbE/10GbE (Primary network)
  - eno2: 1GbE/10GbE (Secondary network - not actively configured)
  - eno3, eno4: Available for future use
- **NIC Teaming:** Not currently configured (can be enabled if needed)

#### Power Supply
- **PSUs:** 2x Hot-plug redundant power supplies
- **Wattage:** [X]W each
- **Efficiency:** Platinum/Titanium rated
- **Redundancy:** 1+1 (Each PSU can power entire server)

#### iDRAC Configuration
- **Version:** iDRAC9 Enterprise
- **Management Port:** Dedicated 1GbE (rear panel)
- **IP Addresses:**
  - k8s-cp1: [iDRAC IP 1]
  - k8s-cp2: [iDRAC IP 2]
  - k8s-cp3: [iDRAC IP 3]
  - k8s-cp4: [iDRAC IP 4]
- **Features Enabled:**
  - Remote console (HTML5)
  - Virtual media
  - Power control
  - Hardware monitoring
  - SNMP monitoring

### 3.2 BIOS/UEFI Configuration

**System Profile:** Performance (Optimized for Kubernetes)

**Key Settings:**
```
Boot Mode: UEFI
Boot Sequence: HDD, Virtual Media, Network

Processor Settings:
  - Virtualization Technology: Enabled
  - VT for Directed I/O: Enabled
  - Logical Processor (Hyper-Threading): Enabled
  - Turbo Boost: Enabled

Memory Settings:
  - Memory Operating Mode: Optimizer Mode
  - Node Interleaving: Disabled (for NUMA awareness)

Integrated Devices:
  - Embedded NIC1-4: Enabled
  - SR-IOV Global Enable: Enabled

System Security:
  - Secure Boot: Disabled (for compatibility)
  - TPM Security: On (if available)
```

### 3.3 Individual Server Details

#### k8s-cp1 (Primary Control Plane)
- **Service Tag:** [Dell Service Tag 1]
- **IP Address:** 10.255.254.10
- **iDRAC IP:** [iDRAC IP 1]
- **Role:** Primary control plane, etcd member, worker
- **Current Load:** [CPU/Memory usage]

#### k8s-cp2 (Control Plane)
- **Service Tag:** [Dell Service Tag 2]
- **IP Address:** 10.255.254.11
- **iDRAC IP:** [iDRAC IP 2]
- **Role:** Control plane, etcd member, worker
- **Current Load:** [CPU/Memory usage]

#### k8s-cp3 (Control Plane)
- **Service Tag:** [Dell Service Tag 3]
- **IP Address:** 10.255.254.12
- **iDRAC IP:** [iDRAC IP 3]
- **Role:** Control plane, etcd member, worker
- **Current Load:** [CPU/Memory usage]

#### k8s-cp4 (Control Plane)
- **Service Tag:** [Dell Service Tag 4]
- **IP Address:** 10.255.254.13
- **iDRAC IP:** [iDRAC IP 4]
- **Role:** Control plane, etcd member, worker
- **Current Load:** [CPU/Memory usage]

**Warranty Information:**
- Check warranty status: https://www.dell.com/support
- ProSupport: [Active/Expiry Date]

---

## 4. Kubernetes Cluster Architecture

### 4.1 Cluster Overview

**Cluster Name:** ha-k8s-cluster
**Kubernetes Version:** v1.34.0
**Container Runtime:** containerd v1.7.28
**CNI Plugin:** Calico v3.30.1
**Topology:** Stacked etcd (all nodes are control plane + worker)

### 4.2 High Availability Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    External Clients                           │
└───────────────────────┬───────────────────────────────────────┘
                        │
                        ▼
            VIP: 10.255.254.100:6443
                (Keepalived VRRP)
                        │
        ┌───────────────┼───────────────┐
        │               │               │
    ┌───▼────┐     ┌───▼────┐     ┌───▼────┐     ┌────────┐
    │k8s-cp1 │     │k8s-cp2 │     │k8s-cp3 │     │k8s-cp4 │
    │        │     │        │     │        │     │        │
    │API:6443│     │API:6443│     │API:6443│     │API:6443│
    └───┬────┘     └───┬────┘     └───┬────┘     └───┬────┘
        │              │              │              │
    ┌───▼──────────────▼──────────────▼──────────────▼───┐
    │              etcd Cluster (4 members)              │
    │         Quorum: 3, Fault Tolerance: 1              │
    └────────────────────────────────────────────────────┘
        │              │              │              │
    ┌───▼────┐     ┌───▼────┐     ┌───▼────┐     ┌───▼────┐
    │Control │     │Control │     │Control │     │Control │
    │ Plane  │     │ Plane  │     │ Plane  │     │ Plane  │
    │Components    │Components    │Components    │Components│
    └───┬────┘     └───┬────┘     └───┬────┘     └───┬────┘
        │              │              │              │
    ┌───▼────┐     ┌───▼────┐     ┌───▼────┐     ┌───▼────┐
    │Worker  │     │Worker  │     │Worker  │     │Worker  │
    │ Node   │     │ Node   │     │ Node   │     │ Node   │
    │(Pods)  │     │(Pods)  │     │(Pods)  │     │(Pods)  │
    └────────┘     └────────┘     └────────┘     └────────┘
```

### 4.3 Control Plane Components

**On Each Server:**

| Component | Port | Purpose | Health Check |
|-----------|------|---------|--------------|
| kube-apiserver | 6443 | Kubernetes API endpoint | `https://localhost:6443/healthz` |
| etcd | 2379, 2380 | Distributed key-value store | `etcdctl endpoint health` |
| kube-controller-manager | 10257 | Cluster state management | `https://localhost:10257/healthz` |
| kube-scheduler | 10259 | Pod scheduling | `https://localhost:10259/healthz` |
| kubelet | 10250 | Node agent | `https://localhost:10250/healthz` |
| kube-proxy | - | Network proxy (IPVS mode) | Check iptables/ipvs rules |

### 4.4 High Availability Features

#### Load Balancer Configuration
- **Technology:** HAProxy + Keepalived
- **Virtual IP:** 10.255.254.100
- **HAProxy Port:** 16443 (alternate) / 8443 (current)
- **Backend Servers:** All 4 API servers (port 6443)
- **Health Check:** HTTP GET /healthz
- **Failover Time:** < 5 seconds
- **VRRP Priority:**
  - k8s-cp1: 150 (Master preference)
  - k8s-cp2: 140
  - k8s-cp3: 130
  - k8s-cp4: 120

**Note:** HAProxy may be configured on alternate port or disabled if kube-apiserver binds to VIP directly. Check current configuration with:
```bash
systemctl status haproxy
netstat -tlnp | grep 6443
```

#### etcd Cluster
- **Members:** 4 (k8s-cp1, k8s-cp2, k8s-cp3, k8s-cp4)
- **Quorum:** 3 nodes required
- **Fault Tolerance:** Can survive 1 node failure
- **Data Directory:** `/var/lib/etcd`
- **Backup Schedule:** Daily at 02:00 AM (cron)
- **Backup Location:** `/opt/kubernetes/backups/`

### 4.5 Network Configuration

#### Pod Network (Calico)
- **CIDR:** 192.168.0.0/16
- **Encapsulation:** VXLAN (cross-subnet)
- **MTU:** 1450 (to accommodate VXLAN overhead)
- **IP Pool:** 192.168.0.0/16
- **Block Size:** /26 (64 IPs per node)
- **BGP:** Enabled for routing
- **Network Policy:** Supported

#### Service Network
- **CIDR:** 10.96.0.0/12
- **DNS Service:** 10.96.0.10 (CoreDNS)
- **Proxy Mode:** IPVS
- **NodePort Range:** 30000-32767

### 4.6 Resource Allocation

**Per Server:**
- **Total CPU:** [X] cores
- **Control Plane Reserved:** ~4 cores
- **Available for Workloads:** ~[X-4] cores
- **Total Memory:** 128GB
- **Control Plane Reserved:** ~8GB
- **Available for Workloads:** ~120GB

**Cluster Totals:**
- **Total CPU:** ~[X*4] cores
- **Workload CPU:** ~[(X-4)*4] cores
- **Total Memory:** 512GB
- **Workload Memory:** ~480GB
- **Fault Tolerance:** Can lose 1 server without impact

---

## 5. Access and Credentials

### 5.1 Server Access

#### SSH Access

**Servers:**
```bash
# SSH to individual servers
ssh root@10.255.254.10  # k8s-cp1
ssh root@10.255.254.11  # k8s-cp2
ssh root@10.255.254.12  # k8s-cp3
ssh root@10.255.254.13  # k8s-cp4

# Or by hostname (if DNS configured)
ssh root@k8s-cp1
ssh root@k8s-cp2
ssh root@k8s-cp3
ssh root@k8s-cp4
```

**SSH Keys:**
- Location: [Specify where SSH keys are stored]
- Key Type: RSA 4096-bit / ED25519
- Passphrase Protected: [Yes/No]

**Root Password:**
- Stored in: [Password manager/secure location]
- Last Changed: [Date]
- Expiry Policy: [Policy]

**Ubuntu User (if exists):**
- Username: `ubuntu`
- Sudo Access: Yes (passwordless)

#### iDRAC Access (Out-of-Band Management)

| Server | iDRAC IP | Web URL | Default Port |
|--------|----------|---------|--------------|
| k8s-cp1 | [IP 1] | https://[IP 1] | 443 |
| k8s-cp2 | [IP 2] | https://[IP 2] | 443 |
| k8s-cp3 | [IP 3] | https://[IP 3] | 443 |
| k8s-cp4 | [IP 4] | https://[IP 4] | 443 |

**Credentials:**
- Username: [iDRAC username]
- Password: [Stored in secure location]
- 2FA: [Enabled/Disabled]

**iDRAC Features:**
- Virtual Console: Enabled (HTML5/Java)
- Virtual Media: Enabled
- Remote Power Control: Enabled
- SNMP: Enabled (Community: [X])
- Email Alerts: [Configured email]

### 5.2 Kubernetes Access

#### kubectl Configuration

**Primary Access (from k8s-cp1):**
```bash
# Already configured on k8s-cp1
export KUBECONFIG=/root/.kube/config
kubectl get nodes
```

**Remote Access (from workstation):**
```bash
# Copy kubeconfig from k8s-cp1
scp root@10.255.254.10:/root/.kube/config ~/.kube/config

# Or use the VIP endpoint
kubectl --server=https://10.255.254.100:6443 get nodes
```

**Admin Kubeconfig Location:**
- Server: `/etc/kubernetes/admin.conf`
- Root user: `/root/.kube/config`
- Ubuntu user: `/home/ubuntu/.kube/config`

#### RBAC and Service Accounts

**Cluster Admin:**
- Certificate: `/etc/kubernetes/pki/admin.crt`
- Key: `/etc/kubernetes/pki/admin.key`
- CA: `/etc/kubernetes/pki/ca.crt`

**Service Accounts:**
- `kube-system:default` - System pods
- `monitoring:prometheus` - Prometheus monitoring
- `monitoring:grafana` - Grafana dashboards
- Custom service accounts as needed

**Creating Admin User:**
```bash
# Create service account
kubectl create serviceaccount admin-user -n kube-system

# Create cluster role binding
kubectl create clusterrolebinding admin-user --clusterrole=cluster-admin --serviceaccount=kube-system:admin-user

# Get token
kubectl -n kube-system create token admin-user
```

### 5.3 Web Interfaces

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| HAProxy Stats | http://10.255.254.10:8404/stats | None | Load balancer monitoring |
| Grafana | https://grafana.local or NodePort | admin / [password] | Monitoring dashboards |
| Prometheus | https://prometheus.local or NodePort | None (internal) | Metrics storage |
| Kubernetes Dashboard | https://dashboard.local or NodePort | Token-based | Cluster management UI |
| AlertManager | https://alertmanager.local or NodePort | None | Alert management |

**Dashboard Token Generation:**
```bash
# Get existing token
kubectl -n kube-system get secret | grep admin-user
kubectl -n kube-system describe secret <token-name>

# Or create new token
kubectl -n kube-system create token admin-user --duration=87600h
```

### 5.4 Network Switch Access

**Switch A:**
- Management IP: [Switch A IP]
- Web UI: https://[Switch A IP]
- SSH: ssh admin@[Switch A IP]
- Console: Serial port on front panel

**Switch B:**
- Management IP: [Switch B IP]
- Web UI: https://[Switch B IP]
- SSH: ssh admin@[Switch B IP]
- Console: Serial port on front panel

**Credentials:**
- Username: [Switch admin username]
- Password: [Stored in secure location]
- Enable Password: [If applicable]

### 5.5 Security Best Practices

**Immediate Actions:**
1. Change all default passwords
2. Rotate SSH keys if needed
3. Enable 2FA where supported
4. Review firewall rules
5. Set up audit logging

**Access Control:**
- Use SSH keys instead of passwords
- Implement bastion host for production
- Use kubectl RBAC for least privilege
- Rotate credentials every 90 days
- Monitor access logs regularly

---

## 6. Deployed Components

### 6.1 System Components

| Component | Namespace | Version | Replicas | Purpose |
|-----------|-----------|---------|----------|---------|
| CoreDNS | kube-system | Latest | 2 | Cluster DNS |
| kube-proxy | kube-system | v1.34.0 | 4 (DaemonSet) | Service networking |
| Calico Node | calico-system | v3.30.1 | 4 (DaemonSet) | CNI networking |
| Calico Controllers | calico-system | v3.30.1 | 1 | CNI management |
| Tigera Operator | tigera-operator | Latest | 1 | Calico operator |

### 6.2 Storage Components

| Component | Namespace | Type | Purpose |
|-----------|-----------|------|---------|
| local-path-provisioner | kube-system | Storage Provisioner | Dynamic PV provisioning |
| Storage Classes | - | Configuration | fast-ssd, standard, backup, logs |

**Storage Classes:**
```bash
kubectl get storageclass
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
fast-ssd-storage       local-path-provisioner  Delete          WaitForFirstConsumer
standard-storage       local-path-provisioner  Delete          WaitForFirstConsumer
backup-storage         local-path-provisioner  Retain          WaitForFirstConsumer
logs-storage           local-path-provisioner  Delete          WaitForFirstConsumer
```

### 6.3 Ingress Controller

| Component | Namespace | Version | Configuration |
|-----------|-----------|---------|---------------|
| NGINX Ingress Controller | ingress-nginx | Latest | 4 replicas (HA) |
| Cert-Manager | cert-manager | Latest | SSL/TLS automation |

**Ingress Access:**
- HTTP NodePort: 30080
- HTTPS NodePort: 30443
- Load Balancer: [If configured]

### 6.4 Monitoring Stack

| Component | Namespace | Version | Replicas | Storage |
|-----------|-----------|---------|----------|---------|
| Prometheus | monitoring | Latest | 2 (HA) | 50Gi PVC |
| Grafana | monitoring | Latest | 1 | 10Gi PVC |
| AlertManager | monitoring | Latest | 3 (HA) | 10Gi PVC |
| Loki | monitoring | Latest | 1 | 50Gi PVC |
| Promtail | monitoring | Latest | 4 (DaemonSet) | - |
| Node Exporter | monitoring | Latest | 4 (DaemonSet) | - |
| kube-state-metrics | monitoring | Latest | 1 | - |

**Monitoring Capabilities:**
- Cluster resource metrics
- Node performance metrics
- Pod and container metrics
- Application logs (via Loki)
- Custom application metrics
- Alert rules configured

**Grafana Dashboards:**
- Kubernetes Cluster Overview
- Node Exporter Dashboard
- Prometheus Stats
- etcd Cluster Dashboard
- Calico Network Dashboard
- Application-specific dashboards (as configured)

### 6.5 Additional Services

| Service | Namespace | Purpose | Status |
|---------|-----------|---------|--------|
| Metrics Server | kube-system | Resource metrics API | Operational |
| Kubernetes Dashboard | kubernetes-dashboard | Web UI | Operational (v7.13.0) |

---

## 7. Storage Configuration

### 7.1 Storage Architecture

```
Each Server:
/mnt/k8s-storage/
├── fast-ssd/           # High-performance storage
│   ├── postgresql/     # Database storage
│   ├── redis/         # Cache storage
│   ├── prometheus/    # Metrics storage
│   ├── grafana/       # Dashboard storage
│   └── loki/          # Log storage
├── standard/          # Standard storage
│   ├── general/       # General purpose
│   └── temp/          # Temporary files
├── backup/            # Backup storage
│   ├── databases/     # DB backups
│   ├── configs/       # Config backups
│   └── volumes/       # PV backups
└── logs/              # Log storage
    ├── applications/  # App logs
    └── system/        # System logs
```

### 7.2 Persistent Volumes

**Total PVs Created:** [X] PVs across all nodes
**Available Capacity:** [X] TB total

**PV Distribution:**
- fast-ssd: [X] PVs, [Y] TB total
- standard: [X] PVs, [Y] TB total
- backup: [X] PVs, [Y] TB total
- logs: [X] PVs, [Y] TB total

**Current Usage:**
```bash
# Check PV usage
kubectl get pv
kubectl get pvc --all-namespaces

# Check node storage
df -h /mnt/k8s-storage/
```

### 7.3 Backup Storage

**Backup Locations:**
- **etcd Backups:** `/opt/kubernetes/backups/` on each server
- **Application Backups:** `/mnt/k8s-storage/backup/`
- **External Backup:** [If configured: NAS/S3/etc.]

**Retention Policy:**
- etcd: 7 days local, [X] days external
- Database: 30 days
- Config: 90 days
- Logs: 30 days

### 7.4 Storage Expansion

**Adding Storage to Cluster:**
1. Add physical drives to servers
2. Create RAID arrays via PERC controller
3. Format and mount to `/mnt/k8s-storage/`
4. Create new PVs using storage class
5. Update storage capacity monitoring

**Example:**
```bash
# Create new PV
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: new-pv-name
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: standard-storage
  local:
    path: /mnt/k8s-storage/standard/new-volume
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-cp1
EOF
```

---

## 8. Network Services

### 8.1 HAProxy Configuration

**Configuration File:** `/etc/haproxy/haproxy.cfg`

**Current Status:**
```bash
# Check HAProxy status
systemctl status haproxy

# View HAProxy stats
curl http://localhost:8404/stats

# Test API endpoint via HAProxy
curl -k https://10.255.254.100:6443/healthz
```

**Frontend Configuration:**
- Binds to: [Check current config - may be VIP:6443 or *:8443]
- Mode: TCP
- Backend: kubernetes-api-backend

**Backend Servers:**
- k8s-cp1:6443
- k8s-cp2:6443
- k8s-cp3:6443
- k8s-cp4:6443

**Health Check:**
- Method: TCP check with HTTP GET /healthz
- Interval: 5 seconds
- Rise: 2 checks
- Fall: 3 checks

### 8.2 Keepalived Configuration

**Configuration File:** `/etc/keepalived/keepalived.conf`

**VRRP Instance:**
- Virtual Router ID: 51
- Virtual IP: 10.255.254.100/24
- Interface: eno1
- State: MASTER (k8s-cp1), BACKUP (others)
- Priority: cp1=150, cp2=140, cp3=130, cp4=120
- Advertisement Interval: 1 second

**Current Status:**
```bash
# Check Keepalived status
systemctl status keepalived

# Check VIP assignment
ip addr show | grep 10.255.254.100

# View Keepalived logs
tail -f /var/log/keepalived.log
journalctl -u keepalived -f
```

**Failover Testing:**
```bash
# Simulate failover by stopping Keepalived
systemctl stop keepalived

# Check VIP moves to another node
# Restart after test
systemctl start keepalived
```

### 8.3 Load Balancing Strategy

**Algorithm:** Round-robin across all healthy API servers
**Session Persistence:** None (stateless API)
**Failover:** Automatic removal of unhealthy backends
**Recovery:** Automatic re-addition when healthy

### 8.4 External Access

**NodePort Services:**
- HTTP Ingress: NodePort 30080 on all nodes
- HTTPS Ingress: NodePort 30443 on all nodes
- Custom Services: NodePort range 30000-32767

**LoadBalancer Services:**
- Not currently configured
- Can be added using MetalLB or external LB

**Ingress Configuration:**
```bash
# List all ingress resources
kubectl get ingress --all-namespaces

# Access via NodePort
curl http://10.255.254.10:30080
curl -k https://10.255.254.10:30443
```

---

## 9. Monitoring and Logging

### 9.1 Prometheus Configuration

**Access:**
```bash
# Port-forward to access Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open browser: http://localhost:9090
```

**Metrics Retention:** 15 days
**Scrape Interval:** 30 seconds
**Storage:** 50Gi PVC on fast-ssd storage

**Key Metrics Collected:**
- Node CPU, memory, disk, network
- Container resource usage
- Kubernetes API server metrics
- etcd performance metrics
- Calico network metrics
- Custom application metrics

**Alert Rules:**
- Node down alert
- High CPU/memory usage
- Disk space low
- etcd cluster unhealthy
- Pod crash looping
- API server errors

### 9.2 Grafana Dashboards

**Access:**
```bash
# Port-forward to access Grafana UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Username: admin
# Password: [Check secret or configured password]
```

**Pre-installed Dashboards:**
1. Kubernetes Cluster Overview
2. Node Exporter Full
3. Kubernetes Pods
4. Kubernetes Deployment
5. Prometheus Stats
6. etcd Dashboard
7. Calico Network Dashboard

**Custom Dashboards:**
- [List any custom dashboards created]

### 9.3 Logging (Loki + Promtail)

**Loki:**
- Storage: 50Gi PVC
- Retention: 30 days
- Access: Via Grafana Explore

**Promtail:**
- Runs on all nodes (DaemonSet)
- Collects logs from: /var/log/pods/*
- Labels: namespace, pod, container

**Accessing Logs:**
```bash
# Via kubectl
kubectl logs <pod-name> -n <namespace>

# Via Grafana
# Navigate to Explore → Select Loki data source
# Query: {namespace="default"}
```

### 9.4 AlertManager Configuration

**Access:**
```bash
# Port-forward to access AlertManager UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Open browser: http://localhost:9093
```

**Notification Channels:**
- [Configure as needed: Email, Slack, PagerDuty, etc.]

**Alert Routing:**
- Critical alerts: [Route 1]
- Warning alerts: [Route 2]
- Info alerts: [Route 3]

**Configuration:**
```bash
# AlertManager config stored in ConfigMap
kubectl get configmap -n monitoring kube-prometheus-stack-alertmanager -o yaml
```

### 9.5 Kubernetes Dashboard

**Access:**
```bash
# Get access token
kubectl -n kube-system create token admin-user

# Port-forward dashboard
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443

# Open browser: https://localhost:8443
# Login with token
```

**Features:**
- View cluster resources
- View logs and metrics
- Execute commands in containers
- Scale deployments
- Create/delete resources

### 9.6 Monitoring Commands

```bash
# Cluster health
kubectl get nodes
kubectl get pods --all-namespaces
kubectl top nodes
kubectl top pods --all-namespaces

# Component health
kubectl get componentstatuses
kubectl get --raw /healthz

# etcd health
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Service status on nodes
systemctl status kubelet
systemctl status containerd
systemctl status haproxy
systemctl status keepalived

# Network connectivity
kubectl run test-pod --image=busybox --rm -it -- nslookup kubernetes.default
```

---

## 10. Backup and Disaster Recovery

### 10.1 Backup Strategy

#### etcd Backups (Automated)
**Script:** `/opt/kubernetes/etcd-backup.sh`
**Schedule:** Daily at 02:00 AM (via cron)
**Location:** `/opt/kubernetes/backups/`
**Retention:** 7 days local
**Format:** etcd snapshot (`.db` file)

**Manual Backup:**
```bash
# Create etcd backup manually
/opt/kubernetes/etcd-backup.sh

# Or use etcdctl directly
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot-YYYYMMDD.db \
  --write-out=table
```

#### Kubernetes Configuration Backups
```bash
# Backup all cluster resources
kubectl get all --all-namespaces -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# Backup specific resources
kubectl get configmaps --all-namespaces -o yaml > configmaps-backup.yaml
kubectl get secrets --all-namespaces -o yaml > secrets-backup.yaml
kubectl get ingress --all-namespaces -o yaml > ingress-backup.yaml
kubectl get pv,pvc --all-namespaces -o yaml > storage-backup.yaml

# Backup Helm releases
helm list --all-namespaces -o yaml > helm-releases-backup.yaml
```

#### Certificate Backups
```bash
# Backup Kubernetes certificates
tar -czf k8s-pki-backup-$(date +%Y%m%d).tar.gz /etc/kubernetes/pki/

# Store securely and off-cluster
```

#### Application Data Backups
- Configured per application
- Stored in `/mnt/k8s-storage/backup/`
- Or external backup solution (Velero, Stash, etc.)

### 10.2 Disaster Recovery Procedures

#### Scenario 1: Single Node Failure

**Impact:** Cluster continues operating with 3 nodes
**Recovery Time:** Automatic (0-5 minutes for VIP failover)

**Actions:**
1. Cluster automatically excludes failed node
2. VIP fails over to another node (if failed node had VIP)
3. Workloads reschedule to healthy nodes
4. etcd maintains quorum with 3 nodes

**Node Recovery:**
```bash
# On failed node after hardware repair
systemctl start kubelet
systemctl start containerd

# Verify node joins cluster
kubectl get nodes

# If node doesn't rejoin, check logs
journalctl -u kubelet -f

# May need to reset and rejoin
kubeadm reset
# Then re-run join command from /opt/kubernetes/join-info/
```

#### Scenario 2: Two Node Failure

**Impact:** Cluster at risk - etcd has 2/4 members (no quorum)
**Recovery Time:** Manual intervention required

**Actions:**
1. Restore at least one failed node immediately
2. etcd quorum restored when 3 nodes operational
3. Do not restart remaining nodes until quorum restored

**Emergency Procedure:**
```bash
# If 2 nodes down, DO NOT reboot remaining nodes
# Recover failed nodes first

# Once 3 nodes available, verify etcd quorum
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Check cluster health
kubectl get nodes
kubectl get cs
```

#### Scenario 3: Complete Cluster Failure

**Impact:** Total cluster outage
**Recovery Time:** 2-4 hours (depending on backup age)

**Recovery Steps:**

1. **Restore first control plane node (k8s-cp1):**
```bash
# On k8s-cp1 after hardware recovery
# Restore etcd from backup
systemctl stop kubelet
systemctl stop etcd

# Find latest backup
ls -lt /opt/kubernetes/backups/

# Restore etcd snapshot
ETCDCTL_API=3 etcdctl snapshot restore /opt/kubernetes/backups/etcd-snapshot-LATEST.db \
  --name=k8s-cp1 \
  --initial-cluster=k8s-cp1=https://10.255.254.10:2380,k8s-cp2=https://10.255.254.11:2380,k8s-cp3=https://10.255.254.12:2380,k8s-cp4=https://10.255.254.13:2380 \
  --initial-cluster-token=k8s-ha-token \
  --initial-advertise-peer-urls=https://10.255.254.10:2380 \
  --data-dir=/var/lib/etcd

# Start services
systemctl start etcd
systemctl start kubelet

# Verify cluster starts
kubectl get nodes
```

2. **Recover remaining nodes:**
```bash
# On k8s-cp2, k8s-cp3, k8s-cp4
systemctl start kubelet

# Verify nodes join
kubectl get nodes
```

3. **Restore application data:**
```bash
# Restore PVs from backup
# Restore application configurations
kubectl apply -f cluster-backup-YYYYMMDD.yaml
```

4. **Verify cluster health:**
```bash
# Run validation script
/path/to/08-cluster-validation.sh
```

#### Scenario 4: Split-Brain (Network Partition)

**Symptoms:** Nodes cannot communicate with each other
**Impact:** etcd may have split quorum

**Detection:**
```bash
# Check etcd member connectivity
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

# Check network connectivity
ping 10.255.254.10
ping 10.255.254.11
ping 10.255.254.12
ping 10.255.254.13
```

**Resolution:**
1. Fix network connectivity first
2. Do not restart nodes during network partition
3. Once network restored, verify etcd quorum
4. May need to remove and re-add members if corruption occurred

### 10.3 Backup Verification

**Monthly Backup Test:**
```bash
# Test etcd backup restore (on test node)
ETCDCTL_API=3 etcdctl snapshot restore /opt/kubernetes/backups/etcd-snapshot-LATEST.db \
  --data-dir=/tmp/test-restore

# Verify backup integrity
ls -lh /tmp/test-restore

# Clean up
rm -rf /tmp/test-restore
```

**Quarterly DR Drill:**
1. Schedule maintenance window
2. Simulate node failure
3. Test recovery procedures
4. Document lessons learned
5. Update DR procedures

### 10.4 External Backup Recommendations

**Consider implementing:**
- **Velero** - Kubernetes cluster backup and restore
- **Restic** - Encrypted, deduplicated backups
- **Off-site replication** - AWS S3, Azure Blob, GCS
- **Scheduled exports** - Regular exports to external storage
- **Immutable backups** - Write-once-read-many storage

---

## 11. Operational Procedures

### 11.1 Daily Operations

#### Health Checks
```bash
# Morning cluster health check (5 minutes)
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory | head -20

# Check etcd health
systemctl status etcd

# Check HAProxy/Keepalived
systemctl status haproxy
systemctl status keepalived
ip addr show | grep 10.255.254.100

# Check monitoring
curl -s http://localhost:9090/-/healthy  # Prometheus
```

#### Log Review
```bash
# Check for errors in system logs
journalctl -u kubelet --since "1 hour ago" | grep -i error
journalctl -u containerd --since "1 hour ago" | grep -i error
journalctl -u etcd --since "1 hour ago" | grep -i error

# Check Kubernetes events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | head -50
```

### 11.2 Weekly Operations

#### System Updates
```bash
# Update Ubuntu packages (maintenance window required)
apt update
apt list --upgradable
apt upgrade -y  # Schedule during maintenance window

# Update containerd (if needed)
apt upgrade containerd.io

# Restart services after update
systemctl daemon-reboot
systemctl restart containerd
systemctl restart kubelet
```

#### Backup Verification
```bash
# Verify etcd backups exist
ls -lh /opt/kubernetes/backups/
df -h /opt/kubernetes/backups/

# Check backup age
find /opt/kubernetes/backups/ -name "etcd-snapshot-*.db" -mtime -1
```

#### Certificate Expiry Check
```bash
# Check certificate expiration
kubeadm certs check-expiration

# Renew certificates if < 30 days
# kubeadm certs renew all  # During maintenance window
```

#### Resource Usage Review
```bash
# Check storage usage
df -h /mnt/k8s-storage/
kubectl get pv --sort-by=.spec.capacity.storage

# Check resource quotas (if configured)
kubectl get resourcequotas --all-namespaces

# Review pod resource requests/limits
kubectl get pods --all-namespaces -o json | jq '.items[] | {name:.metadata.name, namespace:.metadata.namespace, requests:.spec.containers[].resources.requests, limits:.spec.containers[].resources.limits}'
```

### 11.3 Monthly Operations

#### Cluster Maintenance
```bash
# Drain node for maintenance (rolling)
kubectl drain k8s-cp2 --ignore-daemonsets --delete-emptydir-data

# Perform maintenance
apt update && apt upgrade -y
systemctl reboot

# Uncordon node after reboot
kubectl uncordon k8s-cp2

# Repeat for other nodes (one at a time)
```

#### Security Audit
```bash
# Review RBAC permissions
kubectl get clusterrolebindings
kubectl get rolebindings --all-namespaces

# Check for pods running as root
kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.securityContext.runAsUser==0 or .spec.containers[].securityContext.runAsUser==0) | "\(.metadata.namespace)/\(.metadata.name)"'

# Review network policies
kubectl get networkpolicies --all-namespaces
```

#### Capacity Planning
```bash
# Generate resource usage report
kubectl top nodes > /tmp/node-usage-$(date +%Y%m%d).txt
kubectl top pods --all-namespaces > /tmp/pod-usage-$(date +%Y%m%d).txt

# Check storage growth trends
du -sh /mnt/k8s-storage/* > /tmp/storage-usage-$(date +%Y%m%d).txt

# Review metrics in Grafana for trends
```

### 11.4 Kubernetes Version Upgrades

**Planning:**
- Review release notes
- Test in non-production first
- Schedule maintenance window (2-4 hours)
- Backup cluster before upgrade
- Notify stakeholders

**Upgrade Procedure (Rolling):**

```bash
# 1. Check current version
kubectl version
kubeadm version

# 2. Upgrade kubeadm on first control plane
apt-mark unhold kubeadm
apt update
apt-cache madison kubeadm  # Find desired version
apt install kubeadm=1.XX.X-00
apt-mark hold kubeadm

# 3. Plan upgrade
kubeadm upgrade plan

# 4. Apply upgrade on first control plane (k8s-cp1)
kubeadm upgrade apply v1.XX.X

# 5. Upgrade kubelet and kubectl on k8s-cp1
apt-mark unhold kubelet kubectl
apt install kubelet=1.XX.X-00 kubectl=1.XX.X-00
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# 6. Upgrade other control planes (k8s-cp2, k8s-cp3, k8s-cp4)
# On each node:
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Upgrade kubeadm
apt-mark unhold kubeadm
apt install kubeadm=1.XX.X-00
apt-mark hold kubeadm

# Upgrade node
kubeadm upgrade node

# Upgrade kubelet and kubectl
apt-mark unhold kubelet kubectl
apt install kubelet=1.XX.X-00 kubectl=1.XX.X-00
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# Uncordon node
kubectl uncordon <node-name>

# 7. Verify cluster after upgrade
kubectl get nodes
kubectl version
kubectl get pods --all-namespaces
```

### 11.5 Adding New Nodes to Cluster

**Worker Node Addition:**

```bash
# 1. Prepare new server (run 01-server-preparation.sh on new node)

# 2. Generate new join token on k8s-cp1
kubeadm token create --print-join-command

# 3. Run join command on new node
kubeadm join 10.255.254.100:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///var/run/containerd/containerd.sock

# 4. Verify node joins
kubectl get nodes

# 5. Label node (if needed)
kubectl label node <new-node-name> node-role.kubernetes.io/worker=worker
```

**Control Plane Addition:**

```bash
# Use join command from /opt/kubernetes/join-info/control-plane-join.sh
# Or generate new:
kubeadm token create --print-join-command --certificate-key $(kubeadm init phase upload-certs --upload-certs | tail -n 1)
```

### 11.6 Removing Nodes from Cluster

```bash
# 1. Drain node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# 2. Delete node from cluster
kubectl delete node <node-name>

# 3. On the node being removed
kubeadm reset
systemctl stop kubelet
systemctl stop containerd

# 4. Clean up iptables (if needed)
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# 5. Remove etcd member (if control plane)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member remove <member-id>
```

---

## 12. Troubleshooting Guide

### 12.1 Common Issues and Solutions

#### Issue: Node Not Ready

**Symptoms:**
```bash
kubectl get nodes
# Shows node status as NotReady
```

**Diagnosis:**
```bash
# Check node conditions
kubectl describe node <node-name>

# Check kubelet status
systemctl status kubelet
journalctl -u kubelet -n 100

# Check containerd
systemctl status containerd

# Check network connectivity
ping <other-node-ip>
```

**Solutions:**
```bash
# Restart kubelet
systemctl restart kubelet

# Restart containerd
systemctl restart containerd

# Check CNI plugin
kubectl get pods -n calico-system

# Reset node (last resort)
kubeadm reset
# Re-join cluster
```

#### Issue: Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -A
# Shows pods in Pending state
```

**Diagnosis:**
```bash
# Describe pod
kubectl describe pod <pod-name> -n <namespace>
# Look for events: Insufficient CPU, memory, or PVC not bound

# Check node resources
kubectl top nodes
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# Check PVC status
kubectl get pvc -n <namespace>
```

**Solutions:**
```bash
# If insufficient resources: Scale down or add nodes
kubectl scale deployment <deployment-name> --replicas=<lower-number>

# If PVC issue: Check storage class and PVs
kubectl get storageclass
kubectl get pv

# If node selector issue: Check labels
kubectl get nodes --show-labels
```

#### Issue: etcd Cluster Unhealthy

**Symptoms:**
```bash
kubectl get cs
# Shows etcd as unhealthy
```

**Diagnosis:**
```bash
# Check etcd pod status
kubectl get pods -n kube-system | grep etcd

# Check etcd health
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check etcd logs
kubectl logs -n kube-system etcd-<node-name>
journalctl -u etcd
```

**Solutions:**
```bash
# Restart etcd pod (if running as static pod)
mv /etc/kubernetes/manifests/etcd.yaml /tmp/
sleep 30
mv /tmp/etcd.yaml /etc/kubernetes/manifests/

# Check disk space (etcd sensitive to disk I/O)
df -h /var/lib/etcd

# If member corrupt: Remove and re-add member
# CAUTION: Only do this with healthy quorum
ETCDCTL_API=3 etcdctl member remove <member-id>
# Re-join node to cluster
```

#### Issue: VIP Not Assigned

**Symptoms:**
```bash
ip addr show | grep 10.255.254.100
# No output - VIP not assigned to any node
```

**Diagnosis:**
```bash
# Check Keepalived status on all nodes
systemctl status keepalived
journalctl -u keepalived -n 50

# Check VRRP traffic (should see advertisements)
tcpdump -i eno1 vrrp -n

# Check firewall (VRRP uses protocol 112)
iptables -L -n | grep 112
```

**Solutions:**
```bash
# Restart Keepalived
systemctl restart keepalived

# Check Keepalived config
cat /etc/keepalived/keepalived.conf

# Ensure VRRP not blocked
ufw allow proto vrrp from 10.255.254.0/24

# Check for IP conflicts
arping -I eno1 10.255.254.100
```

#### Issue: Ingress Not Working

**Symptoms:**
```bash
curl http://10.255.254.10:30080
# Connection refused or 404
```

**Diagnosis:**
```bash
# Check ingress controller pods
kubectl get pods -n ingress-nginx

# Check ingress resources
kubectl get ingress -A

# Check service
kubectl get svc -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

**Solutions:**
```bash
# Restart ingress controller
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Re-create ingress resource
kubectl delete ingress <ingress-name> -n <namespace>
kubectl apply -f <ingress-file>.yaml

# Check ingress class
kubectl get ingressclass
```

#### Issue: DNS Resolution Failures

**Symptoms:**
```bash
kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default
# Resolution fails
```

**Diagnosis:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check DNS service
kubectl get svc -n kube-system kube-dns

# Test DNS from node
nslookup kubernetes.default.svc.cluster.local 10.96.0.10
```

**Solutions:**
```bash
# Restart CoreDNS
kubectl rollout restart deployment -n kube-system coredns

# Check CoreDNS ConfigMap
kubectl get configmap -n kube-system coredns -o yaml

# Ensure resolv.conf correct in pods
kubectl run test --image=busybox --rm -it -- cat /etc/resolv.conf
```

#### Issue: High CPU/Memory Usage

**Symptoms:**
```bash
kubectl top nodes
# Shows high resource usage
```

**Diagnosis:**
```bash
# Identify resource-hungry pods
kubectl top pods --all-namespaces --sort-by=memory
kubectl top pods --all-namespaces --sort-by=cpu

# Check for crashlooping pods
kubectl get pods -A | grep -i crash

# Check system processes on node
ssh <node> top
ssh <node> htop
```

**Solutions:**
```bash
# Scale down resource-heavy deployments
kubectl scale deployment <name> --replicas=<number>

# Set resource limits (if not set)
kubectl set resources deployment <name> --limits=cpu=500m,memory=512Mi

# Restart misbehaving pods
kubectl delete pod <pod-name> -n <namespace>

# Check for pod memory leaks (restart containers)
kubectl rollout restart deployment <name>
```

### 12.2 Diagnostic Commands Reference

```bash
# Cluster Information
kubectl cluster-info
kubectl cluster-info dump  # Detailed cluster state
kubectl version

# Node Information
kubectl get nodes -o wide
kubectl describe node <node-name>
kubectl top nodes

# Pod Information
kubectl get pods -A -o wide
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container instance
kubectl top pods -A

# Service Information
kubectl get svc -A
kubectl describe svc <service-name> -n <namespace>
kubectl get endpoints <service-name> -n <namespace>

# Network Debugging
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash
# Inside netshoot container:
# nslookup kubernetes.default
# curl http://<service-name>.<namespace>.svc.cluster.local
# ping <pod-ip>

# etcd Debugging
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

# Certificate Information
kubeadm certs check-expiration
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout

# System Service Status
systemctl status kubelet
systemctl status containerd
systemctl status haproxy
systemctl status keepalived

# System Logs
journalctl -u kubelet -f
journalctl -u containerd -f
journalctl -u haproxy -f
journalctl -u keepalived -f

# Resource Usage on Node
df -h
free -h
top
iostat -x 1
netstat -tunlp
ss -tunlp

# Network Connectivity
ping <node-ip>
traceroute <node-ip>
tcpdump -i eno1 port 6443
nmap -p 6443 10.255.254.10
curl -k https://10.255.254.100:6443/healthz
```

### 12.3 Emergency Contacts

| Role | Name | Contact | Availability |
|------|------|---------|--------------|
| Infrastructure Lead | [Name] | [Email/Phone] | 24/7 |
| Kubernetes Admin | [Name] | [Email/Phone] | Business hours |
| Network Admin | [Name] | [Email/Phone] | Business hours |
| Dell Hardware Support | Dell ProSupport | [Phone/Portal] | 24/7 |
| On-Call Engineer | [Name] | [Phone/Pager] | 24/7 |

### 12.4 Escalation Procedure

1. **Level 1:** Check this troubleshooting guide
2. **Level 2:** Review logs and Kubernetes events
3. **Level 3:** Contact on-call engineer
4. **Level 4:** Escalate to infrastructure lead
5. **Level 5:** Engage Dell ProSupport for hardware issues

---

## 13. Next Steps and Recommendations

### 13.1 Immediate Next Steps for Development Team

#### 1. Access Verification (Day 1)
- [ ] Test SSH access to all 4 servers
- [ ] Verify iDRAC access for all servers
- [ ] Test kubectl access from k8s-cp1
- [ ] Access Grafana dashboards
- [ ] Access Kubernetes Dashboard
- [ ] Verify network switch access

#### 2. Familiarization (Week 1)
- [ ] Review deployed applications
- [ ] Understand storage layout
- [ ] Review monitoring dashboards
- [ ] Test backup restore procedure (in test environment)
- [ ] Run cluster validation script: `/path/to/08-cluster-validation.sh`
- [ ] Document any questions or concerns

#### 3. Security Hardening (Week 2)
- [ ] Change all default passwords
- [ ] Rotate SSH keys if needed
- [ ] Configure RBAC for development team
- [ ] Set up network policies for applications
- [ ] Configure Pod Security Standards
- [ ] Enable audit logging (if not already)
- [ ] Set up centralized logging (external SIEM)

### 13.2 Infrastructure Improvements to Consider

#### High Priority
1. **External Backup Solution**
   - Implement Velero for cluster backups
   - Set up off-site backup replication (S3, NAS, etc.)
   - Automated backup testing

2. **External Load Balancer** (Optional)
   - Consider MetalLB for LoadBalancer services
   - Or external hardware load balancer
   - For production-grade external access

3. **Certificate Management**
   - Configure Let's Encrypt with cert-manager
   - Automate SSL/TLS for ingress resources
   - Monitor certificate expiration

4. **Monitoring Enhancements**
   - Configure AlertManager notifications (email, Slack, PagerDuty)
   - Set up external monitoring (UptimeRobot, Pingdom)
   - Create custom Grafana dashboards for applications

5. **Security Scanning**
   - Implement Falco for runtime security
   - Set up container image scanning (Trivy, Clair)
   - Regular vulnerability assessments

#### Medium Priority
6. **GitOps Workflow**
   - Implement Flux or ArgoCD
   - Source control for cluster configuration
   - Automated deployments

7. **Service Mesh** (if needed)
   - Consider Istio or Linkerd
   - For advanced traffic management
   - Enhanced observability

8. **Cluster Autoscaling**
   - Vertical Pod Autoscaler (VPA)
   - Horizontal Pod Autoscaler (HPA) based on custom metrics
   - Cluster autoscaling (if adding cloud nodes)

9. **Network Policy Enforcement**
   - Define network policies for all namespaces
   - Implement default-deny policies
   - Use Calico GlobalNetworkPolicy for cluster-wide rules

10. **Storage Enhancements**
    - Consider Rook-Ceph for distributed storage
    - Implement storage quotas and limits
    - Set up storage monitoring and alerts

#### Low Priority
11. **Advanced Networking**
    - Implement NIC bonding for redundancy
    - Configure multiple networks (storage, management, data)
    - VLAN segmentation for different application tiers

12. **Disaster Recovery Testing**
    - Quarterly DR drills
    - Document recovery time objectives (RTO)
    - Document recovery point objectives (RPO)

### 13.3 Application Deployment Recommendations

#### Database Deployment
```yaml
# Example: PostgreSQL with persistent storage
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
spec:
  serviceName: postgresql
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd-storage
      resources:
        requests:
          storage: 50Gi
```

#### Application Deployment Best Practices
- Use Deployments for stateless applications
- Use StatefulSets for stateful applications (databases)
- Define resource requests and limits for all containers
- Use health checks (readiness and liveness probes)
- Use ConfigMaps for configuration
- Use Secrets for sensitive data (encrypted at rest)
- Implement pod disruption budgets
- Use anti-affinity rules for HA applications

#### Ingress Configuration
```yaml
# Example ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.yourdomain.com
    secretName: app-tls
  rules:
  - host: app.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

### 13.4 VPN and Firewall Configuration

#### VPN Setup Recommendations
For remote access to the cluster, consider:

1. **WireGuard VPN**
   - Lightweight and fast
   - Modern cryptography
   - Easy to configure

2. **OpenVPN**
   - Mature and well-supported
   - Works through most firewalls
   - Good for teams

3. **Tailscale** (easiest)
   - Zero-config mesh VPN
   - Built on WireGuard
   - Easy team management

**Example: Deploying OpenVPN in Kubernetes**
```bash
# Using Helm
helm repo add stable https://charts.helm.sh/stable
helm install openvpn stable/openvpn \
  --set service.type=NodePort \
  --set persistence.enabled=true
```

#### Firewall Configuration

**External Firewall Rules (to add):**
```bash
# Allow VPN access
# Port 1194 UDP (OpenVPN)
# Port 51820 UDP (WireGuard)

# Allow HTTPS ingress (if exposing services externally)
# Port 443 TCP

# Allow monitoring access (if needed externally)
# Port 9090 TCP (Prometheus) - via VPN only
# Port 3000 TCP (Grafana) - via ingress with auth
```

**Internal Firewall (already configured):**
- Kubernetes API: 6443/TCP
- NodePort range: 30000-32767/TCP
- Inter-node communication: All traffic between 10.255.254.0/24

### 13.5 Documentation to Create

**Development Team Should Document:**
1. Application architecture diagrams
2. Database schemas and migrations
3. API endpoints and contracts
4. Deployment procedures for each application
5. Environment-specific configurations
6. Secrets management procedures
7. Monitoring and alerting for applications
8. Runbooks for common application issues
9. On-call procedures and escalation paths
10. Capacity planning and scaling decisions

### 13.6 Training Recommendations

**Kubernetes Training:**
- Certified Kubernetes Administrator (CKA) - for 1-2 team members
- Certified Kubernetes Application Developer (CKAD) - for all developers
- Kubernetes security best practices
- Helm chart development

**Infrastructure Training:**
- Dell server management and iDRAC
- Linux system administration (Ubuntu)
- Network troubleshooting
- Prometheus and Grafana
- etcd operations and backup/restore

---

## 14. Support and Escalation

### 14.1 Vendor Support Contacts

#### Dell Hardware Support
- **Website:** https://www.dell.com/support
- **Phone:** [Dell Support Number for your region]
- **Service Tags:**
  - k8s-cp1: [Service Tag 1]
  - k8s-cp2: [Service Tag 2]
  - k8s-cp3: [Service Tag 3]
  - k8s-cp4: [Service Tag 4]
- **ProSupport:** [Active/Expiry Date]
- **Warranty:** Check at https://www.dell.com/support

#### Network Switch Support
- **Vendor:** [Switch Vendor]
- **Model:** [Switch Model]
- **Support Phone:** [Support Number]
- **Contract Number:** [Contract/Serial Numbers]

#### Software Support
- **Ubuntu Pro:** [If applicable]
- **Kubernetes:** Community support via GitHub/Slack
- **Calico:** Tigera support (if applicable)

### 14.2 Internal Support Structure

| Level | Contact | Scope | Response Time |
|-------|---------|-------|---------------|
| L1 | [Help Desk] | General issues, password resets | 2 hours |
| L2 | [Operations Team] | Kubernetes application issues | 4 hours |
| L3 | [Infrastructure Team] | Cluster and hardware issues | 2 hours (critical) |
| L4 | [Architecture Team] | Design decisions, major changes | 1 business day |

### 14.3 Escalation Procedure

1. **Application Issue:** Developer → L2 Operations → L3 Infrastructure
2. **Cluster Issue:** L3 Infrastructure → L4 Architecture → Vendor Support
3. **Hardware Issue:** L3 Infrastructure → Dell ProSupport
4. **Network Issue:** L3 Infrastructure → Network Team → Switch Vendor
5. **Critical Outage:** Immediate escalation to L3 and notify management

### 14.4 Communication Channels

- **Incident Management:** [Ticket system]
- **Team Chat:** [Slack/Teams channel]
- **On-Call:** [PagerDuty/Opsgenie]
- **Status Page:** [Public status page if applicable]
- **Documentation:** [Wiki/Confluence]

### 14.5 SLA and Response Times

| Severity | Description | Response Time | Resolution Time |
|----------|-------------|---------------|-----------------|
| P1 - Critical | Cluster down, data loss | 15 minutes | 4 hours |
| P2 - High | Degraded service, node down | 1 hour | 8 hours |
| P3 - Medium | Minor issues, non-critical errors | 4 hours | 2 business days |
| P4 - Low | Questions, feature requests | 1 business day | Best effort |

---

## 15. Handover Checklist

### 15.1 Pre-Handover Verification

- [x] All 4 servers operational and clustered
- [x] Kubernetes cluster healthy (4/4 nodes Ready)
- [x] etcd cluster healthy (4/4 members)
- [x] Monitoring stack operational
- [x] Ingress controller deployed
- [x] Storage configured and tested
- [x] Backups configured and tested
- [x] Network redundancy verified
- [x] Cluster validation tests passed
- [x] Documentation completed

### 15.2 Handover Meeting Agenda

1. **Infrastructure Overview** (30 minutes)
   - Physical layout and connectivity
   - Server specifications
   - Network topology
   - Power and cooling

2. **Cluster Architecture** (45 minutes)
   - Kubernetes components
   - HA configuration
   - Storage architecture
   - Network architecture

3. **Access and Credentials** (15 minutes)
   - Server access (SSH, iDRAC)
   - Kubernetes access (kubectl)
   - Web interfaces (Grafana, Dashboard)
   - Credential management

4. **Operations Walkthrough** (60 minutes)
   - Daily health checks
   - Monitoring and alerting
   - Backup verification
   - Common troubleshooting

5. **Q&A and Knowledge Transfer** (30 minutes)
   - Address questions
   - Hands-on practice
   - Contact information

### 15.3 Post-Handover Tasks

**Within 24 hours:**
- [ ] Development team has tested access to all systems
- [ ] Passwords changed where required
- [ ] Contact information verified
- [ ] Any urgent questions addressed

**Within 1 week:**
- [ ] Development team completes infrastructure familiarization
- [ ] First health check performed independently
- [ ] Questions documented and answered
- [ ] Feedback on documentation collected

**Within 1 month:**
- [ ] First independent maintenance window completed
- [ ] Backup restore tested
- [ ] Monitoring alerts configured for applications
- [ ] Team comfortable with operations

### 15.4 Sign-Off

**Infrastructure Provider:**
- Name: ______________________________
- Signature: ______________________________
- Date: ______________________________

**Development Team Lead:**
- Name: ______________________________
- Signature: ______________________________
- Date: ______________________________

**Acceptance Criteria Met:**
- [ ] All systems operational and tested
- [ ] Documentation reviewed and accepted
- [ ] Access verified for all team members
- [ ] Training completed
- [ ] Support contacts established

---

## Appendix A: Quick Reference

### Server Access
```bash
ssh root@10.255.254.10  # k8s-cp1
ssh root@10.255.254.11  # k8s-cp2
ssh root@10.255.254.12  # k8s-cp3
ssh root@10.255.254.13  # k8s-cp4
```

### Cluster Access
```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Health Checks
```bash
# Quick cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl get componentstatuses

# VIP check
ip addr show | grep 10.255.254.100

# Service status
systemctl status kubelet haproxy keepalived
```

### Emergency Contacts
- Infrastructure Lead: [Phone]
- On-Call Engineer: [Phone]
- Dell Support: [Phone]

---

## Appendix B: Network Diagrams

[Include detailed network diagrams here if available]

---

## Appendix C: Configuration Files

### Important Configuration Locations
```bash
# Kubernetes
/etc/kubernetes/admin.conf
/etc/kubernetes/pki/
/var/lib/etcd/

# Container Runtime
/etc/containerd/config.toml

# HAProxy
/etc/haproxy/haproxy.cfg

# Keepalived
/etc/keepalived/keepalived.conf

# Network
/etc/netplan/50-cloud-init.yaml
/etc/hosts

# Backups
/opt/kubernetes/backups/
/opt/kubernetes/etcd-backup.sh
```

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | [Date] | [Your Name] | Initial handover documentation |

---

**END OF DOCUMENT**

---

**Notes:**
- Replace all placeholder values ([X], [IP addresses], [Names], etc.) with actual values
- Add actual MAC addresses, service tags, and credentials in secure locations
- Update network switch details with specific models and configurations
- Include actual backup locations and schedule details
- Add specific contact information for support
- Attach any additional diagrams or screenshots as needed

This document should be treated as **CONFIDENTIAL** and contain sensitive information. Store securely and distribute only to authorized personnel.
