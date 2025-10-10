# Permanent Swap Disable for Kubernetes Cluster

## Problem
After server reboots, Ubuntu 24.04 may re-enable swap (typically `/swap.img`), which causes kubelet to fail with:
```
E1010 06:30:25.717717 4415 run.go:72] "command failed" err="failed to run Kubelet: running with swap on is not supported"
```

This prevents the Kubernetes cluster from starting properly.

## Solution
This directory contains files to permanently disable swap across all nodes, ensuring it stays disabled after reboots.

## Files

1. **disable-swap-permanent.sh** - Script that disables swap permanently
   - Disables swap immediately (`swapoff -a`)
   - Removes `/swap.img` file
   - Comments out swap in `/etc/fstab`
   - Masks systemd swap services
   - Disables cloud-init swap creation

2. **disable-swap-kubernetes.service** - Systemd service that runs on boot
   - Runs before kubelet.service starts
   - Ensures swap is disabled before Kubernetes starts
   - Runs automatically on every boot

3. **install-swap-disable-all-nodes.sh** - Automated installer
   - Copies files to all 4 nodes
   - Installs and enables the service
   - Verifies installation

## Installation Methods

### Method 1: Automated (Recommended)

Copy all files to k8s-cp1, then run the installer:

```bash
# On your local machine, copy files to k8s-cp1
scp disable-swap-permanent.sh disable-swap-kubernetes.service install-swap-disable-all-nodes.sh rao@10.255.254.10:~/

# SSH to k8s-cp1
ssh rao@10.255.254.10

# Move files to ha-cluster directory (optional)
sudo mv ~/*.sh ~/*.service /opt/ha-cluster/ 2>/dev/null || true

# Run the automated installer (requires SSH access to all nodes)
sudo bash install-swap-disable-all-nodes.sh
```

### Method 2: Manual Installation

If SSH keys are not set up between nodes, install manually on each node:

```bash
# On each node (k8s-cp1, k8s-cp2, k8s-cp3, k8s-cp4):

# Copy the script to proper location
sudo cp disable-swap-permanent.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/disable-swap-permanent.sh

# Run the script to disable swap
sudo /usr/local/bin/disable-swap-permanent.sh

# Install the systemd service
sudo cp disable-swap-kubernetes.service /etc/systemd/system/

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable disable-swap-kubernetes.service
sudo systemctl start disable-swap-kubernetes.service

# Verify installation
sudo systemctl status disable-swap-kubernetes.service
sudo swapon --show  # Should show nothing (no swap)
```

## Verification

After installation, verify on each node:

```bash
# Check if swap is disabled
sudo swapon --show
# Output should be empty or "No swap enabled"

# Check if service is enabled
sudo systemctl is-enabled disable-swap-kubernetes.service
# Output: enabled

# Check service status
sudo systemctl status disable-swap-kubernetes.service
# Output: active (exited)

# Verify fstab
grep swap /etc/fstab
# All swap lines should be commented out with #

# Verify systemd swap is masked
systemctl status swap.target
# Output: masked
```

## Testing the Fix

To test that swap stays disabled after reboot:

```bash
# Reboot one node at a time (test on k8s-cp2 first, not cp1)
sudo reboot

# After the node comes back up, verify:
sudo swapon --show  # Should show nothing
sudo systemctl status kubelet  # Should be active (running)
kubectl get nodes  # Node should show Ready
```

## What This Fix Does

1. **Immediate**: Disables swap right now
2. **Boot-time**: Systemd service runs before kubelet on every boot
3. **fstab**: Comments out swap entries to prevent mount
4. **systemd**: Masks swap.target and swapfile.swap services
5. **cloud-init**: Disables swap creation by cloud-init
6. **Physical**: Removes the /swap.img file completely

## Troubleshooting

If kubelet still fails after installation:

```bash
# Check if swap is actually disabled
sudo swapon --show

# If swap is still on, manually disable
sudo swapoff -a

# Restart kubelet
sudo systemctl restart kubelet

# Check logs
sudo journalctl -u kubelet -n 50

# Verify service ran on boot
sudo journalctl -u disable-swap-kubernetes.service
```

## Notes

- This fix is required on **all 4 nodes**: k8s-cp1, k8s-cp2, k8s-cp3, k8s-cp4
- The service runs **before** kubelet starts, ensuring swap is always off
- Safe to run multiple times (idempotent)
- Does not affect other system functions
- Required for Kubernetes production deployments

## Integration with Deployment Scripts

This fix should be integrated into the `01-server-preparation.sh` script to prevent the issue from occurring during initial cluster setup.

Consider adding to line 428 of `01-server-preparation.sh`:

```bash
# Install permanent swap disable mechanism
install_permanent_swap_disable() {
    log "Installing permanent swap disable mechanism..."

    # Install the script and service
    cp "$SCRIPT_DIR/disable-swap-permanent.sh" /usr/local/bin/
    chmod +x /usr/local/bin/disable-swap-permanent.sh

    cp "$SCRIPT_DIR/disable-swap-kubernetes.service" /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable disable-swap-kubernetes.service

    success "Permanent swap disable mechanism installed"
}
```
