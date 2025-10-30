# Multi-Environment Kubernetes Infrastructure - Complete Handover Documentation
## Production, Staging, and Development Environments

---

## Document Information

**Project:** Multi-Environment Kubernetes Infrastructure
**Infrastructure Provider:** [Your Organization]
**Deployment Date:** October 2025
**Handover Date:** [Date]
**Document Version:** 1.0
**Status:** Production-Ready Infrastructure

---

## Executive Summary

This document provides comprehensive handover information for **three Kubernetes environments** deployed on Dell PowerEdge R740 physical servers. The infrastructure includes:

- **Production Environment**: 4-server HA cluster with full redundancy
- **Staging Environment**: 2-server cluster with limited HA for pre-production testing
- **Development Environment**: Single-server cluster for development and testing

### Infrastructure Overview

| Environment | Servers | Network | VIP | HA Level | Fault Tolerance |
|-------------|---------|---------|-----|----------|-----------------|
| **Production** | 4x R740 | 10.255.254.0/24 | 10.255.254.100 | Full HA | 1 node failure |
| **Staging** | 2x R740 | 10.255.253.0/24 | 10.255.253.100 | Limited HA | 0 node failure |
| **Development** | 1x R740 | 10.255.252.0/24 | None | No HA | N/A |

### Current State

**Production:**
- ✅ All 4 servers operational and clustered
- ✅ Kubernetes HA cluster deployed (stacked etcd)
- ✅ Network redundancy with 2 switches
- ✅ Monitoring and logging operational
- ✅ Automated backups configured (30-day retention)
- ✅ Storage classes configured
- ✅ Ingress controller deployed

**Staging:**
- ✅ Both servers operational and clustered
- ✅ Kubernetes cluster deployed
- ✅ Network redundancy configured
- ✅ Monitoring and logging operational
- ✅ Automated backups configured (7-day retention)
- ✅ Storage classes configured
- ✅ Ingress controller deployed

**Development:**
- ✅ Single server operational
- ✅ Kubernetes cluster deployed
- ✅ Monitoring operational (lightweight)
- ✅ Storage classes configured
- ✅ Ingress controller deployed
- ⚠️ No automated backups (by design)

---

## Table of Contents

1. [Physical Infrastructure Overview](#1-physical-infrastructure-overview)
2. [Network Architecture](#2-network-architecture)
3. [Server Hardware Specifications](#3-server-hardware-specifications)
4. [Production Environment](#4-production-environment)
5. [Staging Environment](#5-staging-environment)
6. [Development Environment](#6-development-environment)
7. [Access and Credentials](#7-access-and-credentials)
8. [Deployed Components](#8-deployed-components)
9. [Storage Configuration](#9-storage-configuration)
10. [Monitoring and Logging](#10-monitoring-and-logging)
11. [Backup and Disaster Recovery](#11-backup-and-disaster-recovery)
12. [Operational Procedures](#12-operational-procedures)
13. [Troubleshooting Guide](#13-troubleshooting-guide)
14. [Security Recommendations](#14-security-recommendations)
15. [Next Steps](#15-next-steps)

---

## 1. Physical Infrastructure Overview

### 1.1 Hardware Inventory

**Total Servers:** 7x Dell PowerEdge R740 (2U Rack Servers)

| Server | Environment | IP Address | Role | Rack Location |
|--------|-------------|------------|------|---------------|
| k8s-cp1 | Production | 10.255.254.10 | Control Plane + Worker | Rack 1, U10-11 |
| k8s-cp2 | Production | 10.255.254.11 | Control Plane + Worker | Rack 1, U12-13 |
| k8s-cp3 | Production | 10.255.254.12 | Control Plane + Worker | Rack 1, U14-15 |
| k8s-cp4 | Production | 10.255.254.13 | Control Plane + Worker | Rack 1, U16-17 |
| k8s-stg1 | Staging | 10.255.253.10 | Control Plane + Worker | Rack 2, U10-11 |
| k8s-stg2 | Staging | 10.255.253.11 | Control Plane + Worker | Rack 2, U12-13 |
| k8s-dev1 | Development | 10.255.252.10 | Control Plane + Worker | Rack 2, U14-15 |

**Network Equipment:**
- 2x Network Switches (redundant configuration for production/staging)
- 2x PDUs (Power Distribution Units) per rack
- 1x UPS system per rack

### 1.2 Physical Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                        RACK 1 - Production                       │
├─────────────────────────────────────────────────────────────────┤
│  U17  ┌───────────────────────────────────────────────┐         │
│       │  k8s-cp4 (10.255.254.13) - Dell R740        │         │
│  U16  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U15  ┌───────────────────────────────────────────────┐         │
│       │  k8s-cp3 (10.255.254.12) - Dell R740        │         │
│  U14  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U13  ┌───────────────────────────────────────────────┐         │
│       │  k8s-cp2 (10.255.254.11) - Dell R740        │         │
│  U12  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U11  ┌───────────────────────────────────────────────┐         │
│       │  k8s-cp1 (10.255.254.10) - Dell R740        │         │
│  U10  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U9   ┌───────────────────────────────────────────────┐         │
│       │  Switch B (Secondary)                        │         │
│       └───────────────────────────────────────────────┘         │
│                                                                   │
│  U8   ┌───────────────────────────────────────────────┐         │
│       │  Switch A (Primary)                          │         │
│       └───────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     RACK 2 - Staging/Dev                         │
├─────────────────────────────────────────────────────────────────┤
│  U15  ┌───────────────────────────────────────────────┐         │
│       │  k8s-dev1 (10.255.252.10) - Dell R740       │         │
│  U14  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U13  ┌───────────────────────────────────────────────┐         │
│       │  k8s-stg2 (10.255.253.11) - Dell R740       │         │
│  U12  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U11  ┌───────────────────────────────────────────────┐         │
│       │  k8s-stg1 (10.255.253.10) - Dell R740       │         │
│  U10  └───────────────────────────────────────────────┘         │
│                                                                   │
│  U9   ┌───────────────────────────────────────────────┐         │
│       │  Switch B (Secondary)                        │         │
│       └───────────────────────────────────────────────┘         │
│                                                                   │
│  U8   ┌───────────────────────────────────────────────┐         │
│       │  Switch A (Primary)                          │         │
│       └───────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Power Configuration

**Per Server:**
- 2x Hot-plug redundant PSUs (Platinum/Titanium efficiency)
- Power rating: 750W-1100W per PSU
- Each PSU connected to separate PDU
- Average consumption: 400-600W under normal load

**Total Power Consumption:**
- Production cluster: ~2,400W (4 servers × ~600W)
- Staging cluster: ~1,200W (2 servers × ~600W)
- Development server: ~600W (1 server × ~600W)
- **Total infrastructure: ~4,200W**

**Power-On Sequence (Critical for Production/Staging):**
1. Power on switches first
2. Power on servers in order: cp1 → cp2 → cp3 → cp4
3. Wait 5-10 minutes for cluster convergence
4. Verify VIP assignment and cluster health

---

## 2. Network Architecture

### 2.1 Network Segmentation

**Production Network: 10.255.254.0/24**
- Gateway: 10.255.254.1
- VIP: 10.255.254.100 (Floating IP managed by Keepalived)
- Server IPs: 10.255.254.10-13
- DNS: 8.8.8.8, 8.8.4.4, 10.255.254.1

**Staging Network: 10.255.253.0/24**
- Gateway: 10.255.253.1
- VIP: 10.255.253.100 (Floating IP managed by Keepalived)
- Server IPs: 10.255.253.10-11
- DNS: 8.8.8.8, 8.8.4.4, 10.255.253.1

**Development Network: 10.255.252.0/24**
- Gateway: 10.255.252.1
- Server IP: 10.255.252.10
- DNS: 8.8.8.8, 8.8.4.4, 10.255.252.1

### 2.2 Network Topology

```
                    ┌─────────────────────┐
                    │  Core Network       │
                    │  (Gateway)          │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
     Production            Staging            Development
   10.255.254.0/24      10.255.253.0/24    10.255.252.0/24
          │                    │                    │
          │                    │                    │
   ┌──────▼────────┐    ┌─────▼──────┐      ┌─────▼──────┐
   │ Switch A + B  │    │ Switch A+B │      │  Switch    │
   │  (Redundant)  │    │ (Redundant)│      │  (Single)  │
   └───────┬───────┘    └─────┬──────┘      └─────┬──────┘
           │                  │                    │
    ┌──────┴──────┐    ┌──────┴──────┐            │
    │   4 Nodes   │    │   2 Nodes   │       ┌────▼────┐
    │  VIP: .100  │    │  VIP: .100  │       │ 1 Node  │
    └─────────────┘    └─────────────┘       └─────────┘
```

### 2.3 Firewall Rules

**Common Ports (All Environments):**

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Admin Network | SSH Access |
| 6443 | TCP | Cluster Network | Kubernetes API |
| 2379-2380 | TCP | Cluster Network | etcd Client/Peer |
| 10250 | TCP | Cluster Network | Kubelet API |
| 10257 | TCP | Cluster Network | kube-controller-manager |
| 10259 | TCP | Cluster Network | kube-scheduler |
| 30000-32767 | TCP | Any | NodePort Services |
| 179 | TCP | Cluster Network | Calico BGP |
| 4789 | UDP | Cluster Network | Calico VXLAN |

**Production/Staging Additional Ports:**

| Port | Protocol | Purpose |
|------|----------|---------|
| 8404 | TCP | HAProxy Statistics |
| 112 | VRRP | Keepalived VRRP Protocol |

### 2.4 Cabling Matrix

**Production (per server):**
- eno1 → Switch A (Primary data path, VLAN 254)
- eno2 → Switch B (Secondary data path, VLAN 254)
- iDRAC → Management Switch (VLAN 1)

**Staging (per server):**
- eno1 → Switch A (Primary data path, VLAN 253)
- eno2 → Switch B (Secondary data path, VLAN 253)
- iDRAC → Management Switch (VLAN 1)

**Development:**
- eno1 → Switch (Data path, VLAN 252)
- iDRAC → Management Switch (VLAN 1)

---

## 3. Server Hardware Specifications

### 3.1 Dell PowerEdge R740 - Standard Configuration

**Common Specifications (All 7 Servers):**

**Processor:**
- 2x Intel Xeon Scalable Processors (3rd Gen - Cascade Lake)
- Total cores: 32-56 cores per server (depending on specific CPU model)
- Hyper-Threading: Enabled
- Virtualization: VT-x, VT-d enabled
- Turbo Boost: Enabled
- AES-NI: Enabled

**Memory:**
- 128GB DDR4 RDIMM per server
- Speed: 2666 MT/s
- ECC: Enabled
- Total cluster memory:
  - Production: 512GB (4 × 128GB)
  - Staging: 256GB (2 × 128GB)
  - Development: 128GB (1 × 128GB)

**Storage:**
- Boot Drive: 2× SSD in RAID 1 (OS installation)
- Data Drives: Multiple SSDs/HDDs (configured per server)
- RAID Controller: Dell PERC H730P (2GB NV Cache)
- RAID Configuration:
  - RAID 1: Boot drives
  - RAID 10/5/6: Data drives (varies by server)

**Network Interfaces:**
- 4× 1GbE or 10GbE onboard NICs
  - eno1: Primary network interface (active)
  - eno2: Secondary network interface (configured for redundancy)
  - eno3, eno4: Available for future use
- Dedicated 1GbE iDRAC management port

**Power:**
- 2× Hot-plug redundant PSUs
- 750W-1100W per PSU
- Platinum/Titanium efficiency rating
- 1+1 Redundancy (each PSU can power entire server)

**Remote Management:**
- iDRAC9 Enterprise
- Features: Remote console (HTML5), virtual media, power control, hardware monitoring

### 3.2 BIOS/UEFI Configuration

**Applied to All Servers:**

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

System Profile: Performance (for Kubernetes workloads)

Integrated Devices:
  - Embedded NIC1-4: Enabled
  - SR-IOV Global Enable: Enabled

System Security:
  - Secure Boot: Disabled (for compatibility)
  - TPM Security: On (if available)
```

### 3.3 Individual Server Details

#### Production Environment

**k8s-cp1 (Primary Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_1]
- IP: 10.255.254.10
- iDRAC IP: [iDRAC_IP_1]
- Role: Primary control plane, etcd member, worker
- VIP Priority: 150 (prefers to hold VIP)

**k8s-cp2 (Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_2]
- IP: 10.255.254.11
- iDRAC IP: [iDRAC_IP_2]
- Role: Control plane, etcd member, worker
- VIP Priority: 140

**k8s-cp3 (Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_3]
- IP: 10.255.254.12
- iDRAC IP: [iDRAC_IP_3]
- Role: Control plane, etcd member, worker
- VIP Priority: 130

**k8s-cp4 (Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_4]
- IP: 10.255.254.13
- iDRAC IP: [iDRAC_IP_4]
- Role: Control plane, etcd member, worker
- VIP Priority: 120

#### Staging Environment

**k8s-stg1 (Primary Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_5]
- IP: 10.255.253.10
- iDRAC IP: [iDRAC_IP_5]
- Role: Primary control plane, etcd member, worker
- VIP Priority: 150

**k8s-stg2 (Control Plane)**
- Service Tag: [DELL_SERVICE_TAG_6]
- IP: 10.255.253.11
- iDRAC IP: [iDRAC_IP_6]
- Role: Control plane, etcd member, worker
- VIP Priority: 140

#### Development Environment

**k8s-dev1 (Single Node)**
- Service Tag: [DELL_SERVICE_TAG_7]
- IP: 10.255.252.10
- iDRAC IP: [iDRAC_IP_7]
- Role: Control plane, etcd, worker (all-in-one)
- No VIP (single node)

**Warranty Information:**
- Check warranty status: https://www.dell.com/support
- Dell ProSupport: [Active/Expiry Date - check with service tags]

---

## 4. Production Environment

### 4.1 Cluster Architecture

**Configuration:**
- 4 nodes (k8s-cp1 through k8s-cp4)
- Kubernetes version: v1.34.0
- Container runtime: containerd v1.7.28
- CNI: Calico v3.30.1
- Topology: Stacked etcd (etcd on control plane nodes)

**High Availability Setup:**

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
    │HAProxy │     │HAProxy │     │HAProxy │     │HAProxy │
    │API:6443│     │API:6443│     │API:6443│     │API:6443│
    └───┬────┘     └───┬────┘     └───┬────┘     └───┬────┘
        │              │              │              │
    ┌───▼──────────────▼──────────────▼──────────────▼───┐
    │              etcd Cluster (4 members)              │
    │         Quorum: 3, Fault Tolerance: 1              │
    └────────────────────────────────────────────────────┘
        │              │              │              │
    ┌───▼────┐     ┌───▼────┐     ┌───▼────┐     ┌───▼────┐
    │Worker  │     │Worker  │     │Worker  │     │Worker  │
    │ Pods   │     │ Pods   │     │ Pods   │     │ Pods   │
    └────────┘     └────────┘     └────────┘     └────────┘
```

### 4.2 Key Features

**Fault Tolerance:**
- Can survive 1 node failure without service disruption
- etcd maintains quorum with 3/4 nodes
- API server accessible via VIP with automatic failover
- Workloads automatically rescheduled on failure

**Load Balancing:**
- HAProxy: Load balances API requests across all 4 nodes
- Keepalived: Manages VIP with VRRP protocol
- Health checks: Automatic removal of unhealthy backends
- Failover time: < 5 seconds

**Network:**
- Pod CIDR: 192.168.0.0/16 (Calico managed)
- Service CIDR: 10.96.0.0/12
- Calico encapsulation: VXLAN
- Network policies: Supported

### 4.3 Critical Endpoints

```
Kubernetes API (VIP):  https://10.255.254.100:6443
HAProxy Stats:         http://10.255.254.10:8404/stats
Ingress HTTP:          http://[any-node-ip]:30080
Ingress HTTPS:         https://[any-node-ip]:30443
```

### 4.4 Resource Capacity

**Total Cluster Resources:**
- CPU: ~200 cores (50 cores per server × 4)
- Memory: 512GB total
- Control plane overhead: ~32GB memory, ~16 cores
- Available for workloads: ~480GB memory, ~184 cores

**Fault-Tolerant Capacity:**
- Can lose 1 node and maintain: ~360GB memory, ~138 cores

---

## 5. Staging Environment

### 5.1 Cluster Architecture

**Configuration:**
- 2 nodes (k8s-stg1, k8s-stg2)
- Kubernetes version: v1.34.0
- Container runtime: containerd v1.7.28
- CNI: Calico v3.30.1
- Topology: Stacked etcd (etcd on control plane nodes)

**Limited HA Setup:**

```
                External Clients
                       │
                       ▼
           VIP: 10.255.253.100:6443
               (Keepalived VRRP)
                       │
              ┌────────┴────────┐
              │                 │
         ┌────▼─────┐     ┌────▼─────┐
         │k8s-stg1  │     │k8s-stg2  │
         │HAProxy   │     │HAProxy   │
         │API:6443  │     │API:6443  │
         └────┬─────┘     └────┬─────┘
              │                 │
         ┌────▼─────────────────▼────┐
         │   etcd Cluster (2 members)│
         │   Quorum: 2/2 (NO FAULT   │
         │   TOLERANCE!)              │
         └────┬─────────────────┬─────┘
              │                 │
         ┌────▼─────┐     ┌────▼─────┐
         │Worker    │     │Worker    │
         │Pods      │     │Pods      │
         └──────────┘     └──────────┘
```

### 5.2 Critical Limitations

⚠️ **ZERO FAULT TOLERANCE**: Both nodes must be operational for cluster to function.

**Why?**
- etcd requires quorum (majority of nodes)
- With 2 nodes, quorum = 2/2
- If 1 node fails, quorum is lost (1/2 is not majority)
- Cluster becomes read-only when quorum is lost

**Impact:**
- ANY single node failure = cluster outage
- Maintenance must be carefully planned
- NOT suitable for critical production workloads
- Perfect for pre-production testing

### 5.3 Critical Endpoints

```
Kubernetes API (VIP):  https://10.255.253.100:6443
HAProxy Stats:         http://10.255.253.10:8404/stats
Ingress HTTP:          http://[any-node-ip]:30080
Ingress HTTPS:         https://[any-node-ip]:30443
```

### 5.4 Resource Capacity

**Total Cluster Resources:**
- CPU: ~100 cores (50 cores per server × 2)
- Memory: 256GB total
- Control plane overhead: ~16GB memory, ~8 cores
- Available for workloads: ~240GB memory, ~92 cores

---

## 6. Development Environment

### 6.1 Cluster Architecture

**Configuration:**
- 1 node (k8s-dev1)
- Kubernetes version: v1.34.0
- Container runtime: containerd v1.7.28
- CNI: Calico v3.30.1
- Topology: Single-node (all components on one server)

**Simple Setup:**

```
        ┌─────────────────────────┐
        │      k8s-dev1           │
        │  10.255.252.10:6443     │
        │                         │
        │  ┌──────────────────┐   │
        │  │  API Server      │   │
        │  │  etcd (single)   │   │
        │  │  Controller Mgr  │   │
        │  │  Scheduler       │   │
        │  └──────────────────┘   │
        │           │             │
        │  ┌────────▼─────────┐   │
        │  │   Worker Node    │   │
        │  │   (Workload Pods)│   │
        │  └──────────────────┘   │
        └─────────────────────────┘
```

### 6.2 Characteristics

**Pros:**
- Simple to manage
- Fast iteration cycles
- All resources available for development
- Low complexity
- No network overhead between nodes

**Cons:**
- Single point of failure
- No HA testing possible
- Limited capacity
- Not representative of production architecture

**Best For:**
- Feature development
- Testing application deployments
- Learning Kubernetes
- Quick prototyping

### 6.3 Critical Endpoints

```
Kubernetes API:   https://10.255.252.10:6443
Ingress HTTP:     http://10.255.252.10:30080
Ingress HTTPS:    https://10.255.252.10:30443
```

### 6.4 Resource Capacity

**Single Server Resources:**
- CPU: ~50 cores
- Memory: 128GB total
- Control plane overhead: ~8GB memory, ~4 cores
- Available for workloads: ~120GB memory, ~46 cores

---

## 7. Access and Credentials

### 7.1 SSH Access

**Production Servers:**
```bash
ssh root@10.255.254.10  # k8s-cp1
ssh root@10.255.254.11  # k8s-cp2
ssh root@10.255.254.12  # k8s-cp3
ssh root@10.255.254.13  # k8s-cp4
```

**Staging Servers:**
```bash
ssh root@10.255.253.10  # k8s-stg1
ssh root@10.255.253.11  # k8s-stg2
```

**Development Server:**
```bash
ssh root@10.255.252.10  # k8s-dev1
```

**Authentication:**
- Method: SSH key-based authentication (recommended)
- Root password: [Stored securely - location TBD]
- SSH keys: [Location TBD]
- Key type: RSA 4096-bit or ED25519

### 7.2 iDRAC Access (Out-of-Band Management)

**Production:**
| Server | iDRAC IP | Web Interface |
|--------|----------|---------------|
| k8s-cp1 | [iDRAC_IP_1] | https://[iDRAC_IP_1] |
| k8s-cp2 | [iDRAC_IP_2] | https://[iDRAC_IP_2] |
| k8s-cp3 | [iDRAC_IP_3] | https://[iDRAC_IP_3] |
| k8s-cp4 | [iDRAC_IP_4] | https://[iDRAC_IP_4] |

**Staging:**
| Server | iDRAC IP | Web Interface |
|--------|----------|---------------|
| k8s-stg1 | [iDRAC_IP_5] | https://[iDRAC_IP_5] |
| k8s-stg2 | [iDRAC_IP_6] | https://[iDRAC_IP_6] |

**Development:**
| Server | iDRAC IP | Web Interface |
|--------|----------|---------------|
| k8s-dev1 | [iDRAC_IP_7] | https://[iDRAC_IP_7] |

**Credentials:**
- Username: [iDRAC_USERNAME]
- Password: [Stored securely]
- Features: Remote console (HTML5), virtual media, power control, hardware monitoring

### 7.3 Kubernetes Access

**Production - kubectl:**
```bash
# From k8s-cp1
export KUBECONFIG=/root/.kube/config
kubectl get nodes

# From remote workstation
scp root@10.255.254.10:/root/.kube/config ~/.kube/prod-config
export KUBECONFIG=~/.kube/prod-config
kubectl get nodes

# Via VIP
kubectl --server=https://10.255.254.100:6443 get nodes
```

**Staging - kubectl:**
```bash
# From k8s-stg1
export KUBECONFIG=/root/.kube/config
kubectl get nodes

# From remote workstation
scp root@10.255.253.10:/root/.kube/config ~/.kube/staging-config
export KUBECONFIG=~/.kube/staging-config
kubectl get nodes
```

**Development - kubectl:**
```bash
# From k8s-dev1
export KUBECONFIG=/root/.kube/config
kubectl get nodes

# From remote workstation
scp root@10.255.252.10:/root/.kube/config ~/.kube/dev-config
export KUBECONFIG=~/.kube/dev-config
kubectl get nodes
```

**Kubeconfig Locations:**
- Admin config: `/etc/kubernetes/admin.conf`
- Root user: `/root/.kube/config`
- Certificates: `/etc/kubernetes/pki/`

### 7.4 Web Interfaces

**Production:**
| Service | URL | Credentials |
|---------|-----|-------------|
| HAProxy Stats | http://10.255.254.10:8404/stats | None |
| Grafana | Port-forward or NodePort | admin / [password] |
| Prometheus | Port-forward or NodePort | None |
| Kubernetes Dashboard | Port-forward or NodePort | Token-based |

**Staging:**
| Service | URL | Credentials |
|---------|-----|-------------|
| HAProxy Stats | http://10.255.253.10:8404/stats | None |
| Grafana | Port-forward or NodePort | admin / [password] |
| Prometheus | Port-forward or NodePort | None |

**Development:**
| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | Port-forward or NodePort | admin / [password] |
| Prometheus | Port-forward or NodePort | None |

**Accessing Grafana (example for all environments):**
```bash
# Port-forward to access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Default credentials: admin / prom-operator
```

### 7.5 Creating Admin Users

```bash
# Create service account
kubectl create serviceaccount admin-user -n kube-system

# Create cluster role binding
kubectl create clusterrolebinding admin-user \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:admin-user

# Get token
kubectl -n kube-system create token admin-user --duration=87600h
```

---

## 8. Deployed Components

### 8.1 Core Kubernetes Components

**All Environments:**

| Component | Version | Replicas/Nodes | Namespace |
|-----------|---------|----------------|-----------|
| kube-apiserver | v1.34.0 | Per control plane | kube-system |
| etcd | v3.5.x | Per control plane | kube-system |
| kube-controller-manager | v1.34.0 | Per control plane | kube-system |
| kube-scheduler | v1.34.0 | Per control plane | kube-system |
| kubelet | v1.34.0 | All nodes | System service |
| kube-proxy | v1.34.0 | All nodes (DaemonSet) | kube-system |
| CoreDNS | Latest | 2 replicas | kube-system |
| containerd | v1.7.28 | All nodes | System service |

**Production/Staging Only:**

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| HAProxy | API load balancing | Port 6443 → backend API servers |
| Keepalived | VIP management | VRRP protocol, priority-based |

### 8.2 Network Plugin

**Calico CNI v3.30.1:**

| Component | Replicas | Namespace | Purpose |
|-----------|----------|-----------|---------|
| Tigera Operator | 1 | tigera-operator | Calico operator |
| Calico Node | DaemonSet (all nodes) | calico-system | CNI networking |
| Calico Controllers | 1 | calico-system | CNI management |

**Network Configuration:**
- Pod CIDR: 192.168.0.0/16
- Service CIDR: 10.96.0.0/12
- Encapsulation: VXLAN (cross-subnet)
- MTU: 1450 (VXLAN overhead)
- Network policies: Enabled

### 8.3 Ingress Controller

**NGINX Ingress Controller:**

| Environment | Replicas | Namespace | NodePorts |
|-------------|----------|-----------|-----------|
| Production | 4 (one per node) | ingress-nginx | 30080 (HTTP), 30443 (HTTPS) |
| Staging | 2 (one per node) | ingress-nginx | 30080 (HTTP), 30443 (HTTPS) |
| Development | 1 | ingress-nginx | 30080 (HTTP), 30443 (HTTPS) |

**Cert-Manager:**
- Deployed in all environments
- Namespace: cert-manager
- Purpose: Automated SSL/TLS certificate management

**Access Ingress:**
```bash
# HTTP
curl http://[node-ip]:30080

# HTTPS
curl -k https://[node-ip]:30443
```

### 8.4 Storage Provisioner

**Local Path Provisioner:**
- Deployed in: kube-system namespace
- Purpose: Dynamic PV provisioning for local storage

**Storage Classes (All Environments):**
```bash
kubectl get storageclass

NAME                   PROVISIONER             RECLAIMPOLICY
fast-ssd-storage       local-path-provisioner  Delete
standard-storage       local-path-provisioner  Delete
backup-storage         local-path-provisioner  Retain        # Prod/Staging only
logs-storage           local-path-provisioner  Delete
```

### 8.5 Metrics and Autoscaling

**Metrics Server:**
- Namespace: kube-system
- Purpose: Resource metrics API for `kubectl top` and HPA
- Status: Operational

**Usage:**
```bash
kubectl top nodes
kubectl top pods -A
```

### 8.6 Package Manager

**Helm v3:**
- Installed on all servers
- Purpose: Kubernetes package manager
- Usage:
  ```bash
  helm version
  helm list -A
  ```

---

## 9. Storage Configuration

### 9.1 Storage Architecture

**Storage Directory Structure (Per Node):**

```
/mnt/k8s-storage/
├── fast-ssd/              # High-performance storage
│   ├── databases/         # Database storage (PostgreSQL, MySQL)
│   ├── cache/            # Cache storage (Redis)
│   ├── prometheus/       # Metrics storage
│   ├── grafana/          # Dashboard storage
│   └── loki/             # Log storage
├── standard/             # General purpose storage
│   ├── applications/     # Application data
│   ├── configs/          # Configuration files
│   └── temp/             # Temporary files
├── backup/               # Backup storage (Prod/Staging only)
│   ├── databases/        # Database backups
│   ├── configs/          # Config backups
│   └── volumes/          # PV backups
└── logs/                 # Log storage
    ├── applications/     # Application logs
    └── system/           # System logs
```

### 9.2 Storage Classes Details

**fast-ssd-storage:**
- Performance tier: High
- Use cases: Databases, caches, metrics
- Reclaim policy: Delete
- Volume binding: WaitForFirstConsumer
- Path: `/mnt/k8s-storage/fast-ssd/`

**standard-storage:**
- Performance tier: Standard
- Use cases: General application data
- Reclaim policy: Delete
- Volume binding: WaitForFirstConsumer
- Path: `/mnt/k8s-storage/standard/`

**backup-storage (Production/Staging only):**
- Performance tier: Standard
- Use cases: Backups, archives
- Reclaim policy: Retain (data preserved after PVC deletion)
- Volume binding: WaitForFirstConsumer
- Path: `/mnt/k8s-storage/backup/`

**logs-storage:**
- Performance tier: Standard
- Use cases: Log aggregation
- Reclaim policy: Delete
- Volume binding: WaitForFirstConsumer
- Path: `/mnt/k8s-storage/logs/`

### 9.3 Creating Persistent Volumes

**Example PV Creation:**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv
spec:
  capacity:
    storage: 50Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd-storage
  local:
    path: /mnt/k8s-storage/fast-ssd/postgres
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-cp1
```

### 9.4 Storage Monitoring

**Check storage usage:**

```bash
# On each node
df -h /mnt/k8s-storage/

# Via kubectl
kubectl get pv
kubectl get pvc --all-namespaces

# Detailed view
kubectl describe pv <pv-name>
kubectl describe pvc <pvc-name> -n <namespace>
```

### 9.5 Storage Expansion

**Adding storage to cluster:**

1. Add physical drives to servers
2. Create RAID arrays via PERC controller
3. Format and mount to appropriate path
4. Create PVs via kubectl or storage provisioner
5. Update monitoring

**Example commands:**

```bash
# Format new disk
sudo mkfs.ext4 /dev/sdX

# Mount
sudo mount /dev/sdX /mnt/k8s-storage/standard/new-volume

# Add to /etc/fstab for persistence
echo "/dev/sdX /mnt/k8s-storage/standard/new-volume ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Create PV (via kubectl apply -f)
```

---

## 10. Monitoring and Logging

### 10.1 Prometheus Stack

**Deployed Components:**

| Component | Replicas | Storage | Retention | Namespace |
|-----------|----------|---------|-----------|-----------|
| Prometheus (Prod) | 2 (HA) | 50Gi | 30 days | monitoring |
| Prometheus (Staging) | 1 | 30Gi | 7 days | monitoring |
| Prometheus (Dev) | 1 | 20Gi | 3 days | monitoring |
| Grafana | 1 | 10Gi | N/A | monitoring |
| AlertManager (Prod) | 3 (HA) | 10Gi | 30 days | monitoring |
| AlertManager (Staging/Dev) | 1 | 5Gi | 7 days | monitoring |

**Accessing Prometheus:**

```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open browser: http://localhost:9090
```

**Key Metrics Collected:**
- Node CPU, memory, disk, network utilization
- Container resource usage
- Kubernetes API server performance
- etcd cluster health and performance
- Calico network metrics
- Custom application metrics (via ServiceMonitor)

**Alert Rules (Production):**
- Node down
- High CPU/memory usage (>80%)
- Disk space low (<10%)
- etcd cluster unhealthy
- Pod crash looping
- API server errors
- Certificate expiring soon

### 10.2 Grafana Dashboards

**Access Grafana:**

```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Browser: http://localhost:3000
# Default credentials: admin / prom-operator
```

**Pre-installed Dashboards:**
1. **Kubernetes Cluster Overview**: Overall cluster health
2. **Node Exporter Full**: Detailed node metrics
3. **Kubernetes Pods**: Pod resource usage
4. **Kubernetes Deployments**: Deployment status
5. **Prometheus Stats**: Prometheus performance
6. **etcd Dashboard**: etcd cluster health
7. **Calico Network**: Network performance

**Creating Custom Dashboards:**
- Use PromQL queries against Prometheus data
- Import community dashboards from grafana.com
- Configure alerts within Grafana

### 10.3 Logging (Loki + Promtail)

**Loki Configuration:**

| Environment | Storage | Retention | Purpose |
|-------------|---------|-----------|---------|
| Production | 50Gi | 30 days | Log aggregation |
| Staging | 30Gi | 7 days | Log aggregation |
| Development | 20Gi | 3 days | Log aggregation |

**Promtail:**
- Runs on all nodes (DaemonSet)
- Collects logs from: `/var/log/pods/`, `/var/log/containers/`
- Labels: namespace, pod, container, node

**Accessing Logs:**

```bash
# Via kubectl (individual pods)
kubectl logs <pod-name> -n <namespace>
kubectl logs -f <pod-name> -n <namespace>  # Follow logs
kubectl logs <pod-name> -c <container> -n <namespace>  # Specific container

# Via Grafana Explore
# 1. Open Grafana
# 2. Navigate to Explore
# 3. Select Loki data source
# 4. Query: {namespace="default"}
# 5. Query: {app="myapp", namespace="production"}
```

**Example Loki Queries:**

```logql
# All logs from namespace
{namespace="default"}

# Logs containing "error"
{namespace="default"} |= "error"

# Logs from specific pod
{pod="myapp-abc123", namespace="default"}

# Rate of error logs
rate({namespace="default"} |= "error" [5m])
```

### 10.4 AlertManager

**Access AlertManager:**

```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Browser: http://localhost:9093
```

**Notification Channels (To Configure):**
- Email: [Configure SMTP settings]
- Slack: [Configure webhook URL]
- PagerDuty: [Configure integration key]
- Webhook: [Custom webhook endpoints]

**Configuration:**

```bash
# Edit AlertManager config
kubectl edit configmap -n monitoring alertmanager-kube-prometheus-stack-alertmanager

# Or edit secret
kubectl edit secret -n monitoring alertmanager-kube-prometheus-stack-alertmanager
```

### 10.5 Node Exporter

**Purpose:** Collects hardware and OS metrics from nodes

**Metrics:**
- CPU usage, load average
- Memory usage
- Disk I/O
- Network I/O
- Filesystem usage
- System temperature (if available)

**Deployed as:** DaemonSet (one pod per node)

**Accessing metrics:**
- Via Prometheus: Node Exporter metrics
- Via Grafana: Node Exporter Full dashboard

### 10.6 Monitoring Commands Cheat Sheet

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl top pods -A

# Component health
kubectl get componentstatuses
kubectl get --raw /healthz

# etcd health (production/staging)
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Service status on nodes
systemctl status kubelet
systemctl status containerd
systemctl status haproxy      # Prod/Staging only
systemctl status keepalived    # Prod/Staging only

# View recent events
kubectl get events -A --sort-by='.lastTimestamp' | head -20

# Check logs
journalctl -u kubelet -f
journalctl -u containerd -f
journalctl -u haproxy -f      # Prod/Staging only
journalctl -u keepalived -f    # Prod/Staging only
```

---

## 11. Backup and Disaster Recovery

### 11.1 Backup Strategy

#### Production Environment

**etcd Backups:**
- Schedule: Daily at 02:00 AM (automated via cron)
- Retention: 30 days local, [configure off-site as needed]
- Location: `/opt/kubernetes/backups/` on each control plane node
- Script: `/opt/kubernetes/etcd-backup.sh`
- Format: etcd snapshot (.db file)

**Manual etcd Backup:**

```bash
# Run backup script
sudo /opt/kubernetes/etcd-backup.sh

# Or use etcdctl directly
ETCDCTL_API=3 etcdctl snapshot save /opt/kubernetes/backups/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /opt/kubernetes/backups/etcd-snapshot-*.db \
  --write-out=table
```

**Kubernetes Configuration Backups:**

```bash
# Backup all resources
kubectl get all --all-namespaces -o yaml > /opt/kubernetes/backups/cluster-backup-$(date +%Y%m%d).yaml

# Backup specific resource types
kubectl get configmaps --all-namespaces -o yaml > /opt/kubernetes/backups/configmaps-backup.yaml
kubectl get secrets --all-namespaces -o yaml > /opt/kubernetes/backups/secrets-backup.yaml
kubectl get pv,pvc --all-namespaces -o yaml > /opt/kubernetes/backups/storage-backup.yaml

# Backup certificates
tar -czf /opt/kubernetes/backups/k8s-pki-backup-$(date +%Y%m%d).tar.gz /etc/kubernetes/pki/
```

#### Staging Environment

**etcd Backups:**
- Schedule: Daily at 02:00 AM
- Retention: 7 days local
- Location: `/opt/kubernetes/backups/`
- Script: `/opt/kubernetes/etcd-backup.sh`

#### Development Environment

**No Automated Backups** (by design)

**Manual backup if needed:**
```bash
# Create backup manually
sudo /opt/kubernetes/etcd-backup.sh

# Or export configurations
kubectl get all --all-namespaces -o yaml > dev-cluster-backup.yaml
```

### 11.2 Disaster Recovery Procedures

#### Production: Single Node Failure

**Impact:** Minimal - cluster continues operating with 3 nodes

**Automatic Recovery:**
1. Cluster automatically excludes failed node
2. VIP fails over to another node (if failed node held VIP)
3. Workloads reschedule to healthy nodes
4. etcd maintains quorum with 3/4 nodes

**Manual Node Recovery:**

```bash
# After hardware repair, on recovered node:
systemctl start kubelet
systemctl start containerd
systemctl start haproxy
systemctl start keepalived

# Verify node rejoins
kubectl get nodes

# If node doesn't rejoin, check logs
journalctl -u kubelet -f

# If necessary, reset and rejoin
kubeadm reset -f
# Then re-run join command from /opt/kubernetes/join-info/
```

#### Production: Two Node Failure

**Impact:** CRITICAL - etcd loses quorum (2/4 nodes = no majority)

**Emergency Actions:**
1. ⚠️ DO NOT REBOOT remaining nodes
2. Restore at least one failed node immediately
3. Once 3 nodes operational, verify etcd quorum
4. Then proceed to restore 4th node

**Verification:**

```bash
# Check etcd members
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Check cluster health
kubectl get nodes
kubectl get cs
```

#### Production: Complete Cluster Failure

**Recovery Steps:**

1. **Restore first control plane (k8s-cp1):**

```bash
# Stop services
systemctl stop kubelet

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
systemctl start kubelet

# Verify
kubectl get nodes
```

2. **Recover remaining nodes:**

```bash
# On each of k8s-cp2, k8s-cp3, k8s-cp4
systemctl start kubelet

# Verify all nodes join
kubectl get nodes
```

3. **Restore application data:**

```bash
# Apply backed-up resources
kubectl apply -f /opt/kubernetes/backups/cluster-backup-YYYYMMDD.yaml

# Verify
kubectl get pods -A
```

#### Staging: Single Node Failure

**Impact:** CRITICAL - cluster stops functioning (etcd loses quorum)

**Recovery:**
- Immediately restore failed node
- Both nodes must be operational for cluster to function
- See production single node recovery for steps

#### Staging: Complete Failure

- Follow production complete cluster failure procedure
- Adjust for 2-node topology

#### Development: Complete Failure

**Recovery:**

1. **Reset and reinitialize:**

```bash
# Reset cluster
kubeadm reset -f

# Clean up
rm -rf /etc/cni/net.d
rm -rf /var/lib/etcd
rm -rf /root/.kube

# Restart containerd
systemctl restart containerd

# Re-run initialization script
cd /path/to/development/
sudo ./03-ha-cluster-init.sh
```

2. **Restore applications:**

```bash
# If you have backup
kubectl apply -f dev-cluster-backup.yaml
```

### 11.3 Backup Verification

**Monthly Backup Test (Production/Staging):**

```bash
# Test etcd backup restore on separate test node
ETCDCTL_API=3 etcdctl snapshot restore /opt/kubernetes/backups/etcd-snapshot-LATEST.db \
  --data-dir=/tmp/test-restore

# Verify integrity
ls -lh /tmp/test-restore

# Clean up
rm -rf /tmp/test-restore
```

**Quarterly DR Drill (Production):**
1. Schedule maintenance window
2. Simulate node failure
3. Test recovery procedures
4. Document lessons learned
5. Update DR procedures

---

## 12. Operational Procedures

### 12.1 Daily Health Checks

**Morning Checklist (5 minutes per environment):**

```bash
# 1. Check all nodes are Ready
kubectl get nodes

# 2. Check for failed/crashlooping pods
kubectl get pods -A | grep -v Running | grep -v Completed

# 3. Check resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -20

# 4. Check VIP assignment (Production/Staging)
ip addr show | grep "10.255.254.100"  # Production
ip addr show | grep "10.255.253.100"  # Staging

# 5. Check system services
systemctl status kubelet
systemctl status containerd
systemctl status haproxy      # Prod/Staging only
systemctl status keepalived    # Prod/Staging only

# 6. Check recent errors
journalctl -u kubelet --since "1 hour ago" | grep -i error
kubectl get events -A --sort-by='.lastTimestamp' | head -20

# 7. Verify backups (Production/Staging)
ls -lh /opt/kubernetes/backups/ | tail -5
```

### 12.2 Weekly Operations

**System Updates (Schedule maintenance window):**

```bash
# Update packages
apt update
apt list --upgradable

# Apply updates (during maintenance)
apt upgrade -y

# Restart services if needed
systemctl daemon-reload
systemctl restart containerd
systemctl restart kubelet
```

**Backup Verification:**

```bash
# Check backup age and size
find /opt/kubernetes/backups/ -name "etcd-snapshot-*.db" -mtime -7 -ls

# Check disk space
df -h /opt/kubernetes/backups/
df -h /mnt/k8s-storage/
```

**Certificate Expiry Check:**

```bash
# Check certificate expiration
kubeadm certs check-expiration

# If < 30 days, renew during maintenance window
# kubeadm certs renew all
```

**Resource Review:**

```bash
# Storage usage
kubectl get pv --sort-by=.spec.capacity.storage

# Pod resource consumption
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu

# Node resource allocation
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

### 12.3 Monthly Operations

**Rolling Node Maintenance:**

```bash
# Drain node for maintenance (ONE AT A TIME!)
kubectl drain k8s-cp2 --ignore-daemonsets --delete-emptydir-data

# Perform maintenance
apt update && apt upgrade -y
systemctl reboot

# After reboot, uncordon node
kubectl uncordon k8s-cp2

# Wait for pods to reschedule and stabilize before next node
kubectl get pods -A -o wide

# Repeat for other nodes sequentially
```

**Security Audit:**

```bash
# Review RBAC
kubectl get clusterrolebindings
kubectl get rolebindings -A

# Check for pods running as root
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.securityContext.runAsUser==0 or .spec.containers[].securityContext.runAsUser==0) | "\(.metadata.namespace)/\(.metadata.name)"'

# Review network policies
kubectl get networkpolicies -A
```

**Capacity Planning:**

```bash
# Generate usage reports
kubectl top nodes > /tmp/node-usage-$(date +%Y%m%d).txt
kubectl top pods -A > /tmp/pod-usage-$(date +%Y%m%d).txt
du -sh /mnt/k8s-storage/* > /tmp/storage-usage-$(date +%Y%m%d).txt

# Review trends in Grafana
```

### 12.4 Adding Nodes to Cluster

**Adding Worker Node (Any Environment):**

```bash
# 1. Prepare new server (run server preparation script)
cd /path/to/environment/
sudo ./01-server-preparation.sh

# 2. On primary control plane, generate join token
kubeadm token create --print-join-command

# 3. On new node, run join command
kubeadm join <vip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///var/run/containerd/containerd.sock

# 4. Verify node joins
kubectl get nodes

# 5. Label node appropriately
kubectl label node <new-node> node-role.kubernetes.io/worker=worker
```

**Adding Control Plane Node (Production/Staging):**

```bash
# 1. Prepare new server

# 2. Generate control plane join command with certificate key
kubeadm token create --print-join-command --certificate-key \
  $(kubeadm init phase upload-certs --upload-certs | tail -n 1)

# 3. On new node, run control plane join command
kubeadm join <vip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <cert-key> \
  --cri-socket unix:///var/run/containerd/containerd.sock

# 4. Verify
kubectl get nodes
```

### 12.5 Removing Nodes from Cluster

```bash
# 1. Cordon node (prevent new pods)
kubectl cordon <node-name>

# 2. Drain node (evict existing pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# 3. Delete node from cluster
kubectl delete node <node-name>

# 4. On the node being removed
kubeadm reset -f
systemctl stop kubelet
systemctl stop containerd

# 5. If removing etcd member (control plane)
# First, get member ID
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Remove member
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member remove <member-id>
```

### 12.6 Kubernetes Version Upgrade

**Pre-Upgrade Checklist:**
- [ ] Review release notes for target version
- [ ] Test upgrade in development environment first
- [ ] Then test in staging environment
- [ ] Backup all clusters: `sudo /opt/kubernetes/etcd-backup.sh`
- [ ] Schedule maintenance window (2-4 hours)
- [ ] Notify stakeholders

**Upgrade Procedure (Rolling):**

```bash
# 1. On first control plane node (e.g., k8s-cp1)

# Upgrade kubeadm
apt-mark unhold kubeadm
apt update
apt-cache madison kubeadm  # Find target version
apt install kubeadm=1.XX.X-00
apt-mark hold kubeadm

# Verify upgrade plan
kubeadm upgrade plan

# Apply upgrade
kubeadm upgrade apply v1.XX.X

# Upgrade kubelet and kubectl
apt-mark unhold kubelet kubectl
apt install kubelet=1.XX.X-00 kubectl=1.XX.X-00
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# 2. On each additional control plane node (cp2, cp3, cp4, stg2)

# Drain node
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

# Wait for node to become Ready before proceeding to next

# 3. Verify cluster after all upgrades
kubectl get nodes
kubectl version
kubectl get pods -A
```

---

## 13. Troubleshooting Guide

### 13.1 Common Issues

#### Issue: Node Not Ready

**Symptoms:**
```bash
kubectl get nodes
# Shows node status as NotReady
```

**Diagnosis:**
```bash
# Check node details
kubectl describe node <node-name>

# Check kubelet
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager

# Check containerd
systemctl status containerd
journalctl -u containerd -n 100 --no-pager

# Check network
ping <other-node-ip>
```

**Solutions:**
```bash
# Restart kubelet
systemctl restart kubelet

# Restart containerd
systemctl restart containerd

# Check CNI
kubectl get pods -n calico-system

# Reset node (last resort)
kubeadm reset
# Then rejoin cluster
```

#### Issue: Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -A
# Shows pods in Pending state
```

**Diagnosis:**
```bash
# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# Check PVC status (if using storage)
kubectl get pvc -n <namespace>

# Check for node taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

**Solutions:**
```bash
# If insufficient resources
kubectl scale deployment <name> --replicas=<lower-number>

# If PVC issue
kubectl get pv
kubectl describe pvc <pvc-name>

# If taint issue (dev environment should have no taints)
kubectl taint nodes <node-name> <taint-key>-  # Remove taint
```

#### Issue: VIP Not Assigned (Production/Staging)

**Symptoms:**
```bash
ip addr show | grep "10.255.254.100"
# No output - VIP not on any node
```

**Diagnosis:**
```bash
# Check Keepalived on all nodes
systemctl status keepalived
journalctl -u keepalived -n 50 --no-pager

# Check VRRP traffic
tcpdump -i eno1 vrrp -n -c 10

# Check for IP conflicts
arping -I eno1 10.255.254.100
```

**Solutions:**
```bash
# Restart Keepalived on all nodes
systemctl restart keepalived

# Check config
cat /etc/keepalived/keepalived.conf

# Ensure firewall allows VRRP (protocol 112)
iptables -L -n | grep 112
```

#### Issue: etcd Cluster Unhealthy

**Symptoms:**
```bash
kubectl get cs
# Shows etcd as unhealthy
```

**Diagnosis:**
```bash
# Check etcd pods
kubectl get pods -n kube-system | grep etcd

# Check etcd health
kubectl exec -n kube-system etcd-k8s-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check etcd logs
kubectl logs -n kube-system etcd-<node-name> --tail=100

# Check disk space (etcd sensitive to I/O)
df -h /var/lib/etcd
```

**Solutions:**
```bash
# Restart etcd pod (static pod)
mv /etc/kubernetes/manifests/etcd.yaml /tmp/
sleep 30
mv /tmp/etcd.yaml /etc/kubernetes/manifests/

# If disk space low, clean up
sudo journalctl --vacuum-time=7d

# If member corrupt (CAUTION: only with healthy quorum)
# Remove and re-add member
```

#### Issue: DNS Not Working

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
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# Check DNS service
kubectl get svc -n kube-system kube-dns

# Test from node
nslookup kubernetes.default.svc.cluster.local 10.96.0.10
```

**Solutions:**
```bash
# Restart CoreDNS
kubectl rollout restart deployment -n kube-system coredns

# Check ConfigMap
kubectl get configmap -n kube-system coredns -o yaml

# Check pod's resolv.conf
kubectl run test --image=busybox --rm -it -- cat /etc/resolv.conf
```

#### Issue: High CPU/Memory Usage

**Symptoms:**
```bash
kubectl top nodes
# Shows >80% resource usage
```

**Diagnosis:**
```bash
# Identify resource-hungry pods
kubectl top pods -A --sort-by=memory | head -20
kubectl top pods -A --sort-by=cpu | head -20

# Check for crashlooping pods
kubectl get pods -A | grep -i crash

# On node, check system processes
ssh <node> top
```

**Solutions:**
```bash
# Scale down deployments
kubectl scale deployment <name> --replicas=<number> -n <namespace>

# Set resource limits (if not set)
kubectl set resources deployment <name> \
  --limits=cpu=500m,memory=512Mi \
  --requests=cpu=100m,memory=128Mi

# Restart problematic pods
kubectl delete pod <pod-name> -n <namespace>

# Check for memory leaks
kubectl rollout restart deployment <name> -n <namespace>
```

#### Issue: Ingress Not Working

**Symptoms:**
```bash
curl http://<node-ip>:30080
# Connection refused or 404
```

**Diagnosis:**
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resources
kubectl get ingress -A

# Check service
kubectl get svc -n ingress-nginx

# Check logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

**Solutions:**
```bash
# Restart ingress controller
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Re-create ingress
kubectl delete ingress <ingress-name> -n <namespace>
kubectl apply -f <ingress-file>.yaml

# Check ingress class
kubectl get ingressclass
```

### 13.2 Diagnostic Commands Reference

**Quick Health Check:**
```bash
# Cluster overview
kubectl cluster-info
kubectl version
kubectl get nodes
kubectl get pods -A

# Component status
kubectl get componentstatuses
kubectl get --raw /healthz

# Resource usage
kubectl top nodes
kubectl top pods -A

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | head -30

# etcd health
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

**Network Debugging:**
```bash
# Deploy debug pod
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash

# Inside pod:
nslookup kubernetes.default
curl http://<service-name>.<namespace>.svc.cluster.local
ping <pod-ip>

# Test DNS
kubectl run test-dns --image=busybox:1.28 --rm -it -- nslookup kubernetes.default
```

**Storage Debugging:**
```bash
# Check PVs and PVCs
kubectl get pv
kubectl get pvc -A
kubectl describe pv <pv-name>
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage usage on nodes
df -h /mnt/k8s-storage/
du -sh /mnt/k8s-storage/*
```

---

## 14. Security Recommendations

### 14.1 Immediate Actions (Week 1)

**Change Default Credentials:**
- [ ] Change root passwords on all servers
- [ ] Change iDRAC passwords
- [ ] Change Grafana admin password
- [ ] Rotate SSH keys if needed

**Enable RBAC:**
```bash
# Create service accounts with appropriate permissions
kubectl create serviceaccount <app-name> -n <namespace>

# Create roles
kubectl create role <role-name> --verb=get,list,watch --resource=pods,services

# Bind roles
kubectl create rolebinding <binding-name> \
  --role=<role-name> \
  --serviceaccount=<namespace>:<sa-name> \
  -n <namespace>
```

**Review Access:**
- [ ] Document who has SSH access
- [ ] Document who has kubectl access
- [ ] Document who has iDRAC access
- [ ] Implement least privilege principle

### 14.2 Security Hardening (Month 1)

**Pod Security Standards:**
```bash
# Enable Pod Security Standards per namespace
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted
```

**Network Policies:**
```yaml
# Example: Default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

**Enable Audit Logging:**
```bash
# Edit API server manifest
vi /etc/kubernetes/manifests/kube-apiserver.yaml

# Add audit policy and log configuration
# --audit-policy-file=/etc/kubernetes/audit-policy.yaml
# --audit-log-path=/var/log/kubernetes/audit.log
# --audit-log-maxage=30
# --audit-log-maxbackup=10
# --audit-log-maxsize=100
```

**Secrets Management:**
- Use Kubernetes Secrets (encrypted at rest)
- Consider external secret management (Vault, Sealed Secrets)
- Never commit secrets to git
- Rotate secrets regularly

**TLS Certificates:**
```bash
# Configure cert-manager with Let's Encrypt
# Or use internal CA

# Check certificate expiration
kubeadm certs check-expiration

# Set reminders to renew before expiry
```

### 14.3 Ongoing Security

**Regular Updates:**
- Keep Kubernetes updated (test in dev → staging → production)
- Update containerd and OS packages
- Monitor CVE announcements

**Security Scanning:**
- Implement image scanning (Trivy, Clair)
- Scan for vulnerabilities regularly
- Implement admission controllers to prevent insecure deployments

**Access Monitoring:**
- Review audit logs regularly
- Monitor for unauthorized access attempts
- Set up alerts for suspicious activity

**Backup Security:**
- Encrypt backups
- Store backups securely off-site
- Test restore procedures regularly

---

## 15. Next Steps

### 15.1 Immediate Tasks (Day 1-3)

**Access Configuration:**
- [ ] Distribute SSH keys to team members
- [ ] Create kubeconfig files for team members
- [ ] Configure RBAC for team members
- [ ] Set up VPN access (if needed)

**Monitoring Setup:**
- [ ] Configure AlertManager notification channels (email, Slack, PagerDuty)
- [ ] Set up custom Grafana dashboards for applications
- [ ] Configure meaningful alerts

**Documentation:**
- [ ] Fill in placeholder values in this document:
  - Service tags
  - iDRAC IPs
  - Passwords/credentials locations
  - MAC addresses
- [ ] Create runbooks for common tasks
- [ ] Document application deployment procedures

**Testing:**
- [ ] Deploy test application to development
- [ ] Test VIP failover (production/staging)
- [ ] Verify backups are running
- [ ] Test disaster recovery in development

### 15.2 Short Term (Week 1-2)

**Application Deployment:**
- [ ] Deploy applications to development environment
- [ ] Test thoroughly in development
- [ ] Promote to staging for validation
- [ ] Deploy to production

**CI/CD Setup:**
- [ ] Set up CI/CD pipelines (GitLab CI, GitHub Actions, Jenkins)
- [ ] Implement GitOps workflow (Flux, ArgoCD)
- [ ] Automate deployments

**Network Configuration:**
- [ ] Configure ingress for applications with proper DNS
- [ ] Set up TLS certificates
- [ ] Implement network policies
- [ ] Configure resource quotas per namespace

**Storage Management:**
- [ ] Create PVs for applications
- [ ] Set up backup strategy for application data
- [ ] Implement storage monitoring and alerts

### 15.3 Medium Term (Month 1)

**Security Hardening:**
- [ ] Implement Pod Security Standards
- [ ] Configure comprehensive RBAC policies
- [ ] Enable audit logging
- [ ] Set up vulnerability scanning
- [ ] Implement secret management solution

**Observability:**
- [ ] Create custom Grafana dashboards
- [ ] Configure comprehensive alerting
- [ ] Set up log aggregation workflows
- [ ] Implement distributed tracing (Jaeger, Tempo)

**Disaster Recovery:**
- [ ] Document detailed DR procedures
- [ ] Test failover scenarios
- [ ] Validate backup/restore procedures
- [ ] Conduct DR drills

**Optimization:**
- [ ] Analyze resource utilization
- [ ] Implement horizontal pod autoscaling (HPA)
- [ ] Configure vertical pod autoscaling (VPA)
- [ ] Tune resource requests/limits

### 15.4 Long Term (Ongoing)

**Scaling:**
- [ ] Add more nodes if needed
- [ ] Implement cluster autoscaling
- [ ] Optimize for cost and performance

**Upgrades:**
- [ ] Plan regular Kubernetes version upgrades
- [ ] Test upgrades in dev/staging first
- [ ] Keep all components up to date

**Advanced Features:**
- [ ] Consider service mesh (Istio, Linkerd) if needed
- [ ] Implement advanced networking (multiple networks, SR-IOV)
- [ ] Set up multi-cluster management (if expanding)

**Training:**
- [ ] Team members complete Kubernetes training
  - CKA (Certified Kubernetes Administrator)
  - CKAD (Certified Kubernetes Application Developer)
- [ ] Dell hardware management training
- [ ] Disaster recovery training

---

## Appendix A: Quick Reference

### Environment Summary Table

| Aspect | Production | Staging | Development |
|--------|------------|---------|-------------|
| **Servers** | 4x R740 | 2x R740 | 1x R740 |
| **Network** | 10.255.254.0/24 | 10.255.253.0/24 | 10.255.252.0/24 |
| **VIP** | 10.255.254.100 | 10.255.253.100 | None |
| **Gateway** | 10.255.254.1 | 10.255.253.1 | 10.255.252.1 |
| **Node IPs** | .10, .11, .12, .13 | .10, .11 | .10 |
| **HA** | Full (4-node) | Limited (2-node) | None |
| **Fault Tolerance** | 1 node | 0 nodes | 0 nodes |
| **etcd Quorum** | 3/4 | 2/2 | 1/1 |
| **Backup Retention** | 30 days | 7 days | None (manual) |
| **Log Retention** | 30 days | 7 days | 3 days |
| **Monitoring Retention** | 30 days | 7 days | 3 days |

### Access Endpoints

**Production:**
```
SSH:          ssh root@10.255.254.{10,11,12,13}
API (VIP):    https://10.255.254.100:6443
Ingress HTTP: http://10.255.254.{10,11,12,13}:30080
Ingress HTTPS:https://10.255.254.{10,11,12,13}:30443
HAProxy:      http://10.255.254.10:8404/stats
```

**Staging:**
```
SSH:          ssh root@10.255.253.{10,11}
API (VIP):    https://10.255.253.100:6443
Ingress HTTP: http://10.255.253.{10,11}:30080
Ingress HTTPS:https://10.255.253.{10,11}:30443
HAProxy:      http://10.255.253.10:8404/stats
```

**Development:**
```
SSH:          ssh root@10.255.252.10
API:          https://10.255.252.10:6443
Ingress HTTP: http://10.255.252.10:30080
Ingress HTTPS:https://10.255.252.10:30443
```

### Essential Commands

**Health Checks:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl top pods -A
kubectl get events -A --sort-by='.lastTimestamp' | head -20
```

**Service Status:**
```bash
systemctl status kubelet containerd haproxy keepalived
journalctl -u kubelet -f
journalctl -u containerd -f
```

**VIP Check (Prod/Staging):**
```bash
ip addr show | grep "10.255.254.100"  # Production
ip addr show | grep "10.255.253.100"  # Staging
```

**etcd Health:**
```bash
kubectl exec -n kube-system etcd-<node> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

**Backup:**
```bash
# Manual backup
sudo /opt/kubernetes/etcd-backup.sh

# Check backups
ls -lh /opt/kubernetes/backups/
```

### Important File Locations

```
Kubernetes Config:       /etc/kubernetes/
Certificates:            /etc/kubernetes/pki/
etcd Data:              /var/lib/etcd/
Containerd Config:       /etc/containerd/config.toml
HAProxy Config:          /etc/haproxy/haproxy.cfg
Keepalived Config:       /etc/keepalived/keepalived.conf
Storage:                 /mnt/k8s-storage/
Backups:                 /opt/kubernetes/backups/
Logs:                   /var/log/kubernetes/
```

---

## Appendix B: Support and Escalation

### Vendor Support

**Dell Hardware:**
- Website: https://www.dell.com/support
- Phone: [Region-specific phone number]
- Service Tags: [Listed in Section 3.3]
- ProSupport: [Check warranty status]

**Kubernetes:**
- Documentation: https://kubernetes.io/docs/
- GitHub: https://github.com/kubernetes/kubernetes
- Slack: https://slack.k8s.io/

**Calico:**
- Documentation: https://docs.tigera.io/calico/
- Support: [Community or commercial]

### Internal Support Structure

| Level | Contact | Scope | Response Time |
|-------|---------|-------|---------------|
| L1 | [Help Desk] | General issues | 4 hours |
| L2 | [DevOps Team] | Application/deployment issues | 2 hours |
| L3 | [Infrastructure Team] | Cluster/hardware issues | 1 hour (critical) |
| L4 | [Architecture Team] | Design/major changes | 1 business day |

### Communication Channels

- **Incident Management:** [Ticket system URL]
- **Team Chat:** [Slack/Teams channel]
- **On-Call:** [PagerDuty/Opsgenie]
- **Documentation:** [Wiki/Confluence URL]

### SLA and Response Times

| Severity | Description | Response | Resolution |
|----------|-------------|----------|------------|
| **P1** | Cluster down, data loss | 15 min | 4 hours |
| **P2** | Degraded service, node down | 1 hour | 8 hours |
| **P3** | Minor issues | 4 hours | 2 days |
| **P4** | Questions, requests | 1 day | Best effort |

---

## Appendix C: Handover Checklist

### Pre-Handover Verification

**Production:**
- [x] All 4 servers operational
- [x] Kubernetes cluster healthy (4/4 nodes Ready)
- [x] etcd cluster healthy (4/4 members)
- [x] VIP functional and failing over correctly
- [x] Monitoring stack operational
- [x] Ingress controller deployed and tested
- [x] Storage configured
- [x] Backups configured and tested
- [x] Network redundancy verified
- [x] Cluster validation passed

**Staging:**
- [x] Both servers operational
- [x] Kubernetes cluster healthy (2/2 nodes Ready)
- [x] etcd cluster healthy (2/2 members)
- [x] VIP functional and failing over correctly
- [x] Monitoring stack operational
- [x] Ingress controller deployed
- [x] Storage configured
- [x] Backups configured
- [x] Cluster validation passed

**Development:**
- [x] Server operational
- [x] Kubernetes cluster healthy (1/1 node Ready)
- [x] Monitoring stack operational
- [x] Ingress controller deployed
- [x] Storage configured
- [x] Cluster validation passed

### Handover Tasks

**Week 1:**
- [ ] Team has SSH access to all servers
- [ ] Team has kubectl access to all environments
- [ ] Team has iDRAC access
- [ ] Team completed walkthrough of infrastructure
- [ ] Credentials documented and secured
- [ ] Emergency procedures reviewed

**Month 1:**
- [ ] Team comfortable with daily operations
- [ ] First maintenance window completed independently
- [ ] Backup/restore tested
- [ ] Monitoring alerts configured
- [ ] Applications deployed successfully

### Sign-Off

**Infrastructure Team:**
- Name: ___________________________________
- Signature: ___________________________________
- Date: ___________________________________

**Receiving DevOps Team:**
- Name: ___________________________________
- Signature: ___________________________________
- Date: ___________________________________

**Acceptance Criteria:**
- [ ] All environments operational and tested
- [ ] Documentation reviewed and accepted
- [ ] Access verified for all team members
- [ ] Training completed
- [ ] Support structure established
- [ ] Backup and DR procedures understood

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | October 2025 | [Your Name] | Initial multi-environment handover documentation |

---

**END OF DOCUMENT**

---

**CONFIDENTIALITY NOTICE:**

This document contains sensitive infrastructure information including network topology, access credentials, and operational procedures. It should be:

- Stored securely with restricted access
- Distributed only to authorized personnel
- Not committed to public repositories
- Updated regularly as infrastructure evolves
- Reviewed quarterly for accuracy

For questions or clarifications, contact: [Infrastructure Team Contact]
