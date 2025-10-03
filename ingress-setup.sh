#!/bin/bash

# Advanced Ingress Setup for Kubernetes on Dell R740
# Production-ready ingress with SSL, load balancing, and security

set -euo pipefail

LOG_FILE="/var/log/k8s-ingress.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_prerequisites() {
    log "Checking ingress prerequisites..."
    
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

install_nginx_ingress() {
    log "Installing NGINX Ingress Controller with enhanced configuration..."
    
    # Add NGINX Ingress repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    # Create custom values for NGINX Ingress
    cat > nginx-ingress-values.yaml << EOF
# NGINX Ingress Controller Configuration for Dell R740
controller:
  # Enable metrics
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
  
  # Resource allocation optimized for R740
  resources:
    limits:
      memory: 1Gi
      cpu: 1000m
    requests:
      memory: 512Mi
      cpu: 500m
  
  # Service configuration
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
    
  # Enable SSL passthrough
  extraArgs:
    enable-ssl-passthrough: true
    default-ssl-certificate: ingress-nginx/tls-secret
  
  # Configure for high availability
  replicaCount: 2
  
  # Enable admission webhooks
  admissionWebhooks:
    enabled: true
    failurePolicy: Fail
  
  # Security configuration
  config:
    # SSL Security
    ssl-protocols: "TLSv1.2 TLSv1.3"
    ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256,ECDHE-RSA-AES128-GCM-SHA256,ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES256-GCM-SHA384"
    ssl-prefer-server-ciphers: "true"
    
    # Security headers
    add-headers: "ingress-nginx/security-headers"
    
    # Rate limiting
    rate-limit: "100"
    rate-limit-window: "1m"
    
    # Connection limits
    limit-connections: "50"
    
    # Proxy settings
    proxy-connect-timeout: "15"
    proxy-send-timeout: "600"
    proxy-read-timeout: "600"
    proxy-body-size: "50m"
    
    # Enable real IP
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    
    # Custom error pages
    custom-http-errors: "404,503,502,500"
    
    # Log format
    log-format-escape-json: "true"
    log-format-upstream: '{"time": "\$time_iso8601", "remote_addr": "\$proxy_protocol_addr", "x_forwarded_for": "\$proxy_add_x_forwarded_for", "request_id": "\$req_id", "remote_user": "\$remote_user", "bytes_sent": \$bytes_sent, "request_time": \$request_time, "status": \$status, "vhost": "\$host", "request_proto": "\$server_protocol", "path": "\$uri", "request_query": "\$args", "request_length": \$request_length, "duration": \$request_time, "method": "\$request_method", "http_referrer": "\$http_referer", "http_user_agent": "\$http_user_agent"}'

# Default backend
defaultBackend:
  enabled: true
  resources:
    limits:
      memory: 256Mi
      cpu: 200m
    requests:
      memory: 128Mi
      cpu: 100m

# Admission webhooks
admissionWebhooks:
  enabled: true
  
# TCP/UDP service support
tcp: {}
udp: {}
EOF

    # Install NGINX Ingress with custom values
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --values nginx-ingress-values.yaml \
        --wait \
        --timeout 10m
    
    log "NGINX Ingress Controller installed ✓"
}

create_security_headers() {
    log "Creating security headers ConfigMap..."
    
    cat > security-headers.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-headers
  namespace: ingress-nginx
data:
  # Security headers
  X-Frame-Options: "DENY"
  X-Content-Type-Options: "nosniff"
  X-XSS-Protection: "1; mode=block"
  Referrer-Policy: "strict-origin-when-cross-origin"
  Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'"
  Strict-Transport-Security: "max-age=31536000; includeSubDomains; preload"
  Permissions-Policy: "geolocation=(), microphone=(), camera=(), payment=(), usb=(), interest-cohort=()"
EOF

    kubectl apply -f security-headers.yaml
    log "Security headers configured ✓"
}

create_ssl_certificates() {
    log "Creating self-signed SSL certificates for development..."
    
    # Create certificate directory
    mkdir -p /tmp/ssl-certs
    cd /tmp/ssl-certs
    
    # Generate private key
    openssl genrsa -out tls.key 2048
    
    # Generate certificate signing request
    cat > csr.conf << EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Organization
OU=IT Department
CN=*.local

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.local
DNS.2 = localhost
DNS.3 = *.k8s.local
DNS.4 = grafana.local
DNS.5 = prometheus.local
DNS.6 = alertmanager.local
DNS.7 = loki.local
DNS.8 = k8s-dashboard.local
IP.1 = 127.0.0.1
EOF
    
    # Generate self-signed certificate
    openssl req -new -key tls.key -out tls.csr -config csr.conf
    openssl x509 -req -in tls.csr -signkey tls.key -out tls.crt -days 3650 -extensions v3_req -extfile csr.conf
    
    # Create Kubernetes secret
    kubectl create secret tls tls-secret \
        --cert=tls.crt \
        --key=tls.key \
        --namespace=ingress-nginx
    
    # Create wildcard certificate for applications
    kubectl create secret tls wildcard-tls-secret \
        --cert=tls.crt \
        --key=tls.key \
        --namespace=default
    
    # Copy to other namespaces
    for ns in monitoring databases kubernetes-dashboard; do
        kubectl get secret wildcard-tls-secret -o yaml | \
        sed "s/namespace: default/namespace: $ns/" | \
        kubectl apply -f -
    done
    
    # Cleanup
    cd -
    rm -rf /tmp/ssl-certs
    
    log "SSL certificates created ✓"
}

install_cert_manager() {
    log "Installing cert-manager for automatic SSL certificate management..."
    
    # Add cert-manager repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Install cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.15.3 \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait \
        --timeout 10m
    
    # Create cluster issuer for Let's Encrypt staging
    cat > cluster-issuer-staging.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@company.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

    # Create cluster issuer for Let's Encrypt production
    cat > cluster-issuer-prod.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@company.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

    kubectl apply -f cluster-issuer-staging.yaml
    kubectl apply -f cluster-issuer-prod.yaml
    
    log "cert-manager installed ✓"
}

create_ingress_rules() {
    log "Creating comprehensive ingress rules..."
    
    cat > comprehensive-ingress.yaml << EOF
---
# Grafana Ingress with SSL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /
    # cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Uncomment for Let's Encrypt
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: grafana-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - Grafana'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.local
    secretName: grafana-tls
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
# Prometheus Ingress with SSL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: prometheus-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - Prometheus'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.local
    secretName: prometheus-tls
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
# AlertManager Ingress with SSL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alertmanager-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: alertmanager-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - AlertManager'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - alertmanager.local
    secretName: alertmanager-tls
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
# Loki Ingress with SSL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loki-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: loki-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - Loki'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - loki.local
    secretName: loki-tls
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
---
# Kubernetes Dashboard Ingress with SSL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/secure-backends: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - k8s-dashboard.local
    secretName: dashboard-tls
  rules:
  - host: k8s-dashboard.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF

    kubectl apply -f comprehensive-ingress.yaml
    log "Comprehensive ingress rules created ✓"
}

create_basic_auth() {
    log "Creating basic authentication for monitoring services..."
    
    # Create htpasswd file
    mkdir -p /tmp/auth
    
    # Generate passwords (change these in production!)
    echo "admin:\$2y\$10\$rO.0.lVGS8U8oQaGfhVsKOBGnU8iCZ9hbO3QJ5w2n6yR6vr.8D.e" > /tmp/auth/grafana
    echo "admin:\$2y\$10\$rO.0.lVGS8U8oQaGfhVsKOBGnU8iCZ9hbO3QJ5w2n6yR6vr.8D.e" > /tmp/auth/prometheus
    echo "admin:\$2y\$10\$rO.0.lVGS8U8oQaGfhVsKOBGnU8iCZ9hbO3QJ5w2n6yR6vr.8D.e" > /tmp/auth/alertmanager
    echo "admin:\$2y\$10\$rO.0.lVGS8U8oQaGfhVsKOBGnU8iCZ9hbO3QJ5w2n6yR6vr.8D.e" > /tmp/auth/loki
    
    # Create secrets
    kubectl create secret generic grafana-basic-auth --from-file=/tmp/auth/grafana -n monitoring
    kubectl create secret generic prometheus-basic-auth --from-file=/tmp/auth/prometheus -n monitoring
    kubectl create secret generic alertmanager-basic-auth --from-file=/tmp/auth/alertmanager -n monitoring
    kubectl create secret generic loki-basic-auth --from-file=/tmp/auth/loki -n monitoring
    
    # Cleanup
    rm -rf /tmp/auth
    
    log "Basic authentication configured ✓"
    log "Default credentials - Username: admin, Password: admin123"
}

install_ingress_monitoring() {
    log "Installing ingress monitoring and metrics..."
    
    cat > ingress-monitoring.yaml << EOF
---
# Ingress controller service monitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-ingress-controller
  namespace: monitoring
  labels:
    app: nginx-ingress-controller
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
  namespaceSelector:
    matchNames:
    - ingress-nginx
  endpoints:
  - port: prometheus
    interval: 30s
    path: /metrics
---
# Ingress alerting rules
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ingress-alerts
  namespace: monitoring
  labels:
    app: ingress-monitoring
spec:
  groups:
  - name: ingress.rules
    rules:
    - alert: NginxIngressDown
      expr: up{job=~".*nginx-ingress.*"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "NGINX Ingress controller is down"
        description: "NGINX Ingress controller has been down for more than 5 minutes"
    
    - alert: NginxIngressHighErrorRate
      expr: rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) / rate(nginx_ingress_controller_requests[5m]) > 0.1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High error rate in NGINX Ingress"
        description: "NGINX Ingress error rate is {{ \$value | humanizePercentage }} for {{ \$labels.ingress }}"
    
    - alert: NginxIngressHighLatency
      expr: histogram_quantile(0.99, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) > 2
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High latency in NGINX Ingress"
        description: "99th percentile latency is {{ \$value }}s for {{ \$labels.ingress }}"
    
    - alert: SSLCertificateExpiry
      expr: (nginx_ingress_controller_ssl_expire_time_seconds - time()) / 86400 < 30
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "SSL certificate expiring soon"
        description: "SSL certificate for {{ \$labels.host }} expires in {{ \$value }} days"
EOF

    kubectl apply -f ingress-monitoring.yaml
    log "Ingress monitoring configured ✓"
}

create_rate_limiting() {
    log "Creating rate limiting policies..."
    
    cat > rate-limiting.yaml << EOF
---
# Rate limiting middleware
apiVersion: v1
kind: ConfigMap
metadata:
  name: rate-limit-config
  namespace: ingress-nginx
data:
  rate-limit.conf: |
    # Rate limiting configuration
    limit_req_zone \$binary_remote_addr zone=login:10m rate=1r/s;
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=5r/s;
    
    # Connection limiting
    limit_conn_zone \$binary_remote_addr zone=conn_limit_per_ip:10m;
    limit_conn conn_limit_per_ip 10;
EOF

    kubectl apply -f rate-limiting.yaml
    log "Rate limiting configured ✓"
}

show_ingress_info() {
    echo
    echo "=== Enhanced Ingress Configuration Summary ==="
    echo
    echo "NGINX Ingress Controller:"
    echo "- High availability with 2 replicas"
    echo "- SSL/TLS termination enabled"
    echo "- Security headers configured"
    echo "- Rate limiting enabled"
    echo "- Metrics and monitoring enabled"
    echo
    echo "SSL/TLS Configuration:"
    echo "- Self-signed certificates for development"
    echo "- cert-manager installed for automatic certificate management"
    echo "- TLS 1.2 and 1.3 support"
    echo "- Strong cipher suites"
    echo
    echo "Security Features:"
    echo "- Basic authentication for monitoring services"
    echo "- Security headers (HSTS, CSP, etc.)"
    echo "- Rate limiting per IP address"
    echo "- Connection limits"
    echo
    echo "=== Service URLs ==="
    local node_ip=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "Add these entries to /etc/hosts:"
    echo "\$node_ip grafana.local"
    echo "\$node_ip prometheus.local"
    echo "\$node_ip alertmanager.local"
    echo "\$node_ip loki.local"
    echo "\$node_ip k8s-dashboard.local"
    echo
    echo "Access URLs (with SSL):"
    echo "- Grafana: https://grafana.local:30443"
    echo "- Prometheus: https://prometheus.local:30443"
    echo "- AlertManager: https://alertmanager.local:30443"
    echo "- Loki: https://loki.local:30443"
    echo "- Dashboard: https://k8s-dashboard.local:30443"
    echo
    echo "Default Credentials:"
    echo "- Username: admin"
    echo "- Password: admin123"
    echo
    echo "NodePort Services:"
    echo "- HTTP: 30080"
    echo "- HTTPS: 30443"
    echo
    echo "=== Ingress Status ==="
    kubectl get ingress --all-namespaces
    echo
    echo "=== NGINX Ingress Pods ==="
    kubectl get pods -n ingress-nginx
    echo
    echo "=== Useful Commands ==="
    echo "View ingress logs: kubectl logs -f -n ingress-nginx deployment/ingress-nginx-controller"
    echo "Check certificate status: kubectl get certificates --all-namespaces"
    echo "Test ingress: curl -k https://grafana.local:30443"
    echo "View ingress metrics: kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller-metrics 10254:10254"
    echo
}

main() {
    log "Starting enhanced ingress setup for Dell R740..."
    
    check_prerequisites
    install_nginx_ingress
    create_security_headers
    create_ssl_certificates
    install_cert_manager
    create_basic_auth
    create_ingress_rules
    install_ingress_monitoring
    create_rate_limiting
    
    # Wait for ingress to be ready
    log "Waiting for ingress controller to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s
    
    show_ingress_info
    
    log "Enhanced ingress setup completed successfully!"
}

main "\$@"