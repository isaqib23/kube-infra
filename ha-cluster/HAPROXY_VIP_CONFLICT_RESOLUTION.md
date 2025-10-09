# HAProxy and VIP Conflict Resolution

## Issue Overview

During HA Kubernetes cluster initialization on k8s-cp1, HAProxy fails to start with the error:

```
[ALERT] Binding for frontend kubernetes-api: cannot bind socket (Address already in use) for [10.255.254.100:6443]
```

## Root Cause

**kube-apiserver is already listening on `*:6443`** (all network interfaces), which includes:
- localhost (127.0.0.1:6443)
- Server IP (10.255.254.10:6443)
- **VIP (10.255.254.100:6443)** ← This causes the conflict

When HAProxy tries to also bind to VIP:6443, it fails because kube-apiserver is already using that address.

## Why This Happens

1. **Kubernetes API Server** binds to all interfaces (`0.0.0.0:6443`) by default
2. **Keepalived** assigns the VIP (10.255.254.100) to k8s-cp1 (MASTER node)
3. Since kube-apiserver is listening on `*:6443`, it automatically listens on the VIP too
4. **HAProxy** then tries to bind to the same VIP:6443 → **CONFLICT**

## Current State Verification

```bash
# Check what's listening on port 6443
sudo netstat -tlnp | grep :6443
# Output: kube-apiserver is listening on *:6443

# Check VIP assignment
ip addr show | grep 10.255.254.100
# Output: VIP is assigned to this server

# Test API accessibility
curl -k https://10.255.254.100:6443/healthz
# Output: ok ✓ (API is already accessible via VIP)
```

**Conclusion:** The Kubernetes API is already accessible via VIP without HAProxy!

## Solution: Stop HAProxy on k8s-cp1 (Temporary)

### Why Stop HAProxy?

1. ✅ **API is already accessible via VIP** through kube-apiserver directly
2. ✅ **Keepalived is managing VIP failover** correctly
3. ✅ **No load balancing needed yet** - only 1 control plane is running
4. ✅ **Prevents constant restart loop** of HAProxy service
5. ✅ **Allows deployment to continue** without errors

### Implementation

```bash
# Stop HAProxy service
sudo systemctl stop haproxy

# Disable HAProxy from auto-starting (until we reconfigure it)
sudo systemctl disable haproxy

# Verify API still works
kubectl get nodes
kubectl cluster-info
curl -k https://10.255.254.100:6443/healthz
```

### What This Means

- **VIP 10.255.254.100:6443** → Routes directly to kube-apiserver on k8s-cp1
- **Keepalived** handles VIP failover (if k8s-cp1 fails, VIP moves to k8s-cp2)
- **No HAProxy needed** for single control plane
- **Deployment can continue** to join other control planes

## After Joining Other Control Planes

Once k8s-cp2, k8s-cp3, and k8s-cp4 join the cluster, we need to reconfigure HAProxy for proper load balancing.

### Step 1: Verify All Control Planes Are Joined

```bash
# Check all nodes are Ready
kubectl get nodes -o wide

# Should show:
# k8s-cp1   Ready    control-plane   ...
# k8s-cp2   Ready    control-plane   ...
# k8s-cp3   Ready    control-plane   ...
# k8s-cp4   Ready    control-plane   ...
```

### Step 2: Reconfigure HAProxy on All Nodes

**Option A: Use HAProxy for Load Balancing (Recommended for production)**

Configure HAProxy to bind to a different port or only when VIP is not on the local server.

**Option B: Let kube-apiserver Handle VIP Directly (Simpler)**

Keep HAProxy disabled and let kube-apiserver handle the VIP. Kubernetes API server can handle the load and Keepalived manages failover.

### Step 3: Run Post-Join HAProxy Configuration Script

Create and run this script after all nodes join:

```bash
#!/bin/bash
# Run on ALL nodes after cluster is fully formed

# File: ha-cluster/reconfigure-haproxy-post-join.sh

CURRENT_NODE=$(hostname)
VIP="10.255.254.100"

# Check if VIP is assigned to this node
if ip addr show | grep -q "$VIP"; then
    echo "VIP is on this node, keeping HAProxy disabled"
    systemctl stop haproxy
    systemctl disable haproxy
else
    echo "VIP is NOT on this node, configuring HAProxy"

    # HAProxy can bind to VIP:6443 on backup nodes without conflict
    systemctl enable haproxy
    systemctl restart haproxy
fi
```

## Architecture Explanation

### Single Control Plane (Current State)
```
Client → VIP:6443 → kube-apiserver (k8s-cp1)
         ↑
    Keepalived manages VIP
```

### Multiple Control Planes (After Join)
```
Client → VIP:6443 → kube-apiserver (k8s-cp1, cp2, cp3, cp4)
         ↑
    Keepalived manages VIP failover between nodes
    Each node's kube-apiserver handles requests when VIP is assigned
```

**OR with HAProxy (Alternative)**
```
Client → VIP:6443 → HAProxy → kube-apiserver (cp1, cp2, cp3, cp4)
         ↑              ↑
    Keepalived     Load balances across
    manages VIP    all API servers
```

## Decision Matrix

| Scenario | Use HAProxy? | Why |
|----------|--------------|-----|
| 1 control plane | ❌ No | kube-apiserver handles VIP directly |
| 4 control planes, VIP on node | ❌ No | Conflict with kube-apiserver |
| 4 control planes, VIP NOT on node | ✅ Maybe | Can load balance, but not required |
| Custom port for HAProxy | ✅ Yes | Avoids conflict, provides monitoring |

## Recommended Approach

**For this deployment:**

1. ✅ **Now:** Stop HAProxy on k8s-cp1, let kube-apiserver handle VIP
2. ✅ **After join:** Keep HAProxy disabled on whichever node has VIP
3. ✅ **Optional:** Enable HAProxy on backup nodes for monitoring/stats
4. ✅ **Production:** Consider external load balancer or keepalived + kube-apiserver is sufficient

## Commands Reference

### Check HAProxy Status
```bash
sudo systemctl status haproxy
```

### Stop HAProxy
```bash
sudo systemctl stop haproxy
sudo systemctl disable haproxy
```

### Start HAProxy (after reconfiguration)
```bash
sudo systemctl enable haproxy
sudo systemctl start haproxy
```

### Check API Accessibility
```bash
# Via localhost
curl -k https://127.0.0.1:6443/healthz

# Via server IP
curl -k https://10.255.254.10:6443/healthz

# Via VIP
curl -k https://10.255.254.100:6443/healthz
```

### Check VIP Assignment
```bash
ip addr show | grep 10.255.254.100
```

### Check What's Listening on Port 6443
```bash
sudo netstat -tlnp | grep :6443
sudo ss -tlnp | grep :6443
```

## Troubleshooting

### HAProxy Won't Start
- **Check:** Is VIP assigned to this node?
- **Check:** Is kube-apiserver already on port 6443?
- **Solution:** Stop HAProxy if on VIP node

### API Not Accessible
- **Check:** Is kube-apiserver running?
- **Check:** Is VIP assigned to any node?
- **Solution:** Check keepalived and kube-apiserver status

### VIP Not Failing Over
- **Check:** Is keepalived running on all nodes?
- **Check:** Are priorities configured correctly?
- **Solution:** Review keepalived configuration

## Summary

- **Issue:** HAProxy can't bind to VIP:6443 because kube-apiserver is already using it
- **Solution:** Stop HAProxy on k8s-cp1 (the VIP master node)
- **Impact:** None - API is still accessible via VIP through kube-apiserver
- **Next Steps:** Join other control planes, then decide on HAProxy strategy
- **Recommendation:** Keep it simple - use kube-apiserver + keepalived without HAProxy

---

**Document Version:** 1.0
**Created:** October 2025
**Status:** Active Issue Resolution
**Applies To:** k8s-cp1 during initial cluster setup
