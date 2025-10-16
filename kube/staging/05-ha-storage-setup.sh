#!/bin/bash

# HA Storage Setup Script for Kubernetes Cluster
# Run this script on k8s-stg1 after all control planes have joined
# Purpose: Configure distributed storage across all 2 Dell R740 servers

set -euo pipefail

LOG_FILE="/var/log/ha-storage-setup.log"

# Storage configuration
STORAGE_BASE_PATH="/mnt/k8s-storage"

# Control plane servers (2 servers for staging)
declare -A CONTROL_PLANES=(
    ["k8s-stg1"]="10.255.253.10"
    ["k8s-stg2"]="10.255.253.11"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*${NC}" | tee -a "$LOG_FILE"
    exit 1
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    HA Storage Setup - Distributed Storage Configuration"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script configures distributed storage across all 2"
    echo "Dell R740 servers for the STAGING Kubernetes cluster."
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Verify this is k8s-stg1
    local hostname=$(hostname)
    if [[ "$hostname" != "k8s-stg1" ]]; then
        error "This script should only be run on k8s-stg1. Current hostname: $hostname"
    fi
    
    # Check if kubectl is working
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster. Ensure cluster is initialized"
    fi
    
    # Check if all control planes are joined
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ $ready_nodes -lt 2 ]]; then
        warning "Only $ready_nodes nodes are Ready. Expected 2 nodes. Continuing anyway..."
    fi
    
    success "Prerequisites check passed"
}

verify_all_nodes_storage() {
    log "Verifying storage directories on all nodes..."
    
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        
        log "Checking storage directories on $node ($node_ip)..."
        
        # Check if we can SSH to the node (assuming SSH keys are set up)
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "test -d $STORAGE_BASE_PATH" 2>/dev/null; then
            success "Storage directories verified on $node"
        else
            warning "Cannot verify storage on $node via SSH. Directories should exist from previous scripts"
        fi
    done
}

create_storage_classes() {
    log "Creating storage classes for HA setup..."
    
    cat > /tmp/ha-storage-classes.yaml << EOF
---
# Fast SSD Storage Class for Databases and Critical Applications
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Fast local SSD storage for databases and critical applications"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  type: local-ssd
  performance: high
---
# Standard Storage Class for General Applications (Default)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
    description: "Standard local storage for general applications"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  type: local-standard
  performance: medium
---
# Backup Storage Class for Long-term Data Retention
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: backup-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Backup storage for long-term data retention"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  type: local-backup
  performance: low
---
# Logs Storage Class for Log Aggregation
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: logs-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Storage optimized for log data with high write throughput"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
parameters:
  type: local-logs
  performance: write-optimized
EOF

    kubectl apply -f /tmp/ha-storage-classes.yaml
    success "Storage classes created"
}

create_distributed_persistent_volumes() {
    log "Creating distributed persistent volumes across all nodes..."
    
    cat > /tmp/ha-persistent-volumes.yaml << EOF
EOF

    # Create PVs for each node
    local pv_counter=1
    
    for node in "${!CONTROL_PLANES[@]}"; do
        cat >> /tmp/ha-persistent-volumes.yaml << EOF
---
# PostgreSQL Fast SSD Volume on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv-$pv_counter
  labels:
    type: local-ssd
    app: postgresql
    tier: database
    node: $node
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/fast-ssd/postgresql
    type: DirectoryOrCreate
---
# Redis Fast SSD Volume on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv-$pv_counter
  labels:
    type: local-ssd
    app: redis
    tier: cache
    node: $node
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/fast-ssd/redis
    type: DirectoryOrCreate
---
# Prometheus Fast SSD Volume on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-pv-$pv_counter
  labels:
    type: local-ssd
    app: prometheus
    tier: monitoring
    node: $node
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/fast-ssd/prometheus
    type: DirectoryOrCreate
---
# Grafana Standard Volume on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-pv-$pv_counter
  labels:
    type: local-standard
    app: grafana
    tier: monitoring
    node: $node
spec:
  storageClassName: standard-storage
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/fast-ssd/grafana
    type: DirectoryOrCreate
---
# Loki Logs Volume on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-pv-$pv_counter
  labels:
    type: local-logs
    app: loki
    tier: logging
    node: $node
spec:
  storageClassName: logs-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/fast-ssd/loki
    type: DirectoryOrCreate
---
# General Purpose Volume 1 on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: general-pv-${pv_counter}a
  labels:
    type: local-standard
    app: general
    tier: standard
    node: $node
spec:
  storageClassName: standard-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/standard/general
    type: DirectoryOrCreate
---
# General Purpose Volume 2 on $node
apiVersion: v1
kind: PersistentVolume
metadata:
  name: general-pv-${pv_counter}b
  labels:
    type: local-standard
    app: general
    tier: standard
    node: $node
spec:
  storageClassName: standard-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $STORAGE_BASE_PATH/standard/general-$pv_counter
    type: DirectoryOrCreate
EOF
        ((pv_counter++))
    done

    kubectl apply -f /tmp/ha-persistent-volumes.yaml
    success "Distributed persistent volumes created across all nodes"
}

install_local_path_provisioner() {
    log "Installing local-path-provisioner for dynamic provisioning..."
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/local-path-provisioner -n local-path-storage
    
    # Create custom config for multiple nodes
    cat > /tmp/local-path-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |-
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths": ["$STORAGE_BASE_PATH/standard"]
        }
      ]
    }
  setup: |-
    #!/bin/sh
    set -eu
    mkdir -m 0777 -p "\$VOL_DIR"
  teardown: |-
    #!/bin/sh
    set -eu
    rm -rf "\$VOL_DIR"
  helperPod.yaml: |-
    apiVersion: v1
    kind: Pod
    metadata:
      name: helper-pod
    spec:
      containers:
      - name: helper-pod
        image: busybox:1.36
        imagePullPolicy: IfNotPresent
EOF

    kubectl apply -f /tmp/local-path-config.yaml
    
    # Restart local-path-provisioner to pick up new config
    kubectl rollout restart deployment/local-path-provisioner -n local-path-storage
    kubectl wait --for=condition=available --timeout=300s deployment/local-path-provisioner -n local-path-storage
    
    success "Local-path-provisioner installed and configured"
}

create_storage_monitoring() {
    log "Creating storage monitoring and alerts..."
    
    cat > /tmp/ha-storage-monitoring.yaml << EOF
---
# Storage monitoring service monitor (requires Prometheus Operator)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: storage-metrics
  namespace: monitoring
  labels:
    app: storage-monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
---
# Storage alerting rules (requires Prometheus Operator)
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
  namespace: monitoring
  labels:
    app: storage-monitoring
spec:
  groups:
  - name: storage.rules
    rules:
    - alert: HighDiskUsage
      expr: (node_filesystem_size_bytes{fstype!="tmpfs"} - node_filesystem_free_bytes{fstype!="tmpfs"}) / node_filesystem_size_bytes{fstype!="tmpfs"} > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High disk usage on {{ \$labels.instance }}"
        description: "Disk usage is above 85% on {{ \$labels.instance }} for filesystem {{ \$labels.mountpoint }}"
    
    - alert: CriticalDiskUsage
      expr: (node_filesystem_size_bytes{fstype!="tmpfs"} - node_filesystem_free_bytes{fstype!="tmpfs"}) / node_filesystem_size_bytes{fstype!="tmpfs"} > 0.95
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Critical disk usage on {{ \$labels.instance }}"
        description: "Disk usage is above 95% on {{ \$labels.instance }} for filesystem {{ \$labels.mountpoint }}"
    
    - alert: PersistentVolumeUsageHigh
      expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High PV usage for {{ \$labels.persistentvolumeclaim }}"
        description: "PersistentVolume {{ \$labels.persistentvolumeclaim }} in namespace {{ \$labels.namespace }} is {{ \$value | humanizePercentage }} full"
    
    - alert: PersistentVolumeCritical
      expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.95
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Critical PV usage for {{ \$labels.persistentvolumeclaim }}"
        description: "PersistentVolume {{ \$labels.persistentvolumeclaim }} in namespace {{ \$labels.namespace }} is {{ \$value | humanizePercentage }} full"
    
    - alert: PersistentVolumeFailure
      expr: kube_persistentvolume_status_phase{phase="Failed"} == 1
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "PersistentVolume {{ \$labels.persistentvolume }} failed"
        description: "PersistentVolume {{ \$labels.persistentvolume }} is in Failed state"
EOF

    # Create monitoring namespace if it doesn't exist
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply monitoring configuration (will fail if Prometheus Operator not installed yet)
    kubectl apply -f /tmp/ha-storage-monitoring.yaml || warning "Storage monitoring config applied but may require Prometheus Operator"
    
    success "Storage monitoring configuration created"
}

create_backup_jobs() {
    log "Creating distributed backup jobs..."
    
    cat > /tmp/ha-backup-jobs.yaml << EOF
---
# Namespace for backup operations
apiVersion: v1
kind: Namespace
metadata:
  name: backup-system
---
# Service account for backup operations
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-service-account
  namespace: backup-system
---
# ClusterRole for backup operations
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backup-cluster-role
rules:
- apiGroups: [""]
  resources: ["pods", "persistentvolumes", "persistentvolumeclaims", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
---
# ClusterRoleBinding for backup operations
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backup-cluster-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: backup-cluster-role
subjects:
- kind: ServiceAccount
  name: backup-service-account
  namespace: backup-system
---
# Configuration backup job
apiVersion: batch/v1
kind: CronJob
metadata:
  name: k8s-config-backup
  namespace: backup-system
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              DATE=\$(date +%Y%m%d_%H%M%S)
              BACKUP_DIR="/backup/k8s-configs"
              mkdir -p \$BACKUP_DIR
              
              # Backup all Kubernetes resources
              kubectl get all --all-namespaces -o yaml > \$BACKUP_DIR/all-resources_\${DATE}.yaml
              kubectl get pv,pvc --all-namespaces -o yaml > \$BACKUP_DIR/storage_\${DATE}.yaml
              kubectl get storageclass -o yaml > \$BACKUP_DIR/storageclasses_\${DATE}.yaml
              kubectl get configmaps --all-namespaces -o yaml > \$BACKUP_DIR/configmaps_\${DATE}.yaml
              kubectl get secrets --all-namespaces -o yaml > \$BACKUP_DIR/secrets_\${DATE}.yaml
              kubectl get ingress --all-namespaces -o yaml > \$BACKUP_DIR/ingress_\${DATE}.yaml
              
              # Create a summary
              echo "Kubernetes Configuration Backup - \$DATE" > \$BACKUP_DIR/backup-summary_\${DATE}.txt
              echo "Nodes: \$(kubectl get nodes --no-headers | wc -l)" >> \$BACKUP_DIR/backup-summary_\${DATE}.txt
              echo "Namespaces: \$(kubectl get namespaces --no-headers | wc -l)" >> \$BACKUP_DIR/backup-summary_\${DATE}.txt
              echo "PVs: \$(kubectl get pv --no-headers | wc -l)" >> \$BACKUP_DIR/backup-summary_\${DATE}.txt
              echo "PVCs: \$(kubectl get pvc --all-namespaces --no-headers | wc -l)" >> \$BACKUP_DIR/backup-summary_\${DATE}.txt
              
              # Cleanup old backups (keep 14 days)
              find \$BACKUP_DIR -name "*.yaml" -mtime +14 -delete
              find \$BACKUP_DIR -name "*.txt" -mtime +14 -delete
              
              echo "Kubernetes configuration backup completed: \$BACKUP_DIR"
            volumeMounts:
            - name: backup-volume
              mountPath: /backup
          volumes:
          - name: backup-volume
            hostPath:
              path: $STORAGE_BASE_PATH/backup/configs
              type: DirectoryOrCreate
          restartPolicy: OnFailure
          serviceAccountName: backup-service-account
          nodeSelector:
            kubernetes.io/hostname: k8s-stg1  # Run backup on k8s-stg1
EOF

    kubectl apply -f /tmp/ha-backup-jobs.yaml
    success "Distributed backup jobs created"
}

test_storage_functionality() {
    log "Testing storage functionality..."
    
    # Create a test PVC
    cat > /tmp/storage-test.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-storage
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
  namespace: default
spec:
  containers:
  - name: test-container
    image: busybox:1.36
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing storage write..." > /data/test-file.txt
      echo "Storage test completed at \$(date)" >> /data/test-file.txt
      cat /data/test-file.txt
      sleep 30
    volumeMounts:
    - name: test-storage
      mountPath: /data
  volumes:
  - name: test-storage
    persistentVolumeClaim:
      claimName: storage-test-pvc
  restartPolicy: Never
EOF

    kubectl apply -f /tmp/storage-test.yaml
    
    # Wait for PVC to be bound
    local timeout=60
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        local pvc_status=$(kubectl get pvc storage-test-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$pvc_status" == "Bound" ]]; then
            success "Test PVC bound successfully"
            break
        fi
        sleep 2
        ((counter+=2))
    done
    
    if [[ $counter -ge $timeout ]]; then
        warning "Test PVC did not bind within $timeout seconds"
    fi
    
    # Wait for pod to complete
    kubectl wait --for=condition=Ready --timeout=120s pod/storage-test-pod || warning "Storage test pod did not start properly"
    
    # Cleanup test resources
    kubectl delete -f /tmp/storage-test.yaml --ignore-not-found=true
    
    success "Storage functionality test completed"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Storage Setup Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Storage Classes Created ==="
    kubectl get storageclass
    echo
    echo "=== Persistent Volumes Created ==="
    kubectl get pv
    echo
    echo "=== Storage Distribution ==="
    echo "Fast SSD Storage:"
    echo "  • PostgreSQL: 50Gi per node (100Gi total)"
    echo "  • Redis: 20Gi per node (40Gi total)"
    echo "  • Prometheus: 100Gi per node (200Gi total)"
    echo "  • Grafana: 20Gi per node (40Gi total)"
    echo "  • Loki: 100Gi per node (200Gi total)"
    echo
    echo "Standard Storage:"
    echo "  • General Purpose: 200Gi per node (400Gi total)"
    echo
    echo "=== Local Path Provisioner ==="
    kubectl get pods -n local-path-storage
    echo
    echo "=== Backup System ==="
    kubectl get cronjobs -n backup-system
    echo
    echo "=== Storage Monitoring ==="
    kubectl get prometheusrules -n monitoring 2>/dev/null || echo "Storage monitoring ready (requires Prometheus Operator)"
    echo
    echo "=== Next Steps ==="
    echo "1. Deploy HA ingress controller: 06-ha-ingress-setup.sh"
    echo "2. Deploy monitoring stack: 07-ha-monitoring-setup.sh"
    echo "3. Run cluster validation: 08-cluster-validation.sh"
    echo
    echo "=== Useful Commands ==="
    echo "• View storage classes: kubectl get storageclass"
    echo "• View persistent volumes: kubectl get pv"
    echo "• View PVCs: kubectl get pvc --all-namespaces"
    echo "• Check storage usage: kubectl top nodes"
    echo "• Monitor backups: kubectl logs -n backup-system -l job-name=k8s-config-backup"
    echo
    echo -e "${GREEN}Distributed storage is now configured across all 2 nodes!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    
    log "Starting HA storage setup across all nodes..."
    
    # Storage setup
    verify_all_nodes_storage
    create_storage_classes
    create_distributed_persistent_volumes
    install_local_path_provisioner
    
    # Monitoring and backup
    create_storage_monitoring
    create_backup_jobs
    
    # Testing
    test_storage_functionality
    
    show_completion_info
    
    success "HA storage setup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script configures distributed storage for the STAGING Kubernetes cluster."
        echo "Run this script on k8s-stg1 after all control planes have joined."
        echo
        echo "Storage will be distributed across all 2 Dell R740 servers with:"
        echo "• Multiple storage classes (fast-ssd, standard, backup, logs)"
        echo "• Node-affinity for persistent volumes"
        echo "• Local-path-provisioner for dynamic provisioning"
        echo "• Automated backup jobs"
        echo "• Storage monitoring and alerting"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac