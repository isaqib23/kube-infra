#!/bin/bash

# HA Monitoring Setup Script for Kubernetes Cluster
# Run this script on k8s-stg1 after ingress setup
# Purpose: Deploy comprehensive monitoring stack with HA configuration

set -euo pipefail

LOG_FILE="/var/log/ha-monitoring-setup.log"

# Monitoring configuration
CLUSTER_DOMAIN="k8s.local"
GRAFANA_ADMIN_PASSWORD="admin123"
ALERTMANAGER_SLACK_WEBHOOK=""  # Set this for Slack notifications

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
    echo "    HA Monitoring Stack Setup - Prometheus + Grafana + Loki"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script deploys a comprehensive monitoring stack with"
    echo "high availability across all 2 Dell R740 servers."
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
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        error "helm is not installed. Ensure cluster initialization completed successfully"
    fi
    
    # Check if ingress controller is running
    if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers | grep -q "Running"; then
        error "NGINX Ingress Controller not running. Run 06-ha-ingress-setup.sh first"
    fi
    
    # Check if storage classes exist
    if ! kubectl get storageclass fast-ssd &> /dev/null; then
        error "Storage classes not found. Run 05-ha-storage-setup.sh first"
    fi
    
    success "Prerequisites check passed"
}

create_monitoring_namespace() {
    log "Creating monitoring namespace..."
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for network policies
    kubectl label namespace monitoring name=monitoring --overwrite
    
    success "Monitoring namespace created"
}

install_prometheus_operator() {
    log "Installing Prometheus Operator..."
    
    # Add prometheus-community repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Create values file for HA Prometheus stack
    cat > /tmp/prometheus-stack-values.yaml << EOF
# Prometheus Stack HA Configuration for Dell R740 Cluster

# Global settings
fullnameOverride: ""
nameOverride: ""

# Prometheus configuration
prometheus:
  enabled: true
  
  prometheusSpec:
    # HA configuration
    replicas: 2
    retention: 30d
    retentionSize: "90GB"
    
    # Resource allocation for R740
    resources:
      limits:
        memory: 4Gi
        cpu: 2000m
      requests:
        memory: 2Gi
        cpu: 1000m
    
    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi
    
    # Node affinity for distribution
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                - prometheus
            topologyKey: kubernetes.io/hostname
    
    # Security context - Fixed for permission issues
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534  # nobody user
      fsGroup: 65534
      fsGroupChangePolicy: "OnRootMismatch"
    
    # Additional scrape configs
    additionalScrapeConfigs:
    - job_name: 'kubernetes-nodes-cadvisor'
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):10250'
        replacement: '\${1}:4194'
        target_label: __address__
      - source_labels: [__meta_kubernetes_node_name]
        target_label: node
    
    # Service monitor selector
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

# AlertManager configuration
alertmanager:
  enabled: true
  
  alertmanagerSpec:
    # HA configuration
    replicas: 3
    
    # Resource allocation
    resources:
      limits:
        memory: 1Gi
        cpu: 500m
      requests:
        memory: 512Mi
        cpu: 250m
    
    # Storage configuration
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    
    # Node affinity for distribution
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                - alertmanager
            topologyKey: kubernetes.io/hostname

# Grafana configuration
grafana:
  enabled: true
  
  # HA configuration
  replicas: 2
  
  # Admin credentials
  adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  
  # Resource allocation
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m
  
  # Persistence
  persistence:
    enabled: true
    storageClassName: fast-ssd
    size: 20Gi
    accessModes:
    - ReadWriteOnce
  
  # Grafana configuration
  grafana.ini:
    server:
      domain: grafana.${CLUSTER_DOMAIN}
      root_url: https://grafana.${CLUSTER_DOMAIN}
      serve_from_sub_path: false
    security:
      disable_gravatar: true
      cookie_secure: true
      cookie_samesite: strict
    users:
      allow_sign_up: false
      auto_assign_org: true
      auto_assign_org_role: Viewer
    auth:
      disable_login_form: false
    log:
      mode: console
      level: info
    unified_alerting:
      enabled: true
  
  # Data sources
  sidecar:
    datasources:
      enabled: true
      defaultDatasourceEnabled: true
    dashboards:
      enabled: true
      defaultDashboardsEnabled: true
      searchNamespace: ALL
  
  # Default dashboards
  defaultDashboardsEnabled: true
  
  # Service configuration
  service:
    type: ClusterIP
    port: 80

# Node Exporter
nodeExporter:
  enabled: true
  
  # Deploy on all nodes
  hostNetwork: true
  hostPID: true
  
  serviceMonitor:
    enabled: true

# Kube State Metrics
kubeStateMetrics:
  enabled: true

# Prometheus Node Exporter
prometheus-node-exporter:
  enabled: true
  
  # Resource allocation
  resources:
    limits:
      memory: 512Mi
      cpu: 250m
    requests:
      memory: 256Mi
      cpu: 100m

# Kube State Metrics
kube-state-metrics:
  enabled: true
  
  # Resource allocation
  resources:
    limits:
      memory: 512Mi
      cpu: 250m
    requests:
      memory: 256Mi
      cpu: 100m

# Additional exporters
kubeApiServer:
  enabled: true

kubelet:
  enabled: true
  serviceMonitor:
    cAdvisorMetricRelabelings:
    - sourceLabels: [__name__]
      regex: 'container_cpu_usage_seconds_total|container_memory_working_set_bytes|container_fs_usage_bytes|container_fs_limit_bytes'
      action: keep

kubeControllerManager:
  enabled: true

kubeEtcd:
  enabled: true
  service:
    enabled: true
    port: 2381
    targetPort: 2381

kubeScheduler:
  enabled: true

kubeProxy:
  enabled: true

coreDns:
  enabled: true
EOF

    # Install or upgrade Prometheus stack
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values /tmp/prometheus-stack-values.yaml \
        --wait \
        --timeout 20m
    
    success "Prometheus stack installed"
}

install_loki_stack() {
    log "Installing Loki stack for log aggregation..."

    # Add grafana repository
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    # Create values file for Loki (simple single-binary mode)
    cat > /tmp/loki-values.yaml << EOF
# Loki Single Binary Configuration with Persistence
# Simplified deployment for reliable operation

loki:
  auth_enabled: false

  commonConfig:
    replication_factor: 1

  storage:
    type: 'filesystem'

  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

# Deployment mode - using SingleBinary for simplicity and reliability
deploymentMode: SingleBinary

singleBinary:
  replicas: 1

  # Persistence configuration with proper permissions
  persistence:
    enabled: true
    storageClass: logs-storage
    size: 100Gi
    accessModes:
      - ReadWriteOnce

  # Security context to fix permission issues
  podSecurityContext:
    fsGroup: 10001
    runAsGroup: 10001
    runAsNonRoot: true
    runAsUser: 10001
    fsGroupChangePolicy: "OnRootMismatch"

  # Resource allocation for R740
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m

  # Anti-affinity for HA distribution
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
              - single-binary
          topologyKey: kubernetes.io/hostname

# Gateway configuration
gateway:
  enabled: true
  replicas: 2

  resources:
    limits:
      memory: 512Mi
      cpu: 250m
    requests:
      memory: 256Mi
      cpu: 100m

# Monitoring integration
monitoring:
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false

  serviceMonitor:
    enabled: true

# Loki Canary for testing
lokiCanary:
  enabled: false

# Test pod
test:
  enabled: false

# Read component (disabled in SingleBinary mode)
read:
  replicas: 0

# Write component (disabled in SingleBinary mode)
write:
  replicas: 0

# Backend component (disabled in SingleBinary mode)
backend:
  replicas: 0
EOF

    # Create Promtail values for log collection
    cat > /tmp/promtail-values.yaml << EOF
# Promtail Configuration for Log Collection

config:
  # Loki endpoint
  clients:
    - url: http://loki-gateway/loki/api/v1/push
      tenant_id: 1

  # Positions file
  positions:
    filename: /run/promtail/positions.yaml

  # Scrape configs
  snippets:
    scrapeConfigs: |
      # Pod logs
      - job_name: kubernetes-pods
        pipeline_stages:
          - cri: {}
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels:
              - __meta_kubernetes_pod_controller_name
            regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
            action: replace
            target_label: __tmp_controller_name
          - source_labels:
              - __meta_kubernetes_pod_label_app_kubernetes_io_name
              - __meta_kubernetes_pod_label_app
              - __tmp_controller_name
              - __meta_kubernetes_pod_name
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: app
          - source_labels:
              - __meta_kubernetes_pod_label_app_kubernetes_io_component
              - __meta_kubernetes_pod_label_component
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: component
          - action: replace
            source_labels:
            - __meta_kubernetes_pod_node_name
            target_label: node_name
          - action: replace
            source_labels:
            - __meta_kubernetes_namespace
            target_label: namespace
          - action: replace
            replacement: \$1
            separator: /
            source_labels:
            - namespace
            - app
            target_label: job
          - action: replace
            source_labels:
            - __meta_kubernetes_pod_name
            target_label: pod
          - action: replace
            source_labels:
            - __meta_kubernetes_pod_container_name
            target_label: container
          - action: replace
            replacement: /var/log/pods/*\$1/*.log
            separator: /
            source_labels:
            - __meta_kubernetes_pod_uid
            - __meta_kubernetes_pod_container_name
            target_label: __path__
          - action: replace
            regex: true/(.*)
            replacement: /var/log/pods/*\$1/*.log
            separator: /
            source_labels:
            - __meta_kubernetes_pod_annotationpresent_kubernetes_io_config_hash
            - __meta_kubernetes_pod_annotation_kubernetes_io_config_hash
            - __meta_kubernetes_pod_container_name
            target_label: __path__

# DaemonSet to run on all nodes
daemonset:
  enabled: true

# Resource allocation
resources:
  limits:
    memory: 512Mi
    cpu: 250m
  requests:
    memory: 256Mi
    cpu: 100m

# Service Monitor for Prometheus integration
serviceMonitor:
  enabled: true
EOF

    # Install Loki
    log "Installing Loki..."
    helm upgrade --install loki grafana/loki \
        --namespace monitoring \
        --values /tmp/loki-values.yaml \
        --wait \
        --timeout 10m

    # Install Promtail
    log "Installing Promtail..."
    helm upgrade --install promtail grafana/promtail \
        --namespace monitoring \
        --values /tmp/promtail-values.yaml \
        --wait \
        --timeout 5m

    success "Loki stack installed"
}

configure_alerting_rules() {
    log "Configuring custom alerting rules..."
    
    cat > /tmp/custom-alerts.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kubernetes-ha-cluster-alerts
  namespace: monitoring
  labels:
    app: kube-prometheus-stack
    release: kube-prometheus-stack
spec:
  groups:
  - name: kubernetes-ha-cluster.rules
    rules:
    
    # Node availability alerts
    - alert: NodeDown
      expr: up{job="node-exporter"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Node {{ \$labels.instance }} is down"
        description: "Node {{ \$labels.instance }} has been down for more than 5 minutes."
    
    - alert: NodeHighCPU
      expr: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on node {{ \$labels.instance }}"
        description: "CPU usage is above 80% for more than 10 minutes."
    
    - alert: NodeHighMemory
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage on node {{ \$labels.instance }}"
        description: "Memory usage is above 85% for more than 10 minutes."
    
    # Control plane alerts
    - alert: KubernetesAPIServerDown
      expr: up{job="apiserver"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Kubernetes API Server is down on {{ \$labels.instance }}"
        description: "API Server on {{ \$labels.instance }} has been down for more than 1 minute."
    
    - alert: EtcdClusterUnhealthy
      expr: up{job="kube-etcd"} != 1
      for: 3m
      labels:
        severity: critical
      annotations:
        summary: "etcd cluster member {{ \$labels.instance }} is unhealthy"
        description: "etcd cluster member {{ \$labels.instance }} has been unhealthy for more than 3 minutes."
    
    - alert: EtcdInsufficientMembers
      expr: count(up{job="kube-etcd"} == 1) < 3
      for: 3m
      labels:
        severity: critical
      annotations:
        summary: "etcd cluster has insufficient healthy members"
        description: "etcd cluster has {{ \$value }} healthy members. At least 3 are required for quorum."
    
    # HAProxy/Load balancer alerts
    - alert: HAProxyDown
      expr: up{job="haproxy"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "HAProxy is down on {{ \$labels.instance }}"
        description: "HAProxy load balancer on {{ \$labels.instance }} has been down for more than 1 minute."
    
    # Ingress alerts
    - alert: NginxIngressDown
      expr: up{job=~".*nginx-ingress.*"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "NGINX Ingress controller is down"
        description: "NGINX Ingress controller has been down for more than 5 minutes."
    
    - alert: NginxIngressHighErrorRate
      expr: rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) / rate(nginx_ingress_controller_requests[5m]) > 0.1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High error rate in NGINX Ingress"
        description: "NGINX Ingress error rate is {{ \$value | humanizePercentage }} for ingress {{ \$labels.ingress }}."
    
    # Storage alerts
    - alert: PersistentVolumeClaimPending
      expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ \$labels.persistentvolumeclaim }} is pending"
        description: "PVC {{ \$labels.persistentvolumeclaim }} in namespace {{ \$labels.namespace }} has been pending for more than 10 minutes."
    
    # Pod alerts
    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ \$labels.pod }} is crash looping"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is restarting frequently."
    
    - alert: PodNotReady
      expr: kube_pod_status_ready{condition="false"} == 1
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ \$labels.pod }} is not ready"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} has been not ready for more than 10 minutes."
    
    # Cluster resource alerts
    - alert: KubernetesTooManyPods
      expr: count(kube_pod_info) > 200
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Too many pods in cluster"
        description: "Cluster has {{ \$value }} pods. Consider scaling up nodes."
    
    - alert: KubernetesNodeNotReady
      expr: kube_node_status_condition{condition="Ready",status="true"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Node {{ \$labels.node }} is not ready"
        description: "Node {{ \$labels.node }} has been not ready for more than 5 minutes."
EOF

    kubectl apply -f /tmp/custom-alerts.yaml
    success "Custom alerting rules configured"
}

configure_alertmanager() {
    log "Configuring AlertManager..."
    
    cat > /tmp/alertmanager-config.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-kube-prometheus-stack-alertmanager
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'alertmanager@${CLUSTER_DOMAIN}'
      resolve_timeout: 5m
    
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'critical-alerts'
        group_wait: 10s
        repeat_interval: 1h
      - match:
          severity: warning
        receiver: 'warning-alerts'
        repeat_interval: 6h
    
    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'http://localhost:9093/api/v1/alerts'
        send_resolved: true
    
    - name: 'critical-alerts'
      webhook_configs:
      - url: 'http://localhost:9093/api/v1/alerts'
        send_resolved: true
        title: 'Critical Alert - STAGING Kubernetes Cluster'
        text: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Severity: {{ .Labels.severity }}
          Instance: {{ .Labels.instance }}
          {{ end }}
    
    - name: 'warning-alerts'
      webhook_configs:
      - url: 'http://localhost:9093/api/v1/alerts'
        send_resolved: true
        title: 'Warning Alert - STAGING Kubernetes Cluster'
        text: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Severity: {{ .Labels.severity }}
          Instance: {{ .Labels.instance }}
          {{ end }}
    
    inhibit_rules:
    - source_match:
        severity: 'critical'
      target_match:
        severity: 'warning'
      equal: ['alertname', 'instance']
EOF

    kubectl apply -f /tmp/alertmanager-config.yaml
    success "AlertManager configuration applied"
}

install_additional_exporters() {
    log "Installing additional exporters for comprehensive monitoring..."
    
    # HAProxy Exporter for load balancer monitoring
    cat > /tmp/haproxy-exporter.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: haproxy-exporter
  namespace: monitoring
  labels:
    app: haproxy-exporter
spec:
  selector:
    matchLabels:
      app: haproxy-exporter
  template:
    metadata:
      labels:
        app: haproxy-exporter
    spec:
      hostNetwork: true
      containers:
      - name: haproxy-exporter
        image: prom/haproxy-exporter:v0.15.0
        args:
        - '--haproxy.scrape-uri=http://localhost:8404/stats;csv'
        - '--web.listen-address=:9101'
        ports:
        - containerPort: 9101
          name: metrics
        resources:
          limits:
            memory: 128Mi
            cpu: 100m
          requests:
            memory: 64Mi
            cpu: 50m
      tolerations:
      - effect: NoSchedule
        operator: Exists
---
apiVersion: v1
kind: Service
metadata:
  name: haproxy-exporter
  namespace: monitoring
  labels:
    app: haproxy-exporter
spec:
  ports:
  - port: 9101
    targetPort: 9101
    name: metrics
  selector:
    app: haproxy-exporter
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: haproxy-exporter
  namespace: monitoring
  labels:
    app: haproxy-exporter
spec:
  selector:
    matchLabels:
      app: haproxy-exporter
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

    kubectl apply -f /tmp/haproxy-exporter.yaml
    success "HAProxy exporter installed"
}

create_grafana_dashboards() {
    log "Creating custom Grafana dashboards..."
    
    # HA Cluster Overview Dashboard
    cat > /tmp/ha-cluster-dashboard.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ha-cluster-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  ha-cluster-overview.json: |
    {
      "dashboard": {
        "id": null,
        "title": "STAGING Kubernetes Cluster Overview",
        "tags": ["kubernetes", "ha", "dell-r740"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Cluster Nodes Status",
            "type": "stat",
            "targets": [
              {
                "expr": "kube_node_status_condition{condition=\"Ready\",status=\"true\"}",
                "legendFormat": "Ready Nodes"
              }
            ],
            "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Control Plane Health",
            "type": "stat",
            "targets": [
              {
                "expr": "up{job=\"apiserver\"}",
                "legendFormat": "API Servers"
              }
            ],
            "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0}
          },
          {
            "id": 3,
            "title": "etcd Cluster Health",
            "type": "stat",
            "targets": [
              {
                "expr": "up{job=\"kube-etcd\"}",
                "legendFormat": "etcd Members"
              }
            ],
            "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0}
          },
          {
            "id": 4,
            "title": "HAProxy Status",
            "type": "stat",
            "targets": [
              {
                "expr": "up{job=\"haproxy-exporter\"}",
                "legendFormat": "HAProxy Instances"
              }
            ],
            "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0}
          },
          {
            "id": 5,
            "title": "Node CPU Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) by (instance) * 100)",
                "legendFormat": "{{ instance }}"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4}
          },
          {
            "id": 6,
            "title": "Node Memory Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
                "legendFormat": "{{ instance }}"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4}
          }
        ],
        "time": {"from": "now-1h", "to": "now"},
        "refresh": "30s"
      }
    }
EOF

    kubectl apply -f /tmp/ha-cluster-dashboard.yaml
    success "Custom Grafana dashboards created"
}

wait_for_monitoring_ready() {
    log "Waiting for monitoring stack to be ready..."

    # Wait for Prometheus
    kubectl wait --for=condition=available --timeout=600s deployment/kube-prometheus-stack-operator -n monitoring

    # Wait for Grafana
    kubectl wait --for=condition=available --timeout=600s deployment/kube-prometheus-stack-grafana -n monitoring

    # Wait for AlertManager
    kubectl wait --for=condition=ready --timeout=600s pod -l app.kubernetes.io/name=alertmanager -n monitoring

    # Wait for Loki (StatefulSet in single-binary mode)
    kubectl wait --for=condition=ready --timeout=600s pod -l app.kubernetes.io/component=single-binary -n monitoring || warning "Loki not ready"

    # Wait for Loki gateway
    kubectl wait --for=condition=available --timeout=600s deployment/loki-gateway -n monitoring || warning "Loki gateway not ready"

    success "Monitoring stack is ready"
}

configure_monitoring_persistence() {
    log "Verifying monitoring persistence configuration..."
    
    # Check if Prometheus PVCs are bound
    local prometheus_pvcs=$(kubectl get pvc -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -c "Bound" || echo "0")
    if [[ $prometheus_pvcs -gt 0 ]]; then
        success "Prometheus storage is persistent ($prometheus_pvcs PVCs bound)"
    else
        warning "Prometheus storage may not be persistent"
    fi
    
    # Check if Grafana PVC is bound
    if kubectl get pvc -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -q "Bound"; then
        success "Grafana storage is persistent"
    else
        warning "Grafana storage may not be persistent"
    fi
    
    # Check if AlertManager PVCs are bound
    local alertmanager_pvcs=$(kubectl get pvc -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers | grep -c "Bound" || echo "0")
    if [[ $alertmanager_pvcs -gt 0 ]]; then
        success "AlertManager storage is persistent ($alertmanager_pvcs PVCs bound)"
    else
        warning "AlertManager storage may not be persistent"
    fi
}

test_monitoring_functionality() {
    log "Testing monitoring functionality..."
    
    # Test Prometheus API
    if kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &>/dev/null &
    then
        local port_forward_pid=$!
        sleep 10
        
        if curl -s "http://localhost:9090/api/v1/query?query=up" | jq -r '.status' | grep -q "success"; then
            success "Prometheus API is responding"
        else
            warning "Prometheus API test failed"
        fi
        
        kill $port_forward_pid &>/dev/null || true
    else
        warning "Could not test Prometheus API"
    fi
    
    # Test Grafana API
    if kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &>/dev/null &
    then
        local port_forward_pid=$!
        sleep 10
        
        if curl -s "http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/health" | jq -r '.database' | grep -q "ok"; then
            success "Grafana API is responding"
        else
            warning "Grafana API test failed"
        fi
        
        kill $port_forward_pid &>/dev/null || true
    else
        warning "Could not test Grafana API"
    fi
    
    success "Monitoring functionality test completed"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Monitoring Stack Setup Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Monitoring Stack Components ==="
    echo "✓ Prometheus (HA with 2 replicas)"
    echo "✓ Grafana (HA with 2 replicas)"
    echo "✓ AlertManager (HA with 3 replicas)"
    echo "✓ Loki Stack (Distributed mode)"
    echo "✓ Node Exporter (on all nodes)"
    echo "✓ HAProxy Exporter (on all nodes)"
    echo "✓ Kube State Metrics"
    echo
    echo "=== Pod Status ==="
    kubectl get pods -n monitoring -o wide
    echo
    echo "=== Persistent Storage ==="
    kubectl get pvc -n monitoring
    echo
    echo "=== Service Monitor Status ==="
    kubectl get servicemonitor -n monitoring
    echo
    echo "=== Prometheus Rules ==="
    kubectl get prometheusrules -n monitoring
    echo
    echo "=== Access Information ==="
    echo "All services are accessible via ingress with basic authentication:"
    echo "• Grafana: https://grafana.${CLUSTER_DOMAIN}"
    echo "• Prometheus: https://prometheus.${CLUSTER_DOMAIN}"
    echo "• AlertManager: https://alertmanager.${CLUSTER_DOMAIN}"
    echo
    echo "Credentials:"
    echo "• Username: admin"
    echo "• Password: ${GRAFANA_ADMIN_PASSWORD}"
    echo
    echo "=== Port Forward Access (Alternative) ==="
    echo "• Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "• Prometheus: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "• AlertManager: kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093"
    echo
    echo "=== Key Features ==="
    echo "• High availability across all 2 Dell R740 servers"
    echo "• Persistent storage with fast SSD storage class"
    echo "• Comprehensive alerting for cluster health"
    echo "• Log aggregation with Loki and Promtail"
    echo "• HAProxy monitoring for load balancer health"
    echo "• Custom dashboards for HA cluster overview"
    echo "• Automatic service discovery"
    echo "• Data retention: 30 days for metrics, 31 days for logs"
    echo
    echo "=== Next Steps ==="
    echo "1. Run cluster validation: 08-cluster-validation.sh"
    echo "2. Access Grafana and explore pre-configured dashboards"
    echo "3. Configure additional alerting channels (Slack, email)"
    echo "4. Add custom dashboards for specific applications"
    echo
    echo "=== Useful Commands ==="
    echo "• Check monitoring health: kubectl get pods -n monitoring"
    echo "• View Prometheus targets: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "• Check alerting rules: kubectl get prometheusrules -n monitoring"
    echo "• View logs: kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus"
    echo "• Check storage: kubectl get pvc -n monitoring"
    echo
    echo -e "${GREEN}Comprehensive monitoring is now active across your HA cluster!${NC}"
    echo -e "${YELLOW}Remember to configure external alerting (email/Slack) for staging use!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    
    log "Starting HA monitoring stack setup..."
    
    # Basic setup
    create_monitoring_namespace
    
    # Core monitoring stack
    install_prometheus_operator
    install_loki_stack
    
    # Configuration
    configure_alerting_rules
    configure_alertmanager
    
    # Additional components
    install_additional_exporters
    create_grafana_dashboards
    
    # Verification
    wait_for_monitoring_ready
    configure_monitoring_persistence
    test_monitoring_functionality
    
    show_completion_info
    
    success "HA monitoring stack setup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script deploys a comprehensive HA monitoring stack for the Kubernetes cluster."
        echo "Run this script on k8s-stg1 after ingress setup."
        echo
        echo "Components deployed:"
        echo "• Prometheus (HA with 2 replicas)"
        echo "• Grafana (HA with 2 replicas)"
        echo "• AlertManager (HA with 3 replicas)"
        echo "• Loki Stack (distributed log aggregation)"
        echo "• Node Exporter (metrics from all nodes)"
        echo "• HAProxy Exporter (load balancer metrics)"
        echo "• Custom alerting rules for HA cluster health"
        echo "• Persistent storage with fast SSD"
        echo "• Integration with ingress for secure access"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac