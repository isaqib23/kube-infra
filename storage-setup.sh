#!/bin/bash

# Advanced Storage Setup for Kubernetes on Dell R740
# Production-ready storage solutions with multiple storage classes

set -euo pipefail

LOG_FILE="/var/log/k8s-storage.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_prerequisites() {
    log "Checking storage prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster"
    fi
    
    log "Prerequisites check passed ✓"
}

create_storage_directories() {
    log "Creating storage directories on Dell R740..."
    
    # Create base storage directories
    mkdir -p /mnt/k8s-storage/{fast-ssd,standard,backup,logs}
    
    # Create specific application directories
    mkdir -p /mnt/k8s-storage/fast-ssd/{postgresql,redis,prometheus,grafana,loki}
    mkdir -p /mnt/k8s-storage/standard/{general,temp}
    mkdir -p /mnt/k8s-storage/backup/{databases,configs,volumes}
    mkdir -p /mnt/k8s-storage/logs/{applications,system}
    
    # Set proper permissions
    chmod 755 /mnt/k8s-storage
    chmod 755 /mnt/k8s-storage/*
    
    # Set ownership for specific applications
    chown -R 1001:1001 /mnt/k8s-storage/fast-ssd/postgresql
    chown -R 999:999 /mnt/k8s-storage/fast-ssd/redis
    chown -R 65534:65534 /mnt/k8s-storage/fast-ssd/prometheus
    chown -R 472:472 /mnt/k8s-storage/fast-ssd/grafana
    chown -R 10001:10001 /mnt/k8s-storage/fast-ssd/loki
    
    log "Storage directories created ✓"
}

create_storage_classes() {
    log "Creating multiple storage classes for different workloads..."
    
    cat > storage-classes.yaml << EOF
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
# Standard Storage Class for General Applications
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

    kubectl apply -f storage-classes.yaml
    log "Storage classes created ✓"
}

create_persistent_volumes() {
    log "Creating persistent volumes for different storage tiers..."
    
    cat > persistent-volumes.yaml << EOF
---
# PostgreSQL Fast SSD Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv-01
  labels:
    type: local-ssd
    app: postgresql
    tier: database
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/fast-ssd/postgresql
    type: DirectoryOrCreate
---
# Redis Fast SSD Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv-01
  labels:
    type: local-ssd
    app: redis
    tier: cache
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/fast-ssd/redis
    type: DirectoryOrCreate
---
# Prometheus Fast SSD Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-pv-01
  labels:
    type: local-ssd
    app: prometheus
    tier: monitoring
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/fast-ssd/prometheus
    type: DirectoryOrCreate
---
# Grafana Standard Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-pv-01
  labels:
    type: local-standard
    app: grafana
    tier: monitoring
spec:
  storageClassName: standard-storage
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/fast-ssd/grafana
    type: DirectoryOrCreate
---
# Loki Logs Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-pv-01
  labels:
    type: local-logs
    app: loki
    tier: logging
spec:
  storageClassName: logs-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/fast-ssd/loki
    type: DirectoryOrCreate
---
# Loki Write Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-write-pv-01
  labels:
    type: local-logs
    app: loki-write
    tier: logging
spec:
  storageClassName: logs-storage
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/logs/loki-write
    type: DirectoryOrCreate
---
# Loki Read Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-read-pv-01
  labels:
    type: local-logs
    app: loki-read
    tier: logging
spec:
  storageClassName: logs-storage
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/logs/loki-read
    type: DirectoryOrCreate
---
# General Purpose Volumes
apiVersion: v1
kind: PersistentVolume
metadata:
  name: general-pv-01
  labels:
    type: local-standard
    app: general
    tier: standard
spec:
  storageClassName: standard-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/standard/general
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: general-pv-02
  labels:
    type: local-standard
    app: general
    tier: standard
spec:
  storageClassName: standard-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/k8s-storage/standard/general-02
    type: DirectoryOrCreate
EOF

    # Create directory for second general volume
    mkdir -p /mnt/k8s-storage/standard/general-02
    mkdir -p /mnt/k8s-storage/logs/loki-{write,read}
    
    kubectl apply -f persistent-volumes.yaml
    log "Persistent volumes created ✓"
}

install_local_path_provisioner() {
    log "Installing local-path-provisioner for dynamic provisioning..."
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
    
    # Create custom local-path config
    cat > local-path-config.yaml << EOF
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
          "paths": ["/mnt/k8s-storage/standard"]
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

    kubectl apply -f local-path-config.yaml
    
    # Restart local-path-provisioner to pick up new config
    kubectl rollout restart deployment/local-path-provisioner -n local-path-storage
    
    log "Local-path-provisioner installed ✓"
}

create_storage_monitoring() {
    log "Creating storage monitoring and alerts..."
    
    cat > storage-monitoring.yaml << EOF
---
# Storage monitoring service monitor
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
# Storage alerting rules
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
EOF

    kubectl apply -f storage-monitoring.yaml
    log "Storage monitoring configured ✓"
}

create_backup_jobs() {
    log "Creating backup jobs for persistent volumes..."
    
    cat > backup-jobs.yaml << EOF
---
# Database backup job
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
  namespace: databases
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:17
            command:
            - /bin/bash
            - -c
            - |
              DATE=\$(date +%Y%m%d_%H%M%S)
              pg_dump -h postgresql.postgresql.svc.cluster.local -U postgres -d appdb > /backup/postgresql_\${DATE}.sql
              find /backup -name "postgresql_*.sql" -mtime +7 -delete
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgresql-connection
                  key: postgres-password
            volumeMounts:
            - name: backup-volume
              mountPath: /backup
          volumes:
          - name: backup-volume
            hostPath:
              path: /mnt/k8s-storage/backup/databases
              type: DirectoryOrCreate
          restartPolicy: OnFailure
---
# Configuration backup job
apiVersion: batch/v1
kind: CronJob
metadata:
  name: config-backup
  namespace: kube-system
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
              kubectl get all --all-namespaces -o yaml > /backup/k8s-resources_\${DATE}.yaml
              kubectl get pv,pvc --all-namespaces -o yaml > /backup/k8s-storage_\${DATE}.yaml
              find /backup -name "k8s-*.yaml" -mtime +14 -delete
            volumeMounts:
            - name: backup-volume
              mountPath: /backup
          volumes:
          - name: backup-volume
            hostPath:
              path: /mnt/k8s-storage/backup/configs
              type: DirectoryOrCreate
          restartPolicy: OnFailure
          serviceAccountName: backup-service-account
---
# Service account for backup jobs
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-service-account
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backup-cluster-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: backup-service-account
  namespace: kube-system
EOF

    kubectl apply -f backup-jobs.yaml
    log "Backup jobs created ✓"
}

show_storage_info() {
    echo
    echo "=== Enhanced Storage Configuration Summary ==="
    echo
    echo "Storage Classes Created:"
    echo "- fast-ssd: High-performance storage for databases and critical apps"
    echo "- standard-storage: Default storage for general applications (DEFAULT)"
    echo "- backup-storage: Long-term storage for backups and archives"
    echo "- logs-storage: Write-optimized storage for log aggregation"
    echo
    echo "Storage Directories on Dell R740:"
    echo "- /mnt/k8s-storage/fast-ssd/    - High-performance applications"
    echo "- /mnt/k8s-storage/standard/    - General applications"
    echo "- /mnt/k8s-storage/backup/      - Backup and archive data"
    echo "- /mnt/k8s-storage/logs/        - Log aggregation data"
    echo
    echo "Persistent Volumes Created:"
    kubectl get pv
    echo
    echo "Storage Classes:"
    kubectl get storageclass
    echo
    echo "=== Storage Monitoring ==="
    echo "✓ Disk usage alerts configured"
    echo "✓ PersistentVolume usage monitoring"
    echo "✓ Automated backup jobs scheduled"
    echo
    echo "=== Backup Schedule ==="
    echo "- Database backups: Daily at 2 AM"
    echo "- Configuration backups: Daily at 3 AM"
    echo "- Retention: 7 days for DB, 14 days for configs"
    echo
    echo "=== Useful Commands ==="
    echo "Check storage usage: kubectl top nodes"
    echo "View PV status: kubectl get pv,pvc --all-namespaces"
    echo "Check backup jobs: kubectl get cronjobs --all-namespaces"
    echo "View storage metrics: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090"
    echo
}

main() {
    log "Starting enhanced storage setup for Dell R740..."
    
    check_prerequisites
    create_storage_directories
    create_storage_classes
    create_persistent_volumes
    install_local_path_provisioner
    create_storage_monitoring
    create_backup_jobs
    
    show_storage_info
    
    log "Enhanced storage setup completed successfully!"
}

main "$@"