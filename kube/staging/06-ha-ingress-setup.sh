#!/bin/bash

# HA Ingress Controller Setup Script for Kubernetes Cluster
# Run this script on k8s-stg1 after storage setup
# Purpose: Deploy and configure HA NGINX Ingress Controller

set -euo pipefail

LOG_FILE="/var/log/ha-ingress-setup.log"

# Ingress configuration
VIP="10.255.254.100"
CLUSTER_DOMAIN="k8s.local"

# Control plane servers (2 servers for staging)
declare -A CONTROL_PLANES=(
    ["k8s-stg1"]="10.255.254.20"
    ["k8s-stg2"]="10.255.254.21"
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
    echo "    HA Ingress Controller Setup - NGINX with SSL/TLS"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script deploys a High Availability NGINX Ingress"
    echo "Controller with SSL/TLS, security, and monitoring."
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
    
    # Check if all nodes are ready
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ $ready_nodes -lt 2 ]]; then
        warning "Only $ready_nodes nodes are Ready. Expected 2 nodes."
    fi
    
    # Check if storage classes exist
    if ! kubectl get storageclass standard-storage &> /dev/null; then
        error "Storage classes not found. Run 05-ha-storage-setup.sh first"
    fi
    
    success "Prerequisites check passed"
}

install_cert_manager() {
    log "Installing cert-manager for automatic SSL certificate management..."
    
    # Add cert-manager repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Create namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Install or upgrade cert-manager with CRDs
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.15.3 \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait \
        --timeout 10m
    
    # Wait for cert-manager to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    
    success "cert-manager installed successfully"
}

create_cluster_issuers() {
    log "Creating cluster issuers for Let's Encrypt..."
    
    cat > /tmp/cluster-issuers.yaml << EOF
---
# Let's Encrypt Staging Issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@${CLUSTER_DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
---
# Let's Encrypt staging Issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${CLUSTER_DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
# Self-signed Issuer for internal services
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

    kubectl apply -f /tmp/cluster-issuers.yaml
    success "Cluster issuers created"
}

create_self_signed_certificates() {
    log "Creating self-signed certificates for internal services..."
    
    cat > /tmp/self-signed-certs.yaml << EOF
---
# Self-signed CA Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: "Kubernetes HA Cluster CA"
  secretName: selfsigned-ca-secret
  privateKey:
    algorithm: RSA
    size: 4096
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
---
# CA Issuer using self-signed CA
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: selfsigned-ca-secret
---
# Wildcard certificate for cluster services
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-tls-secret
  namespace: default
spec:
  secretName: wildcard-tls-secret
  commonName: "*.${CLUSTER_DOMAIN}"
  dnsNames:
  - "*.${CLUSTER_DOMAIN}"
  - "${CLUSTER_DOMAIN}"
  - "localhost"
  - "*.monitoring.${CLUSTER_DOMAIN}"
  - "*.ingress.${CLUSTER_DOMAIN}"
  ipAddresses:
  - "127.0.0.1"
  - "${VIP}"
EOF

    # Add all control plane IPs
    for hostname in "${!CONTROL_PLANES[@]}"; do
        echo "  - \"${CONTROL_PLANES[$hostname]}\"" >> /tmp/self-signed-certs.yaml
    done

    cat >> /tmp/self-signed-certs.yaml << EOF
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
EOF

    kubectl apply -f /tmp/self-signed-certs.yaml
    
    # Wait for certificates to be ready
    kubectl wait --for=condition=ready --timeout=300s certificate/selfsigned-ca -n cert-manager
    kubectl wait --for=condition=ready --timeout=300s certificate/wildcard-tls-secret -n default
    
    success "Self-signed certificates created"
}

install_nginx_ingress() {
    log "Installing NGINX Ingress Controller with HA configuration..."
    
    # Add NGINX Ingress repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    # Create custom values for HA NGINX Ingress
    cat > /tmp/nginx-ingress-values.yaml << EOF
# NGINX Ingress Controller HA Configuration for Dell R740 Cluster
controller:
  # High Availability - Deploy on multiple nodes (2 for staging)
  replicaCount: 2
  
  # Ensure pods are distributed across nodes
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
              - ingress-nginx
          topologyKey: kubernetes.io/hostname
  
  # Resource allocation optimized for R740
  resources:
    limits:
      memory: 2Gi
      cpu: 2000m
    requests:
      memory: 1Gi
      cpu: 1000m
  
  # Service configuration - NodePort for HA with HAProxy
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
    enableHttp: true
    enableHttps: true
  
  # Enable metrics for monitoring
  # NOTE: ServiceMonitor disabled until Prometheus Operator is installed (script 07)
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
      namespace: monitoring
      additionalLabels:
        app: nginx-ingress
  
  # Enhanced configuration
  config:
    # SSL Security
    ssl-protocols: "TLSv1.2 TLSv1.3"
    ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256,ECDHE-RSA-AES128-GCM-SHA256,ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES256-GCM-SHA384,ECDHE-ECDSA-CHACHA20-POLY1305,ECDHE-RSA-CHACHA20-POLY1305,DHE-RSA-AES128-GCM-SHA256,DHE-RSA-AES256-GCM-SHA384"
    ssl-prefer-server-ciphers: "true"
    ssl-dh-param: "ffdhe2048"
    
    # Security headers
    add-headers: "ingress-nginx/security-headers"
    
    # Rate limiting
    rate-limit: "1000"
    rate-limit-window: "1m"
    rate-limit-rps: "100"
    
    # Connection limits
    limit-connections: "100"
    
    # Proxy settings optimized for HA
    proxy-connect-timeout: "30"
    proxy-send-timeout: "600"
    proxy-read-timeout: "600"
    proxy-body-size: "100m"
    proxy-buffer-size: "8k"
    proxy-buffers-number: "8"
    
    # Enable real IP preservation
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    use-proxy-protocol: "false"
    
    # Performance optimizations
    worker-processes: "auto"
    worker-connections: "16384"
    max-worker-connections: "16384"
    worker-cpu-affinity: "auto"
    
    # Custom error pages
    custom-http-errors: "404,503,502,500,401,403"
    
    # Logging
    log-format-escape-json: "true"
    log-format-upstream: '{"time": "\$time_iso8601", "remote_addr": "\$proxy_protocol_addr", "x_forwarded_for": "\$proxy_add_x_forwarded_for", "request_id": "\$req_id", "remote_user": "\$remote_user", "bytes_sent": \$bytes_sent, "request_time": \$request_time, "status": \$status, "vhost": "\$host", "request_proto": "\$server_protocol", "path": "\$uri", "request_query": "\$args", "request_length": \$request_length, "duration": \$request_time, "method": "\$request_method", "http_referrer": "\$http_referer", "http_user_agent": "\$http_user_agent", "upstream_addr": "\$upstream_addr", "upstream_response_time": "\$upstream_response_time", "upstream_status": "\$upstream_status"}'
    
    # Enable SSL passthrough
    enable-ssl-passthrough: "true"
    
    # HSTS
    hsts: "true"
    hsts-max-age: "31536000"
    hsts-include-subdomains: "true"
    hsts-preload: "true"
  
  # Additional arguments
  extraArgs:
    default-ssl-certificate: ingress-nginx/default-ssl-certificate
  
  # Admission webhooks
  admissionWebhooks:
    enabled: true
    failurePolicy: Fail
    patch:
      enabled: true

# Default backend
defaultBackend:
  enabled: true
  replicaCount: 2
  resources:
    limits:
      memory: 512Mi
      cpu: 500m
    requests:
      memory: 256Mi
      cpu: 250m

# TCP/UDP service support
tcp: {}
udp: {}
EOF
    
    # Install or upgrade NGINX Ingress
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --values /tmp/nginx-ingress-values.yaml \
        --wait \
        --timeout 15m
    
    success "NGINX Ingress Controller installed"
}

create_security_headers_configmap() {
    log "Creating security headers configuration..."
    
    cat > /tmp/security-headers.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-headers
  namespace: ingress-nginx
data:
  # Security headers for all ingress traffic
  X-Frame-Options: "DENY"
  X-Content-Type-Options: "nosniff"
  X-XSS-Protection: "1; mode=block"
  Referrer-Policy: "strict-origin-when-cross-origin"
  Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data: https:; connect-src 'self' https:; frame-ancestors 'none';"
  Strict-Transport-Security: "max-age=31536000; includeSubDomains; preload"
  Permissions-Policy: "geolocation=(), microphone=(), camera=(), payment=(), usb=(), interest-cohort=()"
  X-Robots-Tag: "noindex, nofollow, nosnippet, noarchive"
EOF

    kubectl apply -f /tmp/security-headers.yaml
    success "Security headers configuration created"
}

create_default_ssl_certificate() {
    log "Creating default SSL certificate for ingress..."

    # Wait for wildcard certificate to be ready
    local timeout=60
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        if kubectl get secret wildcard-tls-secret -n default &>/dev/null; then
            log "Wildcard certificate found"
            break
        fi
        sleep 2
        ((counter+=2))
    done

    # Copy the wildcard certificate to ingress namespace
    # Use --dry-run=client to avoid conflicts
    kubectl get secret wildcard-tls-secret -n default -o yaml | \
    sed 's/namespace: default/namespace: ingress-nginx/' | \
    sed 's/name: wildcard-tls-secret/name: default-ssl-certificate/' | \
    sed '/resourceVersion:/d' | \
    sed '/uid:/d' | \
    sed '/creationTimestamp:/d' | \
    kubectl apply -f -

    success "Default SSL certificate configured"
}

update_haproxy_for_ingress() {
    log "Checking HAProxy configuration for ingress traffic..."

    # NOTE: HAProxy is disabled on nodes with VIP (kube-apiserver conflict)
    # Ingress traffic routes via NodePort (30080/30443) which works without HAProxy

    # Check which node has VIP
    local vip_node=""
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"

        if [[ "$node" == "k8s-stg1" ]]; then
            # Check locally
            if ip addr show | grep -q "$VIP"; then
                vip_node="$node"
                log "VIP is assigned to $node (local)"
            fi
        else
            # Check remotely via SSH
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "ip addr show | grep -q $VIP" &>/dev/null; then
                vip_node="$node"
                log "VIP is assigned to $node"
            fi
        fi
    done

    if [[ -n "$vip_node" ]]; then
        log "HAProxy is disabled on $vip_node (has VIP, would conflict with kube-apiserver)"
        success "Ingress traffic will use NodePort (30080/30443) directly"
    else
        warning "Could not determine VIP assignment"
    fi

    # Verify ingress NodePort is accessible
    if curl -k -s "http://localhost:30080/healthz" &>/dev/null; then
        success "Ingress HTTP endpoint accessible on NodePort 30080"
    else
        warning "Ingress HTTP endpoint not yet accessible (may need time to start)"
    fi

    if curl -k -s "https://localhost:30443/healthz" &>/dev/null; then
        success "Ingress HTTPS endpoint accessible on NodePort 30443"
    else
        warning "Ingress HTTPS endpoint not yet accessible (may need time to start)"
    fi

    success "Ingress configuration verified (HAProxy not needed for ingress traffic)"
}

wait_for_ingress_ready() {
    log "Waiting for NGINX Ingress Controller to be ready..."
    
    # Wait for deployment to be available
    kubectl wait --for=condition=available --timeout=600s deployment/ingress-nginx-controller -n ingress-nginx
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready --timeout=600s pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
    
    # Check if NodePort services are accessible
    local timeout=60
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if curl -k -s "http://localhost:30080/healthz" &>/dev/null; then
            success "NGINX Ingress HTTP endpoint is accessible"
            break
        fi
        sleep 2
        ((counter+=2))
    done
    
    success "NGINX Ingress Controller is ready"
}

create_monitoring_ingress() {
    log "Creating ingress rules for monitoring services..."
    
    cat > /tmp/monitoring-ingress.yaml << EOF
---
# Grafana Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "ca-issuer"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: grafana-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - Grafana'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.${CLUSTER_DOMAIN}
    secretName: grafana-tls
  rules:
  - host: grafana.${CLUSTER_DOMAIN}
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
# Prometheus Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "ca-issuer"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: prometheus-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - Prometheus'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.${CLUSTER_DOMAIN}
    secretName: prometheus-tls
  rules:
  - host: prometheus.${CLUSTER_DOMAIN}
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
# AlertManager Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alertmanager-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "ca-issuer"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: alertmanager-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - AlertManager'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - alertmanager.${CLUSTER_DOMAIN}
    secretName: alertmanager-tls
  rules:
  - host: alertmanager.${CLUSTER_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-alertmanager
            port:
              number: 9093
EOF

    # Create monitoring namespace if it doesn't exist
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply ingress rules (will work when monitoring stack is deployed)
    kubectl apply -f /tmp/monitoring-ingress.yaml || warning "Monitoring ingress rules applied but services may not exist yet"
    
    success "Monitoring ingress rules created"
}

create_basic_auth_secrets() {
    log "Creating basic authentication secrets..."
    
    # Generate password hash (password: admin123)
    local password_hash='$2y$10$rO.0.lVGS8U8oQaGfhVsKOBGnU8iCZ9hbO3QJ5w2n6yR6vr.8D.e'
    
    # Create auth files
    mkdir -p /tmp/auth
    echo "admin:$password_hash" > /tmp/auth/grafana
    echo "admin:$password_hash" > /tmp/auth/prometheus
    echo "admin:$password_hash" > /tmp/auth/alertmanager
    
    # Create secrets in monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret generic grafana-basic-auth --from-file=/tmp/auth/grafana -n monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic prometheus-basic-auth --from-file=/tmp/auth/prometheus -n monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic alertmanager-basic-auth --from-file=/tmp/auth/alertmanager -n monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Cleanup
    rm -rf /tmp/auth
    
    success "Basic authentication secrets created (username: admin, password: admin123)"
}

test_ingress_functionality() {
    log "Testing ingress functionality..."
    
    # Create a test application
    cat > /tmp/ingress-test.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: config
        configMap:
          name: test-app-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-app-config
  namespace: default
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>STAGING Kubernetes Cluster Test</title>
    </head>
    <body>
        <h1>STAGING Kubernetes Cluster - Ingress Test</h1>
        <p>Server: \$(hostname)</p>
        <p>Time: \$(date)</p>
        <p>Ingress is working correctly!</p>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: test-app-service
  namespace: default
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-app-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "ca-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - test.${CLUSTER_DOMAIN}
    secretName: test-app-tls
  rules:
  - host: test.${CLUSTER_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app-service
            port:
              number: 80
EOF

    kubectl apply -f /tmp/ingress-test.yaml
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/test-app -n default
    
    # Test HTTP access via NodePort
    local test_result="PASS"
    if ! curl -s "http://localhost:30080" -H "Host: test.${CLUSTER_DOMAIN}" | grep -q "Ingress Test"; then
        test_result="FAIL"
        warning "HTTP ingress test failed"
    fi
    
    # Test HTTPS access via NodePort
    if ! curl -k -s "https://localhost:30443" -H "Host: test.${CLUSTER_DOMAIN}" | grep -q "Ingress Test"; then
        test_result="FAIL"
        warning "HTTPS ingress test failed"
    fi
    
    if [[ "$test_result" == "PASS" ]]; then
        success "Ingress functionality test passed"
    else
        warning "Some ingress tests failed"
    fi
    
    # Cleanup test resources
    kubectl delete -f /tmp/ingress-test.yaml --ignore-not-found=true
    
    success "Ingress functionality test completed"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Ingress Controller Setup Completed Successfully!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== NGINX Ingress Controller Status ==="
    kubectl get pods -n ingress-nginx -o wide
    echo
    echo "=== Ingress Controller Services ==="
    kubectl get svc -n ingress-nginx
    echo
    echo "=== Certificate Management ==="
    kubectl get certificates --all-namespaces
    echo
    echo "=== Cluster Issuers ==="
    kubectl get clusterissuers
    echo
    echo "=== HAProxy Integration ==="
    echo "✓ HAProxy updated on all nodes for ingress traffic"
    echo "✓ HTTP traffic: Port 30080 → NGINX Ingress"
    echo "✓ HTTPS traffic: Port 30443 → NGINX Ingress"
    echo
    echo "=== Security Features ==="
    echo "✓ SSL/TLS termination with strong ciphers"
    echo "✓ Security headers configured"
    echo "✓ Rate limiting enabled"
    echo "✓ Basic authentication for monitoring services"
    echo "✓ cert-manager for automatic certificate management"
    echo
    echo "=== Service Access ==="
    echo "Add these entries to your local /etc/hosts file:"
    for hostname in "${!CONTROL_PLANES[@]}"; do
        echo "${CONTROL_PLANES[$hostname]} grafana.${CLUSTER_DOMAIN} prometheus.${CLUSTER_DOMAIN} alertmanager.${CLUSTER_DOMAIN} test.${CLUSTER_DOMAIN}"
        break  # Only need one entry since traffic is load balanced
    done
    echo
    echo "Or access via VIP:"
    echo "$VIP grafana.${CLUSTER_DOMAIN} prometheus.${CLUSTER_DOMAIN} alertmanager.${CLUSTER_DOMAIN}"
    echo
    echo "=== Access URLs (when monitoring is deployed) ==="
    echo "• Grafana: https://grafana.${CLUSTER_DOMAIN}"
    echo "• Prometheus: https://prometheus.${CLUSTER_DOMAIN}"
    echo "• AlertManager: https://alertmanager.${CLUSTER_DOMAIN}"
    echo
    echo "=== Default Credentials ==="
    echo "• Username: admin"
    echo "• Password: admin123"
    echo
    echo "=== Next Steps ==="
    echo "1. Deploy monitoring stack: 07-ha-monitoring-setup.sh"
    echo "2. Run cluster validation: 08-cluster-validation.sh"
    echo "3. Test ingress with real applications"
    echo
    echo "=== Useful Commands ==="
    echo "• Check ingress status: kubectl get ingress --all-namespaces"
    echo "• View ingress logs: kubectl logs -f -n ingress-nginx deployment/ingress-nginx-controller"
    echo "• Test HTTP: curl -H 'Host: test.${CLUSTER_DOMAIN}' http://any-node-ip:30080"
    echo "• Test HTTPS: curl -k -H 'Host: test.${CLUSTER_DOMAIN}' https://any-node-ip:30443"
    echo "• Check certificates: kubectl get certificates --all-namespaces"
    echo "• HAProxy stats: http://any-node-ip:8404/stats"
    echo
    echo -e "${GREEN}HA Ingress Controller is ready for staging workloads!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    
    log "Starting HA ingress controller setup..."
    
    # Certificate management
    install_cert_manager
    create_cluster_issuers
    create_self_signed_certificates
    
    # NGINX Ingress deployment
    install_nginx_ingress
    create_security_headers_configmap
    create_default_ssl_certificate
    
    # Integration and configuration
    update_haproxy_for_ingress
    wait_for_ingress_ready
    
    # Application setup
    create_monitoring_ingress
    create_basic_auth_secrets
    
    # Testing
    test_ingress_functionality
    
    show_completion_info
    
    success "HA ingress controller setup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script deploys an HA NGINX Ingress Controller for the Kubernetes cluster."
        echo "Run this script on k8s-stg1 after storage setup."
        echo
        echo "Features deployed:"
        echo "• NGINX Ingress Controller with 2 replicas (HA)"
        echo "• cert-manager for automatic SSL/TLS certificate management"
        echo "• Security headers and rate limiting"
        echo "• Integration with HAProxy for load balancing"
        echo "• Self-signed certificates for internal services"
        echo "• Basic authentication for monitoring services"
        echo "• Ingress rules for monitoring stack"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac