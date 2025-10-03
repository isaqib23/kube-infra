#!/bin/bash

# Kubernetes Dashboard Installation Script
# For production-ready dashboard with RBAC

set -euo pipefail

LOG_FILE="/var/log/k8s-dashboard.log"
DASHBOARD_VERSION="v7.13.0"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster"
    fi
    
    log "kubectl connectivity verified ✓"
}

install_dashboard() {
    log "Installing Kubernetes Dashboard with Helm..."
    
    # Add Kubernetes Dashboard Helm repository
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm repo update
    
    # Install dashboard using Helm with custom values
    cat > dashboard-values.yaml << EOF
# Kubernetes Dashboard Configuration
app:
  mode: dashboard
  
# Configure ingress
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: k8s-dashboard.local
      paths:
        - path: /
          pathType: Prefix
  
# Configure service
service:
  type: ClusterIP
  
# Security context
securityContext:
  runAsUser: 1001
  runAsGroup: 2001
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  
# Resource limits
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 256Mi

# Enable metrics
metricsScraper:
  enabled: true
EOF
    
    helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --create-namespace \
        --values dashboard-values.yaml \
        --wait \
        --timeout 10m
    
    log "Dashboard installed ✓"
}

create_admin_user() {
    log "Creating dashboard admin user..."
    
    # Create service account
    cat > dashboard-admin-user.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
    
    kubectl apply -f dashboard-admin-user.yaml
    log "Admin user created ✓"
}

create_readonly_user() {
    log "Creating dashboard readonly user..."
    
    # Create readonly service account
    cat > dashboard-readonly-user.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: readonly-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: readonly-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: readonly-user
  namespace: kubernetes-dashboard
EOF
    
    kubectl apply -f dashboard-readonly-user.yaml
    log "Readonly user created ✓"
}

get_tokens() {
    log "Generating access tokens..."
    
    echo
    echo "=== Dashboard Access Information ==="
    echo
    
    # Get admin token
    echo "Admin Token:"
    kubectl -n kubernetes-dashboard create token admin-user
    echo
    
    # Get readonly token
    echo "Readonly Token:"
    kubectl -n kubernetes-dashboard create token readonly-user
    echo
}

create_ingress() {
    log "Creating ingress for dashboard..."
    
    cat > dashboard-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/secure-backends: "true"
spec:
  ingressClassName: nginx
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
    
    kubectl apply -f dashboard-ingress.yaml
    log "Dashboard ingress created ✓"
}

show_access_info() {
    echo
    echo "=== Kubernetes Dashboard Access Methods ==="
    echo
    echo "1. Port Forward (Recommended for testing):"
    echo "   kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443"
    echo "   Then access: https://localhost:8443"
    echo
    echo "2. NodePort (if configured):"
    local nodeport=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "Not configured")
    if [[ "$nodeport" != "Not configured" ]]; then
        local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        echo "   https://${node_ip}:${nodeport}"
    else
        echo "   NodePort not configured"
    fi
    echo
    echo "3. Ingress (if NGINX Ingress is installed):"
    echo "   Add to /etc/hosts: <node-ip> k8s-dashboard.local"
    echo "   Then access: https://k8s-dashboard.local"
    echo
    echo "=== Security Notes ==="
    echo "- Use admin token only for administrative tasks"
    echo "- Use readonly token for monitoring/viewing"
    echo "- Consider setting up proper SSL certificates for production"
    echo "- Restrict network access to dashboard in production"
    echo
}

wait_for_dashboard() {
    log "Waiting for dashboard to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard -n kubernetes-dashboard
    log "Dashboard is ready ✓"
}

main() {
    log "Starting Kubernetes Dashboard installation..."
    
    check_kubectl
    install_dashboard
    wait_for_dashboard
    create_admin_user
    create_readonly_user
    create_ingress
    
    get_tokens
    show_access_info
    
    log "Kubernetes Dashboard installation completed!"
}

main "$@"