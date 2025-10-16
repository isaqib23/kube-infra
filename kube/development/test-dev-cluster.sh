#!/bin/bash

# Test Script for DEVELOPMENT Single-Node Kubernetes Cluster
# This script validates all components of the k8s-dev1 cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

log() {
    echo -e "${BLUE}[TEST] $*${NC}"
}

success() {
    echo -e "${GREEN}✓ PASS: $*${NC}"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL: $*${NC}"
    ((FAILED++))
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $*${NC}"
    ((WARNINGS++))
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    DEVELOPMENT Kubernetes Cluster - Validation Tests"
    echo "    Single-Node Cluster (k8s-dev1)"
    echo "=============================================================="
    echo -e "${NC}"
}

section() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Test 1: Cluster connectivity
test_cluster_connectivity() {
    section "1. Cluster Connectivity"

    log "Testing cluster API server..."
    if kubectl cluster-info &>/dev/null; then
        success "Cluster API server is accessible"
        kubectl cluster-info
    else
        fail "Cannot connect to cluster API server"
    fi

    log "Checking node status..."
    NODE_STATUS=$(kubectl get nodes --no-headers | awk '{print $2}')
    if [[ "$NODE_STATUS" == "Ready" ]]; then
        success "Node is Ready"
    else
        fail "Node status is: $NODE_STATUS"
    fi

    log "Node details:"
    kubectl get nodes -o wide
}

# Test 2: System pods
test_system_pods() {
    section "2. System Pods (kube-system)"

    log "Checking kube-system pods..."

    # Get all pods in kube-system
    TOTAL_PODS=$(kubectl get pods -n kube-system --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers | wc -l)

    log "Total pods: $TOTAL_PODS, Running: $RUNNING_PODS"

    # Check critical components
    CRITICAL_COMPONENTS=(
        "kube-apiserver"
        "kube-controller-manager"
        "kube-scheduler"
        "etcd"
        "coredns"
        "calico-node"
        "calico-kube-controllers"
    )

    for component in "${CRITICAL_COMPONENTS[@]}"; do
        if kubectl get pods -n kube-system | grep -q "$component.*Running"; then
            success "$component is running"
        else
            fail "$component is NOT running"
        fi
    done

    log "All kube-system pods:"
    kubectl get pods -n kube-system
}

# Test 3: Networking (Calico)
test_networking() {
    section "3. Networking (Calico CNI)"

    log "Checking Calico installation..."
    if kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers | grep -q "Running"; then
        success "Calico node is running"
    else
        fail "Calico node is NOT running"
    fi

    if kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers --no-headers | grep -q "Running"; then
        success "Calico controller is running"
    else
        fail "Calico controller is NOT running"
    fi

    log "Checking CoreDNS..."
    COREDNS_COUNT=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers | wc -l)
    if [[ $COREDNS_COUNT -ge 1 ]]; then
        success "CoreDNS is running ($COREDNS_COUNT replicas)"
    else
        fail "CoreDNS is NOT running"
    fi
}

# Test 4: Storage
test_storage() {
    section "4. Storage Classes and Persistent Volumes"

    log "Checking storage classes..."
    SC_COUNT=$(kubectl get sc --no-headers | wc -l)
    if [[ $SC_COUNT -ge 1 ]]; then
        success "Storage classes available: $SC_COUNT"
        kubectl get sc
    else
        fail "No storage classes found"
    fi

    log "Checking persistent volumes..."
    PV_COUNT=$(kubectl get pv --no-headers | wc -l)
    if [[ $PV_COUNT -ge 1 ]]; then
        success "Persistent volumes available: $PV_COUNT"
        kubectl get pv
    else
        warning "No persistent volumes found (may not be created yet)"
    fi
}

# Test 5: Ingress Controller
test_ingress() {
    section "5. Ingress Controller (NGINX)"

    log "Checking ingress-nginx namespace..."
    if kubectl get namespace ingress-nginx &>/dev/null; then
        success "ingress-nginx namespace exists"

        log "Checking ingress controller pods..."
        if kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --field-selector=status.phase=Running --no-headers | grep -q "Running"; then
            success "Ingress controller is running"
        else
            fail "Ingress controller is NOT running"
        fi

        log "Ingress controller details:"
        kubectl get pods -n ingress-nginx
    else
        warning "ingress-nginx namespace not found (may not be installed yet)"
    fi

    log "Checking cert-manager..."
    if kubectl get namespace cert-manager &>/dev/null; then
        success "cert-manager namespace exists"

        CERTMGR_PODS=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running --no-headers | wc -l)
        if [[ $CERTMGR_PODS -ge 3 ]]; then
            success "cert-manager pods are running ($CERTMGR_PODS/3)"
        else
            fail "cert-manager pods not fully running ($CERTMGR_PODS/3)"
        fi
    else
        warning "cert-manager not found (may not be installed yet)"
    fi
}

# Test 6: Monitoring Stack
test_monitoring() {
    section "6. Monitoring Stack (Prometheus, Grafana, Loki)"

    log "Checking monitoring namespace..."
    if kubectl get namespace monitoring &>/dev/null; then
        success "monitoring namespace exists"

        # Check Prometheus
        log "Checking Prometheus..."
        if kubectl get pods -n monitoring | grep -q "prometheus.*Running"; then
            PROM_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep "Running" | awk '{if ($2 == "2/2") print "ready"; else print "not-ready"}')
            if [[ "$PROM_READY" == "ready" ]]; then
                success "Prometheus is running and ready"
            else
                warning "Prometheus is running but not all containers are ready"
            fi
        else
            fail "Prometheus is NOT running"
        fi

        # Check Grafana
        log "Checking Grafana..."
        if kubectl get pods -n monitoring | grep -q "grafana.*Running"; then
            success "Grafana is running"
        else
            fail "Grafana is NOT running"
        fi

        # Check Loki
        log "Checking Loki..."
        if kubectl get pods -n monitoring | grep -q "loki-0.*Running"; then
            LOKI_READY=$(kubectl get pod loki-0 -n monitoring --no-headers | awk '{if ($2 == "2/2") print "ready"; else print "not-ready"}')
            if [[ "$LOKI_READY" == "ready" ]]; then
                success "Loki is running and ready"
            else
                warning "Loki is running but not all containers are ready"
            fi
        else
            fail "Loki is NOT running"
        fi

        # Check Alertmanager
        log "Checking Alertmanager..."
        if kubectl get pods -n monitoring | grep -q "alertmanager.*Running"; then
            success "Alertmanager is running"
        else
            fail "Alertmanager is NOT running"
        fi

        log "All monitoring pods:"
        kubectl get pods -n monitoring
    else
        warning "monitoring namespace not found (may not be installed yet)"
    fi
}

# Test 7: DNS Resolution
test_dns() {
    section "7. DNS Resolution Test"

    log "Creating test pod for DNS resolution..."
    kubectl run dns-test --image=busybox:1.28 --restart=Never --rm -i --command -- nslookup kubernetes.default &>/dev/null && \
        success "DNS resolution works (kubernetes.default resolvable)" || \
        fail "DNS resolution failed"

    # Cleanup
    kubectl delete pod dns-test --ignore-not-found=true &>/dev/null
}

# Test 8: Pod Deployment Test
test_pod_deployment() {
    section "8. Pod Deployment Test"

    log "Deploying test nginx pod..."
    cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: test-nginx
  labels:
    app: test
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF

    log "Waiting for pod to be ready..."
    if kubectl wait --for=condition=Ready pod/test-nginx --timeout=60s &>/dev/null; then
        success "Test pod deployed successfully"
    else
        fail "Test pod failed to deploy"
    fi

    log "Cleaning up test pod..."
    kubectl delete pod test-nginx --ignore-not-found=true &>/dev/null
}

# Test 9: Service and Endpoint Test
test_service() {
    section "9. Service and Endpoint Test"

    log "Checking kubernetes service..."
    if kubectl get svc kubernetes &>/dev/null; then
        success "kubernetes service exists"

        ENDPOINTS=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')
        if [[ -n "$ENDPOINTS" ]]; then
            success "kubernetes service has endpoints: $ENDPOINTS"
        else
            fail "kubernetes service has no endpoints"
        fi
    else
        fail "kubernetes service not found"
    fi
}

# Test 10: Resource Usage
test_resources() {
    section "10. Resource Usage"

    log "Node resource usage:"
    kubectl top node 2>/dev/null || warning "Metrics server not available (kubectl top won't work)"

    log "Checking node capacity:"
    kubectl describe node | grep -A 5 "Capacity:"

    log "Checking node allocatable resources:"
    kubectl describe node | grep -A 5 "Allocatable:"
}

# Test 11: Component Health
test_component_health() {
    section "11. Component Health Status"

    log "Checking component statuses..."
    kubectl get --raw='/readyz?verbose' 2>/dev/null || warning "Unable to check component health"

    log "Checking etcd health..."
    ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd --no-headers | awk '{print $1}')
    if [[ -n "$ETCD_POD" ]]; then
        if kubectl exec -n kube-system "$ETCD_POD" -- etcdctl endpoint health 2>/dev/null | grep -q "healthy"; then
            success "etcd is healthy"
        else
            warning "Unable to verify etcd health"
        fi
    fi
}

# Test 12: Taint Check (Single-Node)
test_taints() {
    section "12. Node Taints (Single-Node Configuration)"

    log "Checking if control-plane taint is removed..."
    TAINTS=$(kubectl get nodes -o jsonpath='{.items[0].spec.taints}')
    if [[ -z "$TAINTS" ]] || [[ "$TAINTS" == "null" ]]; then
        success "Control-plane taint removed (workloads can be scheduled)"
    else
        warning "Node has taints: $TAINTS"
    fi
}

# Summary
show_summary() {
    echo
    echo -e "${BLUE}=============================================================="
    echo "                    TEST SUMMARY"
    echo -e "==============================================================${NC}"
    echo
    echo -e "${GREEN}Passed:   $PASSED${NC}"
    echo -e "${RED}Failed:   $FAILED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All critical tests passed! Cluster is healthy.${NC}"
        exit 0
    else
        echo -e "${RED}⚠️  Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Main execution
main() {
    banner

    test_cluster_connectivity
    test_system_pods
    test_networking
    test_storage
    test_ingress
    test_monitoring
    test_dns
    test_pod_deployment
    test_service
    test_resources
    test_component_health
    test_taints

    show_summary
}

# Run tests
main "$@"
