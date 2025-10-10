#!/bin/bash
# Permanent swap disable for Kubernetes
# Run this script on all Kubernetes nodes to permanently disable swap

set -e

echo "=== Permanently Disabling Swap for Kubernetes ==="

# Disable swap immediately
echo "Disabling swap..."
swapoff -a

# Remove swap file if it exists
if [ -f /swap.img ]; then
    echo "Removing /swap.img..."
    rm -f /swap.img
fi

# Disable swap in fstab
echo "Commenting out swap entries in /etc/fstab..."
sed -i '/swap/s/^/#/' /etc/fstab

# Disable systemd swap services
echo "Masking systemd swap services..."
systemctl mask swap.target 2>/dev/null || true
systemctl mask swapfile.swap 2>/dev/null || true

# Disable cloud-init swap module
echo "Disabling cloud-init swap creation..."
mkdir -p /etc/cloud/cloud.cfg.d/
cat > /etc/cloud/cloud.cfg.d/99-disable-swap.cfg <<'CLOUDEOF'
# Disable swap creation by cloud-init
swap:
  size: 0
  maxsize: 0
CLOUDEOF

# Verify swap is disabled
echo "Verifying swap status..."
if swapon --show | grep -q .; then
    echo "ERROR: Swap is still enabled!"
    swapon --show
    exit 1
else
    echo "SUCCESS: Swap is permanently disabled"
fi

echo ""
echo "=== Swap Disable Complete ==="
echo "Swap has been permanently disabled and will remain disabled after reboot."
