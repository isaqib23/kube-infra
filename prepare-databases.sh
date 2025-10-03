#!/bin/bash

# Database Preparation Script for Kubernetes
# PostgreSQL and Redis deployment using Helm

set -euo pipefail

LOG_FILE="/var/log/k8s-databases.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
    fi
    
    if ! command -v helm &> /dev/null; then
        error "helm is not installed"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster"
    fi
    
    log "Prerequisites check passed ✓"
}

add_helm_repos() {
    log "Adding Helm repositories..."
    
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    log "Helm repositories added ✓"
}

create_namespaces() {
    log "Creating namespaces..."
    
    kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace postgresql --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f -
    
    log "Namespaces created ✓"
}

create_storage_classes() {
    log "Creating storage classes for databases..."
    
    # Fast storage class for databases
    cat > database-storage-class.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: local-ssd
EOF
    
    kubectl apply -f database-storage-class.yaml
    log "Storage classes created ✓"
}

create_persistent_volumes() {
    log "Creating persistent volumes for databases..."
    
    # PostgreSQL PV
    cat > postgresql-pv.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv
  labels:
    type: local
    app: postgresql
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data/postgresql
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv
  labels:
    type: local
    app: redis
spec:
  storageClassName: fast-ssd
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data/redis
    type: DirectoryOrCreate
EOF
    
    kubectl apply -f postgresql-pv.yaml
    log "Persistent volumes created ✓"
}

prepare_postgresql_values() {
    log "Preparing PostgreSQL values..."
    
    cat > postgresql-values.yaml << EOF
## Global parameters
global:
  postgresql:
    auth:
      postgresPassword: "PostgresAdminPassword123!"
      username: "appuser"
      password: "AppUserPassword123!"
      database: "appdb"

## PostgreSQL Primary parameters
primary:
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 20Gi
  
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m
  
  nodeAffinityPreset:
    type: ""
    key: ""
    values: []
  
  podSecurityContext:
    enabled: true
    fsGroup: 1001
  
  containerSecurityContext:
    enabled: true
    runAsUser: 1001
    runAsNonRoot: true

## PostgreSQL read only replica parameters
readReplicas:
  replicaCount: 0

## Metrics parameters
metrics:
  enabled: true
  serviceMonitor:
    enabled: false

## PostgreSQL configuration
postgresql:
  maxConnections: 200
  sharedBuffers: 512MB
  effectiveCacheSize: 2GB
  walBuffers: 16MB
  checkpointCompletionTarget: 0.9
  randomPageCost: 1.1
  
## Use PostgreSQL 17 (latest)
image:
  tag: "17.0.0-debian-12-r4"
EOF
    
    log "PostgreSQL values prepared ✓"
}

prepare_redis_values() {
    log "Preparing Redis values..."
    
    cat > redis-values.yaml << EOF
## Global parameters
global:
  redis:
    password: "RedisPassword123!"

## Redis master parameters
master:
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 10Gi
  
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m

## Redis replica parameters
replica:
  replicaCount: 1
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 10Gi
  
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m

## Metrics parameters
metrics:
  enabled: true
  serviceMonitor:
    enabled: false

## Security parameters
auth:
  enabled: true
  sentinel: true

## Use Redis 7.4 (stable LTS version for production)
image:
  tag: "7.4.1-debian-12-r0"

## Redis configuration
commonConfiguration: |-
  # Enable AOF persistence
  appendonly yes
  appendfsync everysec
  
  # Set maximum memory policy
  maxmemory-policy allkeys-lru
  
  # Increase timeout
  timeout 300
  
  # Enable compression
  rdbcompression yes
  
  # Optimize for performance
  tcp-keepalive 300
  tcp-backlog 511
EOF
    
    log "Redis values prepared ✓"
}

install_postgresql() {
    log "Installing PostgreSQL..."
    
    helm install postgresql bitnami/postgresql \
        --namespace postgresql \
        --values postgresql-values.yaml \
        --wait \
        --timeout 10m
    
    log "PostgreSQL installed ✓"
}

install_redis() {
    log "Installing Redis..."
    
    helm install redis bitnami/redis \
        --namespace redis \
        --values redis-values.yaml \
        --wait \
        --timeout 10m
    
    log "Redis installed ✓"
}

create_database_secrets() {
    log "Creating database connection secrets..."
    
    # PostgreSQL connection secret
    cat > postgresql-connection-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-connection
  namespace: databases
type: Opaque
stringData:
  host: "postgresql.postgresql.svc.cluster.local"
  port: "5432"
  database: "appdb"
  username: "appuser"
  password: "AppUserPassword123!"
  postgres-password: "PostgresAdminPassword123!"
  url: "postgresql://appuser:AppUserPassword123!@postgresql.postgresql.svc.cluster.local:5432/appdb"
EOF
    
    # Redis connection secret
    cat > redis-connection-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-connection
  namespace: databases
type: Opaque
stringData:
  host: "redis-master.redis.svc.cluster.local"
  port: "6379"
  password: "RedisPassword123!"
  url: "redis://:RedisPassword123!@redis-master.redis.svc.cluster.local:6379"
EOF
    
    kubectl apply -f postgresql-connection-secret.yaml
    kubectl apply -f redis-connection-secret.yaml
    
    log "Database connection secrets created ✓"
}

create_database_tests() {
    log "Creating database test pods..."
    
    # PostgreSQL test pod
    cat > postgresql-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-test
  namespace: databases
spec:
  restartPolicy: Never
  containers:
  - name: postgresql-client
    image: postgres:15
    command:
    - /bin/bash
    - -c
    - |
      echo "Testing PostgreSQL connection..."
      export PGPASSWORD=\$POSTGRES_PASSWORD
      psql -h \$POSTGRES_HOST -p \$POSTGRES_PORT -U \$POSTGRES_USER -d \$POSTGRES_DB -c "SELECT version();"
      echo "PostgreSQL connection test completed"
    env:
    - name: POSTGRES_HOST
      valueFrom:
        secretKeyRef:
          name: postgresql-connection
          key: host
    - name: POSTGRES_PORT
      valueFrom:
        secretKeyRef:
          name: postgresql-connection
          key: port
    - name: POSTGRES_DB
      valueFrom:
        secretKeyRef:
          name: postgresql-connection
          key: database
    - name: POSTGRES_USER
      valueFrom:
        secretKeyRef:
          name: postgresql-connection
          key: username
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: postgresql-connection
          key: password
EOF
    
    # Redis test pod
    cat > redis-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: redis-test
  namespace: databases
spec:
  restartPolicy: Never
  containers:
  - name: redis-client
    image: redis:7
    command:
    - /bin/bash
    - -c
    - |
      echo "Testing Redis connection..."
      redis-cli -h \$REDIS_HOST -p \$REDIS_PORT -a \$REDIS_PASSWORD ping
      redis-cli -h \$REDIS_HOST -p \$REDIS_PORT -a \$REDIS_PASSWORD info server
      echo "Redis connection test completed"
    env:
    - name: REDIS_HOST
      valueFrom:
        secretKeyRef:
          name: redis-connection
          key: host
    - name: REDIS_PORT
      valueFrom:
        secretKeyRef:
          name: redis-connection
          key: port
    - name: REDIS_PASSWORD
      valueFrom:
        secretKeyRef:
          name: redis-connection
          key: password
EOF
    
    log "Database test pods created ✓"
}

show_database_info() {
    echo
    echo "=== Database Installation Summary ==="
    echo
    echo "PostgreSQL:"
    echo "- Namespace: postgresql"
    echo "- Service: postgresql.postgresql.svc.cluster.local:5432"
    echo "- Database: appdb"
    echo "- Username: appuser"
    echo "- Admin: postgres"
    echo
    echo "Redis:"
    echo "- Namespace: redis"
    echo "- Master: redis-master.redis.svc.cluster.local:6379"
    echo "- Replica: redis-replica.redis.svc.cluster.local:6379"
    echo
    echo "Connection Secrets:"
    echo "- postgresql-connection (in databases namespace)"
    echo "- redis-connection (in databases namespace)"
    echo
    echo "=== Access Commands ==="
    echo
    echo "PostgreSQL Password:"
    echo "kubectl get secret --namespace postgresql postgresql -o jsonpath='{.data.postgres-password}' | base64 -d"
    echo
    echo "Redis Password:"
    echo "kubectl get secret --namespace redis redis -o jsonpath='{.data.redis-password}' | base64 -d"
    echo
    echo "PostgreSQL Client:"
    echo "kubectl run postgresql-client --rm --tty -i --restart='Never' --namespace postgresql --image postgres:15 --env='PGPASSWORD=\$(kubectl get secret --namespace postgresql postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)' --command -- psql --host postgresql --port 5432 -U postgres -d appdb"
    echo
    echo "Redis Client:"
    echo "kubectl run redis-client --rm --tty -i --restart='Never' --namespace redis --image redis:7 --command -- redis-cli -h redis-master -a \$(kubectl get secret --namespace redis redis -o jsonpath='{.data.redis-password}' | base64 -d)"
    echo
    echo "=== Test Database Connections ==="
    echo "kubectl apply -f postgresql-test.yaml && kubectl logs -f postgresql-test -n databases"
    echo "kubectl apply -f redis-test.yaml && kubectl logs -f redis-test -n databases"
    echo
}

cleanup_test_pods() {
    log "Cleaning up any existing test pods..."
    kubectl delete pod postgresql-test -n databases --ignore-not-found=true
    kubectl delete pod redis-test -n databases --ignore-not-found=true
}

main() {
    log "Starting database preparation for Kubernetes..."
    
    check_prerequisites
    add_helm_repos
    create_namespaces
    create_storage_classes
    create_persistent_volumes
    
    prepare_postgresql_values
    prepare_redis_values
    
    cleanup_test_pods
    
    install_postgresql
    install_redis
    
    create_database_secrets
    create_database_tests
    
    # Wait for databases to be ready
    log "Waiting for databases to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n postgresql --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n redis --timeout=300s
    
    show_database_info
    
    log "Database preparation completed successfully!"
}

main "$@"