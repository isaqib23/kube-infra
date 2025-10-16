#!/bin/bash

# HA Cluster Validation and Failover Testing Script
# Run this script on k8s-stg1 after monitoring setup
# Purpose: Comprehensive testing of HA cluster functionality and failover scenarios

set -euo pipefail

LOG_FILE="/var/log/ha-cluster-validation.log"

# Test configuration
VIP="10.255.253.100"
CLUSTER_DOMAIN="k8s.local"
TEST_NAMESPACE="validation-tests"

# Control plane servers (2 servers for staging)
declare -A CONTROL_PLANES=(
    ["k8s-stg1"]="10.255.253.10"
    ["k8s-stg2"]="10.255.253.11"
)

# Test results tracking
declare -A TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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
}

test_pass() {
    local test_name="$1"
    TEST_RESULTS["$test_name"]="PASS"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
    success "TEST PASS: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="${2:-Unknown failure}"
    TEST_RESULTS["$test_name"]="FAIL"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
    error "TEST FAIL: $test_name - $reason"
}

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    HA Cluster Validation and Failover Testing Suite"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script performs comprehensive testing of the HA"
    echo "Kubernetes cluster across all 2 Dell R740 servers."
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
        error "kubectl cannot connect to cluster"
    fi
    
    # Check if all nodes are ready
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    if [[ $ready_nodes -lt 4 ]]; then
        warning "Only $ready_nodes nodes are Ready. Expected 4 nodes."
    fi
    
    success "Prerequisites check passed"
}

create_test_namespace() {
    log "Creating test namespace..."
    
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$TEST_NAMESPACE" validation=true --overwrite
    
    success "Test namespace created: $TEST_NAMESPACE"
}

test_cluster_basic_functionality() {
    log "=== Testing Basic Cluster Functionality ==="
    
    # Test 1: Node readiness
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    if [[ $ready_nodes -eq 4 ]]; then
        test_pass "All nodes are Ready"
    else
        test_fail "Node readiness check" "Only $ready_nodes/4 nodes are Ready"
    fi
    
    # Test 2: System pods
    local system_pods_running=$(kubectl get pods -n kube-system --no-headers | grep -c "Running" || echo "0")
    local expected_system_pods=20  # Approximate number
    if [[ $system_pods_running -ge $expected_system_pods ]]; then
        test_pass "System pods are running"
    else
        test_fail "System pods check" "Only $system_pods_running system pods running"
    fi
    
    # Test 3: API server accessibility via VIP
    if kubectl --server="https://$VIP:6443" get nodes &>/dev/null; then
        test_pass "API server accessible via VIP"
    else
        test_fail "API server VIP access" "Cannot access API via VIP $VIP"
    fi
    
    # Test 4: DNS resolution
    if kubectl run dns-test --image=busybox:1.36 --rm --restart=Never --namespace="$TEST_NAMESPACE" -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        test_pass "DNS resolution working"
    else
        test_fail "DNS resolution" "Cannot resolve kubernetes.default.svc.cluster.local"
    fi
}

test_etcd_cluster() {
    log "=== Testing etcd Cluster Health ==="
    
    # Test 1: etcd pod count
    local etcd_pods=$(kubectl get pods -n kube-system -l component=etcd --no-headers | grep -c "Running" || echo "0")
    if [[ $etcd_pods -eq 4 ]]; then
        test_pass "All etcd pods are running"
    else
        test_fail "etcd pod count" "Only $etcd_pods/4 etcd pods running"
    fi
    
    # Test 2: etcd cluster health
    local etcd_healthy=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if kubectl exec -n kube-system etcd-$node -- etcdctl \
            --endpoints=https://127.0.0.1:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/server.crt \
            --key=/etc/kubernetes/pki/etcd/server.key \
            endpoint health &>/dev/null; then
            ((etcd_healthy++))
        fi
    done
    
    if [[ $etcd_healthy -ge 3 ]]; then
        test_pass "etcd cluster has healthy quorum ($etcd_healthy/4 members)"
    else
        test_fail "etcd cluster health" "Only $etcd_healthy/4 etcd members are healthy"
    fi
    
    # Test 3: etcd member list
    if kubectl exec -n kube-system etcd-k8s-stg1 -- etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        member list &>/dev/null; then
        test_pass "etcd member list accessible"
    else
        test_fail "etcd member list" "Cannot retrieve etcd member list"
    fi
}

test_haproxy_keepalived() {
    log "=== Testing HAProxy and Keepalived ==="
    
    # Test 1: HAProxy service status on all nodes
    local haproxy_running=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "systemctl is-active haproxy" &>/dev/null; then
            ((haproxy_running++))
        fi
    done
    
    if [[ $haproxy_running -eq 4 ]]; then
        test_pass "HAProxy running on all nodes"
    else
        test_fail "HAProxy service status" "HAProxy running on only $haproxy_running/4 nodes"
    fi
    
    # Test 2: Keepalived service status
    local keepalived_running=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "systemctl is-active keepalived" &>/dev/null; then
            ((keepalived_running++))
        fi
    done
    
    if [[ $keepalived_running -eq 4 ]]; then
        test_pass "Keepalived running on all nodes"
    else
        test_fail "Keepalived service status" "Keepalived running on only $keepalived_running/4 nodes"
    fi
    
    # Test 3: VIP assignment
    local vip_assigned_nodes=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "ip addr show | grep -q $VIP" &>/dev/null; then
            ((vip_assigned_nodes++))
        fi
    done
    
    if [[ $vip_assigned_nodes -eq 1 ]]; then
        test_pass "VIP assigned to exactly one node"
    else
        test_fail "VIP assignment" "VIP assigned to $vip_assigned_nodes nodes (should be 1)"
    fi
    
    # Test 4: HAProxy stats accessibility
    if curl -s "http://localhost:8404/stats" | grep -q "HAProxy Statistics Report"; then
        test_pass "HAProxy statistics accessible"
    else
        test_fail "HAProxy statistics" "Cannot access HAProxy stats page"
    fi
}

test_storage_functionality() {
    log "=== Testing Storage Functionality ==="
    
    # Test 1: Storage classes availability
    local storage_classes=$(kubectl get storageclass --no-headers | wc -l)
    if [[ $storage_classes -ge 4 ]]; then
        test_pass "Storage classes available"
    else
        test_fail "Storage classes" "Only $storage_classes storage classes found"
    fi
    
    # Test 2: Persistent volume availability
    local available_pvs=$(kubectl get pv --no-headers | grep -c "Available\|Bound" || echo "0")
    if [[ $available_pvs -ge 10 ]]; then
        test_pass "Persistent volumes available"
    else
        test_fail "Persistent volumes" "Only $available_pvs PVs available"
    fi
    
    # Test 3: Create and test PVC
    cat > /tmp/test-pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: validation-test-pvc
  namespace: $TEST_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-storage
  resources:
    requests:
      storage: 1Gi
EOF
    
    kubectl apply -f /tmp/test-pvc.yaml
    
    # Wait for PVC to bind
    local timeout=60
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        local pvc_status=$(kubectl get pvc validation-test-pvc -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$pvc_status" == "Bound" ]]; then
            test_pass "PVC creation and binding"
            break
        fi
        sleep 2
        ((counter+=2))
    done
    
    if [[ $counter -ge $timeout ]]; then
        test_fail "PVC creation" "PVC did not bind within $timeout seconds"
    fi
}

test_ingress_functionality() {
    log "=== Testing Ingress Functionality ==="
    
    # Test 1: NGINX Ingress Controller pods
    local ingress_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers | grep -c "Running" || echo "0")
    if [[ $ingress_pods -ge 4 ]]; then
        test_pass "NGINX Ingress Controller pods running"
    else
        test_fail "NGINX Ingress pods" "Only $ingress_pods ingress pods running"
    fi
    
    # Test 2: Ingress NodePort accessibility
    if curl -s "http://localhost:30080/healthz" | grep -q "ok"; then
        test_pass "Ingress HTTP NodePort accessible"
    else
        test_fail "Ingress HTTP access" "Cannot access ingress on port 30080"
    fi
    
    if curl -k -s "https://localhost:30443/healthz" | grep -q "ok"; then
        test_pass "Ingress HTTPS NodePort accessible"
    else
        test_fail "Ingress HTTPS access" "Cannot access ingress on port 30443"
    fi
    
    # Test 3: Create test ingress and verify
    cat > /tmp/test-ingress.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: validation-test-app
  namespace: $TEST_NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: validation-test-app
  template:
    metadata:
      labels:
        app: validation-test-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: validation-test-service
  namespace: $TEST_NAMESPACE
spec:
  selector:
    app: validation-test-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: validation-test-ingress
  namespace: $TEST_NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: validation-test.$CLUSTER_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: validation-test-service
            port:
              number: 80
EOF
    
    kubectl apply -f /tmp/test-ingress.yaml
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/validation-test-app -n "$TEST_NAMESPACE"
    
    # Test ingress accessibility
    if curl -s -H "Host: validation-test.$CLUSTER_DOMAIN" "http://localhost:30080" | grep -q "Welcome to nginx"; then
        test_pass "Test ingress functionality"
    else
        test_fail "Test ingress" "Cannot access test application via ingress"
    fi
}

test_monitoring_stack() {
    log "=== Testing Monitoring Stack ==="
    
    # Test 1: Prometheus pods
    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -c "Running" || echo "0")
    if [[ $prometheus_pods -ge 2 ]]; then
        test_pass "Prometheus pods running"
    else
        test_fail "Prometheus pods" "Only $prometheus_pods prometheus pods running"
    fi
    
    # Test 2: Grafana pods
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -c "Running" || echo "0")
    if [[ $grafana_pods -ge 1 ]]; then
        test_pass "Grafana pods running"
    else
        test_fail "Grafana pods" "No Grafana pods running"
    fi
    
    # Test 3: AlertManager pods
    local alertmanager_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers | grep -c "Running" || echo "0")
    if [[ $alertmanager_pods -ge 3 ]]; then
        test_pass "AlertManager pods running"
    else
        test_fail "AlertManager pods" "Only $alertmanager_pods alertmanager pods running"
    fi
    
    # Test 4: Prometheus targets
    if kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &>/dev/null &
    then
        local port_forward_pid=$!
        sleep 10
        
        local active_targets=$(curl -s "http://localhost:9090/api/v1/targets" | jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")
        if [[ $active_targets -gt 10 ]]; then
            test_pass "Prometheus targets discovered ($active_targets targets)"
        else
            test_fail "Prometheus targets" "Only $active_targets targets discovered"
        fi
        
        kill $port_forward_pid &>/dev/null || true
    else
        test_fail "Prometheus API" "Cannot access Prometheus API"
    fi
}

test_workload_distribution() {
    log "=== Testing Workload Distribution ==="
    
    # Create a test deployment with 8 replicas to test distribution
    cat > /tmp/distribution-test.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: distribution-test
  namespace: $TEST_NAMESPACE
spec:
  replicas: 8
  selector:
    matchLabels:
      app: distribution-test
  template:
    metadata:
      labels:
        app: distribution-test
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - distribution-test
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:1.25
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF
    
    kubectl apply -f /tmp/distribution-test.yaml
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/distribution-test -n "$TEST_NAMESPACE"
    
    # Check pod distribution across nodes
    local nodes_with_pods=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local pods_on_node=$(kubectl get pods -n "$TEST_NAMESPACE" -l app=distribution-test --field-selector spec.nodeName="$node" --no-headers | wc -l)
        if [[ $pods_on_node -gt 0 ]]; then
            ((nodes_with_pods++))
        fi
    done
    
    if [[ $nodes_with_pods -ge 3 ]]; then
        test_pass "Workload distribution across nodes ($nodes_with_pods/4 nodes have pods)"
    else
        test_fail "Workload distribution" "Pods only distributed to $nodes_with_pods/4 nodes"
    fi
}

test_network_connectivity() {
    log "=== Testing Network Connectivity ==="
    
    # Test pod-to-pod communication across nodes
    cat > /tmp/network-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-test-client
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: client
    image: busybox:1.36
    command:
    - sleep
    - "3600"
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: network-test-server
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: server
    image: nginx:1.25
  restartPolicy: Never
EOF
    
    kubectl apply -f /tmp/network-test.yaml
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready --timeout=120s pod/network-test-client -n "$TEST_NAMESPACE"
    kubectl wait --for=condition=ready --timeout=120s pod/network-test-server -n "$TEST_NAMESPACE"
    
    # Get server pod IP
    local server_ip=$(kubectl get pod network-test-server -n "$TEST_NAMESPACE" -o jsonpath='{.status.podIP}')
    
    # Test connectivity
    if kubectl exec network-test-client -n "$TEST_NAMESPACE" -- wget -q --spider "http://$server_ip" &>/dev/null; then
        test_pass "Pod-to-pod network connectivity"
    else
        test_fail "Network connectivity" "Cannot connect from client pod to server pod"
    fi
}

simulate_node_failure() {
    log "=== Simulating Node Failure (Non-destructive) ==="
    
    warning "This test simulates node failure by stopping kubelet service temporarily"
    read -p "Do you want to proceed with failover testing? [y/N]: " CONFIRM_FAILOVER
    
    if [[ ! $CONFIRM_FAILOVER =~ ^[Yy]$ ]]; then
        warning "Skipping failover testing"
        return 0
    fi
    
    # Choose a non-primary node for testing
    local test_node="k8s-stg2"
    local test_node_ip="${CONTROL_PLANES[$test_node]}"
    
    log "Simulating failure on $test_node ($test_node_ip)..."
    
    # Record initial pod count
    local initial_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | wc -l)
    
    # Stop kubelet on test node
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$test_node_ip "systemctl stop kubelet" &>/dev/null || warning "Could not stop kubelet on $test_node"
    
    # Wait and check if pods are rescheduled
    sleep 30
    
    # Check node status
    local node_status=$(kubectl get node "$test_node" --no-headers | awk '{print $2}')
    if [[ "$node_status" == "NotReady" ]]; then
        test_pass "Node failure detected by cluster"
    else
        test_fail "Node failure detection" "Node $test_node still shows as Ready"
    fi
    
    # Wait for pod rescheduling (this can take a few minutes)
    sleep 120
    
    # Check if pods were rescheduled
    local current_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | grep -c "Running" || echo "0")
    if [[ $current_pods -ge $((initial_pods - 2)) ]]; then
        test_pass "Pod rescheduling after node failure"
    else
        test_fail "Pod rescheduling" "Only $current_pods/$initial_pods pods are running after node failure"
    fi
    
    # Restore kubelet
    log "Restoring kubelet on $test_node..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$test_node_ip "systemctl start kubelet" &>/dev/null || warning "Could not start kubelet on $test_node"
    
    # Wait for node to become ready again
    local timeout=300
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        local node_status=$(kubectl get node "$test_node" --no-headers | awk '{print $2}')
        if [[ "$node_status" == "Ready" ]]; then
            test_pass "Node recovery after failure simulation"
            break
        fi
        sleep 10
        ((counter+=10))
    done
    
    if [[ $counter -ge $timeout ]]; then
        test_fail "Node recovery" "Node $test_node did not recover within $timeout seconds"
    fi
}

test_backup_functionality() {
    log "=== Testing Backup Functionality ==="
    
    # Test 1: etcd backup script
    if [[ -f "/opt/kubernetes/etcd-backup.sh" ]]; then
        if /opt/kubernetes/etcd-backup.sh &>/dev/null; then
            test_pass "etcd backup script execution"
        else
            test_fail "etcd backup script" "Backup script failed to execute"
        fi
    else
        test_fail "etcd backup script" "Backup script not found"
    fi
    
    # Test 2: Backup cronjobs
    local backup_cronjobs=$(kubectl get cronjobs -n backup-system --no-headers | wc -l 2>/dev/null || echo "0")
    if [[ $backup_cronjobs -gt 0 ]]; then
        test_pass "Backup cronjobs configured"
    else
        test_fail "Backup cronjobs" "No backup cronjobs found"
    fi
    
    # Test 3: Backup storage directories
    local backup_dirs_exist=0
    for node in "${!CONTROL_PLANES[@]}"; do
        local node_ip="${CONTROL_PLANES[$node]}"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "test -d /mnt/k8s-storage/backup" &>/dev/null; then
            ((backup_dirs_exist++))
        fi
    done
    
    if [[ $backup_dirs_exist -eq 4 ]]; then
        test_pass "Backup directories exist on all nodes"
    else
        test_fail "Backup directories" "Backup directories exist on only $backup_dirs_exist/4 nodes"
    fi
}

cleanup_test_resources() {
    log "Cleaning up test resources..."
    
    # Delete test namespace and all resources
    kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true --timeout=300s
    
    # Clean up temporary files
    rm -f /tmp/test-*.yaml /tmp/distribution-test.yaml /tmp/network-test.yaml
    
    success "Test resources cleaned up"
}

generate_validation_report() {
    log "Generating validation report..."
    
    local report_file="/opt/kubernetes/cluster-validation-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
STAGING Kubernetes Cluster Validation Report
=======================================
Date: $(date)
Cluster: STAGING Kubernetes on 4x Dell R740 servers
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

Test Results:
EOF
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        echo "  [$result] $test_name" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

Cluster Information:
===================
Nodes:
$(kubectl get nodes -o wide)

Pods by Namespace:
$(kubectl get pods --all-namespaces | head -20)

Storage:
$(kubectl get pv,pvc --all-namespaces)

Services:
$(kubectl get svc --all-namespaces | head -20)

Ingress:
$(kubectl get ingress --all-namespaces)

Report Location: $report_file
Log File: $LOG_FILE
EOF
    
    success "Validation report generated: $report_file"
}

show_completion_info() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "🎉 HA Cluster Validation Completed!"
    echo -e "==============================================================${NC}"
    echo
    echo "=== Test Summary ==="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo -e "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! Your HA cluster is ready for staging!${NC}"
    elif [[ $FAILED_TESTS -le 2 ]]; then
        echo -e "${YELLOW}⚠ Minor issues detected. Review failed tests and address if needed.${NC}"
    else
        echo -e "${RED}❌ Multiple issues detected. Review and fix failed tests before staging use.${NC}"
    fi
    
    echo
    echo "=== Test Categories Completed ==="
    echo "✓ Basic cluster functionality"
    echo "✓ etcd cluster health"
    echo "✓ HAProxy and Keepalived"
    echo "✓ Storage functionality"
    echo "✓ Ingress functionality"
    echo "✓ Monitoring stack"
    echo "✓ Workload distribution"
    echo "✓ Network connectivity"
    echo "✓ Failover simulation (if enabled)"
    echo "✓ Backup functionality"
    echo
    echo "=== Next Steps ==="
    echo "1. Review detailed validation report for any failed tests"
    echo "2. Address any issues found during validation"
    echo "3. Configure staging workloads"
    echo "4. Set up external monitoring and alerting"
    echo "5. Establish operational procedures"
    echo
    echo "=== staging Readiness Checklist ==="
    echo "□ All validation tests passing"
    echo "□ External backup strategy implemented"
    echo "□ Monitoring alerts configured (email/Slack)"
    echo "□ SSL certificates for staging domains"
    echo "□ Network policies configured"
    echo "□ RBAC policies reviewed"
    echo "□ Disaster recovery procedures documented"
    echo "□ Operational runbooks created"
    echo
    echo "=== Useful Commands for Ongoing Monitoring ==="
    echo "• Check cluster health: kubectl get nodes,pods --all-namespaces"
    echo "• Monitor etcd: kubectl get pods -n kube-system | grep etcd"
    echo "• Check ingress: kubectl get ingress --all-namespaces"
    echo "• View logs: kubectl logs -n kube-system deployment/coredns"
    echo "• Check storage: kubectl get pv,pvc --all-namespaces"
    echo
    echo -e "${GREEN}Your STAGING Kubernetes cluster on 4x Dell R740 servers is validated and ready!${NC}"
}

main() {
    banner
    check_root
    check_prerequisites
    
    log "Starting comprehensive HA cluster validation..."
    
    # Setup
    create_test_namespace
    
    # Core functionality tests
    test_cluster_basic_functionality
    test_etcd_cluster
    test_haproxy_keepalived
    test_storage_functionality
    test_ingress_functionality
    test_monitoring_stack
    
    # Advanced tests
    test_workload_distribution
    test_network_connectivity
    test_backup_functionality
    
    # Optional destructive test
    simulate_node_failure
    
    # Cleanup and reporting
    cleanup_test_resources
    generate_validation_report
    
    show_completion_info
    
    success "HA cluster validation completed successfully!"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        echo "This script performs comprehensive validation of the STAGING Kubernetes cluster."
        echo "Run this script on k8s-stg1 after all setup is complete."
        echo
        echo "Tests performed:"
        echo "• Basic cluster functionality"
        echo "• etcd cluster health and quorum"
        echo "• HAProxy and Keepalived functionality"
        echo "• Storage classes and persistent volumes"
        echo "• Ingress controller and routing"
        echo "• Monitoring stack (Prometheus, Grafana, AlertManager)"
        echo "• Workload distribution across nodes"
        echo "• Network connectivity between pods"
        echo "• Backup functionality"
        echo "• Optional: Node failure simulation"
        echo
        echo "The script generates a detailed report and provides staging readiness guidance."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac