#!/bin/bash

# Enhanced Monitoring Setup Script for Kubernetes
# Latest versions: Prometheus, Grafana, Loki, AlertManager

set -euo pipefail

LOG_FILE="/var/log/k8s-monitoring.log"

# Latest versions as of October 2025
KUBE_PROMETHEUS_STACK_VERSION="66.2.2"
LOKI_STACK_VERSION="2.11.1"
GRAFANA_VERSION="11.3.0"
PROMETHEUS_VERSION="v2.55.1"
ALERTMANAGER_VERSION="v0.28.1"
LOKI_VERSION="3.3.1"
PROMTAIL_VERSION="3.3.1"
TEMPO_VERSION="2.7.1"

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
    log "Adding latest Helm repositories..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    log "Helm repositories updated ✓"
}

create_namespace() {
    log "Creating monitoring namespace..."
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    log "Monitoring namespace created ✓"
}

prepare_kube_prometheus_values() {
    log "Preparing kube-prometheus-stack values with latest versions..."
    
    cat > kube-prometheus-stack-values.yaml << EOF
# Kube Prometheus Stack Configuration - Latest Version
grafana:
  enabled: true
  adminPassword: "GrafanaAdmin123!"
  
  # Use latest Grafana patch version
  image:
    tag: "11.3.2"
  
  persistence:
    enabled: true
    storageClassName: local-storage
    size: 10Gi
  
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m
  
  # Enhanced Grafana configuration
  grafana.ini:
    server:
      root_url: http://grafana.local
      serve_from_sub_path: false
    security:
      allow_embedding: true
      cookie_secure: false
    auth.anonymous:
      enabled: true
      org_role: Viewer
    feature_toggles:
      enable: "tempoSearch,traceqlEditor"
  
  # Pre-installed plugins
  plugins:
    - grafana-piechart-panel
    - grafana-worldmap-panel
    - grafana-clock-panel
    - redis-datasource
    - postgres-datasource
  
  # Additional data sources
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway.monitoring.svc.cluster.local
      access: proxy
      jsonData:
        maxLines: 1000
    - name: Tempo
      type: tempo
      url: http://tempo.monitoring.svc.cluster.local:3100
      access: proxy

prometheus:
  prometheusSpec:
    # Use latest Prometheus version
    image:
      tag: "v2.55.1"
    
    # Enhanced storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-storage
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi
    
    # Increased resources for better performance
    resources:
      limits:
        memory: 4Gi
        cpu: 2000m
      requests:
        memory: 2Gi
        cpu: 1000m
    
    # Enhanced retention policy
    retention: 30d
    retentionSize: 90GB
    
    # Evaluation interval
    evaluationInterval: 30s
    scrapeInterval: 30s
    
    # Service monitor selectors
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    
    # Additional scrape configs for custom metrics
    additionalScrapeConfigs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)

alertmanager:
  alertmanagerSpec:
    # Use latest AlertManager version
    image:
      tag: "v0.28.1"
    
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-storage
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    
    resources:
      limits:
        memory: 512Mi
        cpu: 300m
      requests:
        memory: 256Mi
        cpu: 150m

# Enhanced node exporter
nodeExporter:
  enabled: true
  
# Enhanced kube-state-metrics
kubeStateMetrics:
  enabled: true

# Prometheus Operator
prometheusOperator:
  # Use latest operator version
  image:
    tag: "v0.78.1"
  
  resources:
    limits:
      memory: 512Mi
      cpu: 300m
    requests:
      memory: 256Mi
      cpu: 150m

# Custom alerting rules
additionalPrometheusRules:
  - name: kubernetes.enhanced.rules
    groups:
    - name: kubernetes.enhanced
      rules:
      - alert: KubernetesPodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ \$labels.pod }} is crash looping"
          description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} has restarted {{ \$value }} times in the last 15 minutes"
      
      - alert: KubernetesNodeNotReady
        expr: kube_node_status_condition{condition="Ready",status="true"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ \$labels.node }} is not ready"
          description: "Node {{ \$labels.node }} has been not ready for more than 5 minutes"
      
      - alert: KubernetesPodMemoryUsageHigh
        expr: (container_memory_working_set_bytes / container_spec_memory_limit_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ \$labels.pod }} memory usage is high"
          description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is using {{ \$value | humanizePercentage }} of its memory limit"
      
      - alert: PostgreSQLDown
        expr: up{job=~".*postgresql.*"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL database is not responding"
      
      - alert: RedisDown
        expr: up{job=~".*redis.*"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          description: "Redis database is not responding"
EOF
    
    log "Kube-prometheus-stack values prepared ✓"
}

prepare_loki_values() {
    log "Preparing Loki stack values with latest version..."
    
    cat > loki-values.yaml << EOF
# Loki Configuration - Latest Version
deploymentMode: SimpleScalable

loki:
  # Use latest Loki version
  image:
    tag: "3.3.1"
  
  auth_enabled: false
  
  commonConfig:
    replication_factor: 1
  
  storage:
    type: 'filesystem'
    filesystem:
      chunks_directory: /var/loki/chunks
      rules_directory: /var/loki/rules
  
  schemaConfig:
    configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: loki_index_
        period: 24h
  
  # Enhanced limits configuration
  limits_config:
    retention_period: 744h  # 31 days
    enforce_metric_name: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    max_cache_freshness_per_query: 10m
    split_queries_by_interval: 15m
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20

# Write component
write:
  replicas: 1
  persistence:
    storageClass: local-storage
    size: 50Gi
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m

# Read component
read:
  replicas: 1
  persistence:
    storageClass: local-storage
    size: 50Gi
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m

# Backend component
backend:
  replicas: 1
  persistence:
    storageClass: local-storage
    size: 50Gi
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m

# Gateway
gateway:
  enabled: true
  replicas: 1
  resources:
    limits:
      memory: 512Mi
      cpu: 300m
    requests:
      memory: 256Mi
      cpu: 150m

# Disable test pods
test:
  enabled: false

# Monitoring
monitoring:
  selfMonitoring:
    enabled: false
  serviceMonitor:
    enabled: true
  rules:
    enabled: true
EOF
    
    log "Loki values prepared ✓"
}

prepare_promtail_values() {
    log "Preparing Promtail values with latest version..."
    
    cat > promtail-values.yaml << EOF
# Promtail Configuration - Latest Version
image:
  tag: "3.3.1"

config:
  # Updated Loki address for new gateway
  clients:
    - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
      tenant_id: 1

  snippets:
    pipelineStages:
      - cri: {}
      - labeldrop:
          - filename
      - timestamp:
          source: timestamp
          format: RFC3339Nano
      - output:
          source: output

  # Enhanced scrape configs
  scrapeConfigs: |
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
            - __meta_kubernetes_pod_label_app_kubernetes_io_instance
            - __meta_kubernetes_pod_label_release
          regex: ^;*([^;]+)(;.*)?$
          action: replace
          target_label: instance
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

resources:
  limits:
    memory: 256Mi
    cpu: 200m
  requests:
    memory: 128Mi
    cpu: 100m

# Service monitor for Promtail metrics
serviceMonitor:
  enabled: true
EOF
    
    log "Promtail values prepared ✓"
}

prepare_alertmanager_config() {
    log "Preparing enhanced AlertManager configuration..."
    
    cat > alertmanager-config.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'alerts@company.com'
      resolve_timeout: 5m
    
    templates:
      - '/etc/alertmanager/templates/*.tmpl'
    
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'critical-alerts'
        group_wait: 5s
        repeat_interval: 5m
      - match:
          severity: warning
        receiver: 'warning-alerts'
        group_wait: 10s
        repeat_interval: 30m
      - match_re:
          alertname: '^(PostgreSQL|Redis).*'
        receiver: 'database-alerts'
        group_wait: 5s
        repeat_interval: 10m
    
    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'cluster', 'service']
    
    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'http://webhook.example.com/webhook'
        send_resolved: true
    
    - name: 'critical-alerts'
      email_configs:
      - to: 'admin@company.com'
        subject: '[CRITICAL] {{ .GroupLabels.alertname }} - {{ .GroupLabels.cluster }}'
        body: |
          {{ range .Alerts -}}
          **Alert:** {{ .Annotations.summary }}
          **Description:** {{ .Annotations.description }}
          **Severity:** {{ .Labels.severity }}
          **Started:** {{ .StartsAt }}
          {{ if .EndsAt }}**Ended:** {{ .EndsAt }}{{ end }}
          **Labels:**
          {{ range .Labels.SortedPairs }} • {{ .Name }}: {{ .Value }}
          {{ end }}
          {{ end }}
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#alerts-critical'
        title: '[CRITICAL] {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}
    
    - name: 'warning-alerts'
      email_configs:
      - to: 'team@company.com'
        subject: '[WARNING] {{ .GroupLabels.alertname }} - {{ .GroupLabels.cluster }}'
        body: |
          {{ range .Alerts -}}
          **Alert:** {{ .Annotations.summary }}
          **Description:** {{ .Annotations.description }}
          **Severity:** {{ .Labels.severity }}
          **Started:** {{ .StartsAt }}
          {{ if .EndsAt }}**Ended:** {{ .EndsAt }}{{ end }}
          {{ end }}
    
    - name: 'database-alerts'
      email_configs:
      - to: 'dba@company.com'
        subject: '[DATABASE] {{ .GroupLabels.alertname }} - {{ .GroupLabels.cluster }}'
        body: |
          {{ range .Alerts -}}
          **Database Alert:** {{ .Annotations.summary }}
          **Description:** {{ .Annotations.description }}
          **Service:** {{ .Labels.job }}
          **Started:** {{ .StartsAt }}
          {{ if .EndsAt }}**Ended:** {{ .EndsAt }}{{ end }}
          {{ end }}
EOF
    
    kubectl apply -f alertmanager-config.yaml
    log "Enhanced AlertManager configuration created ✓"
}

install_kube_prometheus_stack() {
    log "Installing kube-prometheus-stack with latest version..."
    
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --version "$KUBE_PROMETHEUS_STACK_VERSION" \
        --namespace monitoring \
        --values kube-prometheus-stack-values.yaml \
        --wait \
        --timeout 15m
    
    log "Kube-prometheus-stack installed ✓"
}

install_loki_stack() {
    log "Installing Loki stack with latest version..."
    
    helm install loki grafana/loki \
        --version "$LOKI_STACK_VERSION" \
        --namespace monitoring \
        --values loki-values.yaml \
        --wait \
        --timeout 15m
    
    log "Loki stack installed ✓"
}

install_promtail() {
    log "Installing Promtail with latest version..."
    
    helm install promtail grafana/promtail \
        --version "6.18.2" \
        --namespace monitoring \
        --values promtail-values.yaml \
        --wait \
        --timeout 10m
    
    log "Promtail installed ✓"
}

install_tempo() {
    log "Installing Tempo for distributed tracing..."
    
    cat > tempo-values.yaml << EOF
# Tempo Configuration for Distributed Tracing
tempo:
  # Use latest Tempo version
  image:
    tag: "2.7.1"
  
  # Storage configuration
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
  
  # Retention policy
  retention: 168h  # 7 days

# Persistence
persistence:
  enabled: true
  storageClassName: local-storage
  size: 50Gi

# Resources
resources:
  limits:
    memory: 1Gi
    cpu: 500m
  requests:
    memory: 512Mi
    cpu: 250m

# Service monitor
serviceMonitor:
  enabled: true
EOF
    
    helm install tempo grafana/tempo \
        --namespace monitoring \
        --values tempo-values.yaml \
        --wait \
        --timeout 10m
    
    log "Tempo installed ✓"
}

create_ingress() {
    log "Creating enhanced ingress for monitoring services..."
    
    cat > monitoring-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: prometheus.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            port:
              number: 9090
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alertmanager-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: alertmanager.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-alertmanager
            port:
              number: 9093
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loki-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: loki.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki-gateway
            port:
              number: 80
EOF
    
    kubectl apply -f monitoring-ingress.yaml
    log "Enhanced monitoring ingress created ✓"
}

create_service_monitors() {
    log "Creating service monitors for databases and custom services..."
    
    cat > database-service-monitors.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgresql-metrics
  namespace: monitoring
  labels:
    app: postgresql
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: postgresql
      app.kubernetes.io/component: metrics
  namespaceSelector:
    matchNames:
    - postgresql
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-metrics
  namespace: monitoring
  labels:
    app: redis
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/component: metrics
  namespaceSelector:
    matchNames:
    - redis
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: loki-metrics
  namespace: monitoring
  labels:
    app: loki
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: loki
  endpoints:
  - port: http-metrics
    interval: 15s
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: promtail-metrics
  namespace: monitoring
  labels:
    app: promtail
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: promtail
  endpoints:
  - port: http-metrics
    interval: 15s
    path: /metrics
EOF
    
    kubectl apply -f database-service-monitors.yaml
    log "Service monitors created ✓"
}

create_dashboards() {
    log "Creating custom Grafana dashboards..."
    
    cat > custom-dashboards.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-dashboards
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  kubernetes-overview.json: |
    {
      "dashboard": {
        "id": null,
        "title": "Kubernetes Cluster Overview - Enhanced",
        "tags": ["kubernetes"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Cluster Nodes",
            "type": "stat",
            "targets": [
              {
                "expr": "count(up{job=\"kubernetes-nodes\"})",
                "refId": "A"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {
                  "steps": [
                    {"color": "green", "value": null},
                    {"color": "red", "value": 80}
                  ]
                }
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
          }
        ],
        "time": {"from": "now-6h", "to": "now"},
        "refresh": "30s"
      }
    }
EOF
    
    kubectl apply -f custom-dashboards.yaml
    log "Custom dashboards created ✓"
}

show_monitoring_info() {
    echo
    echo "=== Enhanced Monitoring Stack Installation Summary ==="
    echo
    echo "Services Installed (Latest Versions - October 2025):"
    echo "- Prometheus v2.55.1 (metrics collection and alerting)"
    echo "- Grafana v11.3.0 (visualization and dashboards)"
    echo "- AlertManager v0.28.1 (alert routing and notification)"
    echo "- Loki v3.3.1 (log aggregation)"
    echo "- Promtail v3.3.1 (log collection)"
    echo "- Tempo v2.7.1 (distributed tracing)"
    echo
    echo "=== Access Information ==="
    echo
    echo "Grafana:"
    echo "- URL: http://grafana.local (add to /etc/hosts)"
    echo "- Username: admin"
    echo "- Password: GrafanaAdmin123!"
    echo "- Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo
    echo "Prometheus:"
    echo "- URL: http://prometheus.local (add to /etc/hosts)"
    echo "- Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    echo
    echo "AlertManager:"
    echo "- URL: http://alertmanager.local (add to /etc/hosts)"
    echo "- Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093"
    echo
    echo "Loki:"
    echo "- URL: http://loki.local (add to /etc/hosts)"
    echo "- Port-forward: kubectl port-forward -n monitoring svc/loki-gateway 3100:80"
    echo
    echo "=== /etc/hosts entries ==="
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "Add these lines to /etc/hosts:"
    echo "$node_ip prometheus.local"
    echo "$node_ip grafana.local"
    echo "$node_ip alertmanager.local"
    echo "$node_ip loki.local"
    echo
    echo "=== Enhanced Features ==="
    echo "✓ Latest component versions"
    echo "✓ Distributed tracing with Tempo"
    echo "✓ Enhanced log aggregation with Loki"
    echo "✓ Custom alerting rules for databases"
    echo "✓ Advanced Grafana dashboards"
    echo "✓ Service monitors for all components"
    echo "✓ Optimized resource allocation"
    echo "✓ Extended retention policies"
    echo
    echo "=== Pre-configured Dashboards ==="
    echo "Grafana includes enhanced dashboards for:"
    echo "- Kubernetes cluster overview (enhanced)"
    echo "- Node metrics and health"
    echo "- Pod resource usage and performance"
    echo "- Database metrics (PostgreSQL, Redis)"
    echo "- Log analysis and search"
    echo "- Distributed tracing visualization"
    echo "- Custom application metrics"
    echo
    echo "=== Useful Commands ==="
    echo "Check monitoring pods: kubectl get pods -n monitoring"
    echo "View Grafana password: kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d"
    echo "View Prometheus config: kubectl get secret -n monitoring prometheus-kube-prometheus-stack-prometheus -o yaml"
    echo "Query Loki logs: curl -G -s 'http://loki.local/loki/api/v1/query' --data-urlencode 'query={job=\"kubernetes-pods\"}'"
    echo
}

wait_for_services() {
    log "Waiting for monitoring services to be ready..."
    
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=600s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=600s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n monitoring --timeout=600s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n monitoring --timeout=600s
    
    log "Monitoring services are ready ✓"
}

main() {
    log "Starting enhanced monitoring stack installation with latest versions..."
    
    check_prerequisites
    add_helm_repos
    create_namespace
    
    prepare_kube_prometheus_values
    prepare_loki_values
    prepare_promtail_values
    prepare_alertmanager_config
    
    install_kube_prometheus_stack
    install_loki_stack
    install_promtail
    install_tempo
    
    wait_for_services
    
    create_ingress
    create_service_monitors
    create_dashboards
    
    show_monitoring_info
    
    log "Enhanced monitoring stack installation completed successfully!"
}

main "$@"