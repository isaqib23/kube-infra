#!/bin/bash

# Script to adapt production scripts for staging and development environments
# This automates the creation of environment-specific scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "Adapting production scripts for staging and development..."

# Function to adapt script for staging (2 servers)
adapt_for_staging() {
    local src_file=$1
    local dst_file=$2

    sed \
        -e 's/10\.255\.254/10.255.253/g' \
        -e 's/k8s-cp1/k8s-stg1/g' \
        -e 's/k8s-cp2/k8s-stg2/g' \
        -e 's/k8s-cp3/k8s-stg1/g' \
        -e 's/k8s-cp4/k8s-stg2/g' \
        -e 's/production/staging/gi' \
        -e 's/PRODUCTION/STAGING/g' \
        -e 's/Production/Staging/g' \
        -e 's/"51"/"52"/g' \
        -e 's/k8s-ha24/k8s-stg24/g' \
        -e 's/HA Kubernetes/STAGING Kubernetes/g' \
        -e 's/4-node/2-node/g' \
        -e 's/4 servers/2 servers/g' \
        -e 's/ALL 4/BOTH/g' \
        -e 's/4 Dell R740/2 Dell R740/g' \
        -e 's/ha-k8s-cluster/staging-k8s-cluster/g' \
        -e '/# Load environment configuration/a \
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\
source "$SCRIPT_DIR/env-config.sh"\
source "$SCRIPT_DIR/../common/common-functions.sh"' \
        "$src_file" > "$dst_file"

    chmod +x "$dst_file"
    echo "Created: $dst_file"
}

# Function to adapt script for development (1 server)
adapt_for_development() {
    local src_file=$1
    local dst_file=$2

    sed \
        -e 's/10\.255\.254/10.255.252/g' \
        -e 's/k8s-cp1/k8s-dev1/g' \
        -e 's/production/development/gi' \
        -e 's/PRODUCTION/DEVELOPMENT/g' \
        -e 's/Production/Development/g' \
        -e 's/HA Kubernetes/DEVELOPMENT Kubernetes/g' \
        -e 's/4-node/single-node/g' \
        -e 's/2-node/single-node/g' \
        -e 's/4 servers/1 server/g' \
        -e 's/ha-k8s-cluster/dev-k8s-cluster/g' \
        -e '/# Load environment configuration/a \
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\
source "$SCRIPT_DIR/env-config.sh"\
source "$SCRIPT_DIR/../common/common-functions.sh"' \
        "$src_file" > "$dst_file"

    chmod +x "$dst_file"
    echo "Created: $dst_file"
}

# Copy scripts to staging (except those already created)
echo ""
echo "=== Adapting scripts for STAGING ==="
for script in "$BASE_DIR/production/"*.sh; do
    basename_script=$(basename "$script")
    staging_script="$BASE_DIR/staging/$basename_script"

    # Skip if already exists
    if [[ -f "$staging_script" ]]; then
        echo "Skipping (already exists): $staging_script"
        continue
    fi

    adapt_for_staging "$script" "$staging_script"
done

# Copy scripts to development
echo ""
echo "=== Adapting scripts for DEVELOPMENT ==="
for script in "$BASE_DIR/production/"*.sh; do
    basename_script=$(basename "$script")
    dev_script="$BASE_DIR/development/$basename_script"

    # Skip cluster join script for single-node development
    if [[ "$basename_script" == "04-ha-cluster-join.sh" ]]; then
        echo "Skipping (not needed for single-node): $dev_script"
        continue
    fi

    # Skip server failure test for development
    if [[ "$basename_script" == "09-server-failure-test.sh" ]]; then
        echo "Skipping (not applicable for dev): $dev_script"
        continue
    fi

    adapt_for_development "$script" "$dev_script"
done

echo ""
echo "✓ Script adaptation completed!"
echo ""
echo "Next steps:"
echo "1. Review adapted scripts in staging/ and development/ directories"
echo "2. Test scripts in staging environment first"
echo "3. Make any manual adjustments if needed"
