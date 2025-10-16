#!/bin/bash

# Server Failure and Data Accessibility Test Script
# Run this script on k8s-stg1 to test HA failover and data persistence
# Purpose: Validate that the cluster maintains data accessibility when a server fails

set -euo pipefail

LOG_FILE="/var/log/server-failure-test.log"

# Test configuration
TEST_NAMESPACE="failover-test"
TEST_SERVER="k8s-stg2"  # This is the server we'll shutdown
TEST_SERVER_IP="10.255.253.11"

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

banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "    Server Failure & Data Accessibility Test"
    echo "=============================================================="
    echo -e "${NC}"
    echo "This script tests HA cluster behavior when a server fails"
    echo "Test server: $TEST_SERVER ($TEST_SERVER_IP)"
    echo
    echo -e "${RED}WARNING: This test will shutdown $TEST_SERVER temporarily${NC}"
    echo -e "${RED}Make sure you can access the server console to power it back on${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

confirm_test() {
    echo -e "${YELLOW}This test will:${NC}"
    echo "1. Create test applications with persistent data"
    echo "2. Shutdown server $TEST_SERVER"
    echo "3. Verify pods reschedule to remaining 3 nodes"
    echo "4. Test data accessibility from rescheduled pods"
    echo "5. Provide instructions to restore the server"
    echo
    read -p "Do you want to proceed with this test? [y/N]: " CONFIRM

    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        log "Test cancelled by user"
        exit 0
    fi
}

create_test_namespace() {
    log "Creating test namespace..."
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$TEST_NAMESPACE" test=failover --overwrite
    success "Test namespace created: $TEST_NAMESPACE"
}

deploy_test_applications() {
    log "Deploying test applications with persistent storage..."

    # Application 1: StatefulSet with PVCs (will demonstrate local PV behavior)
    cat > /tmp/stateful-app.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: stateful-app
  namespace: failover-test
spec:
  clusterIP: None
  selector:
    app: stateful-app
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: stateful-app
  namespace: failover-test
spec:
  serviceName: stateful-app
  replicas: 4
  selector:
    matchLabels:
      app: stateful-app
  template:
    metadata:
      labels:
        app: stateful-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
        lifecycle:
          postStart:
            exec:
              command:
              - /bin/sh
              - -c
              - |
                echo "Pod: $(hostname) - Node: $(cat /etc/hostname) - Time: $(date)" > /usr/share/nginx/html/index.html
                echo "This data is stored on persistent volume" >> /usr/share/nginx/html/index.html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard-storage
      resources:
        requests:
          storage: 1Gi
EOF

    kubectl apply -f /tmp/stateful-app.yaml

    # Application 2: Deployment with shared storage (will demonstrate rescheduling)
    cat > /tmp/deployment-app.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
  namespace: failover-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-app
  namespace: failover-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: deployment-app
  template:
    metadata:
      labels:
        app: deployment-app
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "Starting pod $(hostname) on node $(cat /etc/hostname)" >> /data/activity.log
          while true; do
            echo "$(date): Pod $(hostname) is running" >> /data/activity.log
            sleep 30
          done
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: shared-data
---
apiVersion: v1
kind: Service
metadata:
  name: deployment-app
  namespace: failover-test
spec:
  selector:
    app: deployment-app
  ports:
  - port: 80
EOF

    kubectl apply -f /tmp/deployment-app.yaml

    log "Waiting for applications to be ready..."
    kubectl wait --for=condition=ready --timeout=300s pod -l app=stateful-app -n "$TEST_NAMESPACE"
    kubectl wait --for=condition=ready --timeout=300s pod -l app=deployment-app -n "$TEST_NAMESPACE"

    success "Test applications deployed and ready"
}

capture_pre_failure_state() {
    log "Capturing pre-failure state..."

    local state_file="/tmp/pre-failure-state.txt"

    cat > "$state_file" << EOF
Pre-Failure Cluster State
=========================
Date: $(date)

Nodes:
$(kubectl get nodes -o wide)

Pods in $TEST_NAMESPACE:
$(kubectl get pods -n "$TEST_NAMESPACE" -o wide)

PVCs:
$(kubectl get pvc -n "$TEST_NAMESPACE" -o wide)

PVs bound to $TEST_NAMESPACE:
$(kubectl get pv | grep "$TEST_NAMESPACE")

Pods on $TEST_SERVER:
$(kubectl get pods -n "$TEST_NAMESPACE" --field-selector spec.nodeName="$TEST_SERVER" -o wide)

StatefulSet pod data:
EOF

    # Capture data from each StatefulSet pod
    for i in {0..3}; do
        local pod_name="stateful-app-$i"
        if kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" &>/dev/null; then
            local pod_node=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.nodeName}')
            echo "Pod: $pod_name on Node: $pod_node" >> "$state_file"
            kubectl exec "$pod_name" -n "$TEST_NAMESPACE" -- cat /usr/share/nginx/html/index.html >> "$state_file" 2>/dev/null || echo "  (unable to read data)" >> "$state_file"
            echo "" >> "$state_file"
        fi
    done

    cat "$state_file"
    success "Pre-failure state captured: $state_file"
}

shutdown_test_server() {
    log "Shutting down test server: $TEST_SERVER"

    warning "Initiating shutdown of $TEST_SERVER in 10 seconds..."
    sleep 10

    # Shutdown the server
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$TEST_SERVER_IP "shutdown -h now" &>/dev/null || \
        warning "SSH command sent, server may take a moment to shutdown"

    success "Shutdown command sent to $TEST_SERVER"

    # Wait for SSH to become unavailable (server actually shut down)
    log "Waiting for server to shutdown (checking SSH connectivity)..."
    local ssh_timeout=120
    local counter=0
    while [[ $counter -lt $ssh_timeout ]]; do
        if ! ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no root@$TEST_SERVER_IP "echo test" &>/dev/null; then
            success "Server $TEST_SERVER is now shut down (SSH unreachable)"
            break
        fi
        echo -n "."
        sleep 5
        ((counter+=5))
    done
    echo ""

    if [[ $counter -ge $ssh_timeout ]]; then
        warning "Server may still be shutting down, proceeding anyway..."
    fi

    # Wait for node to become NotReady in Kubernetes
    log "Waiting for cluster to detect node failure..."
    local timeout=180
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        local node_status=$(kubectl get node "$TEST_SERVER" --no-headers 2>/dev/null | awk '{print $2}')
        if [[ "$node_status" == "NotReady" ]] || [[ "$node_status" == "Unknown" ]]; then
            success "Cluster detected node failure: $TEST_SERVER is $node_status"
            break
        fi
        echo -n "."
        sleep 5
        ((counter+=5))
    done
    echo ""

    if [[ $counter -ge $timeout ]]; then
        error "Node $TEST_SERVER did not become NotReady within $timeout seconds"
    fi

    log "Server shutdown complete. Ready to proceed with testing."
}

monitor_pod_rescheduling() {
    log "Monitoring pod rescheduling..."

    # Wait for Kubernetes to evict pods from failed node (default is 5 minutes)
    log "Waiting for pod eviction timeout (this takes ~5-6 minutes)..."
    sleep 360

    # Check pod status
    local total_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | wc -l)
    local running_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | grep "Running" | wc -l)
    local pending_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | grep "Pending" | wc -l)
    local terminating_pods=$(kubectl get pods -n "$TEST_NAMESPACE" --no-headers | grep "Terminating" | wc -l)

    log "Pod status after node failure:"
    log "  Total pods: $total_pods"
    log "  Running: $running_pods"
    log "  Pending: $pending_pods"
    log "  Terminating: $terminating_pods"

    kubectl get pods -n "$TEST_NAMESPACE" -o wide

    # Check which pods are on the failed node
    local pods_on_failed_node=$(kubectl get pods -n "$TEST_NAMESPACE" --field-selector spec.nodeName="$TEST_SERVER" --no-headers 2>/dev/null | wc -l)

    log "Pods still scheduled on failed node $TEST_SERVER: $pods_on_failed_node"

    success "Pod rescheduling status captured"
}

test_data_accessibility() {
    log "Testing data accessibility after node failure..."

    local accessible_count=0
    local inaccessible_count=0

    # Test StatefulSet pods
    log "Testing StatefulSet pod data accessibility..."
    for i in {0..3}; do
        local pod_name="stateful-app-$i"
        local pod_status=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        local pod_node=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Unknown")

        echo ""
        echo "Pod: $pod_name"
        echo "  Status: $pod_status"
        echo "  Node: $pod_node"

        if [[ "$pod_status" == "Running" ]]; then
            if kubectl exec "$pod_name" -n "$TEST_NAMESPACE" -- cat /usr/share/nginx/html/index.html &>/dev/null; then
                echo "  Data: ACCESSIBLE ✓"
                kubectl exec "$pod_name" -n "$TEST_NAMESPACE" -- cat /usr/share/nginx/html/index.html | head -2
                ((accessible_count++))
            else
                echo "  Data: INACCESSIBLE ✗"
                ((inaccessible_count++))
            fi
        elif [[ "$pod_node" == "$TEST_SERVER" ]]; then
            echo "  Data: INACCESSIBLE (pod on failed node) ✗"
            echo "  Note: Pod's PV is on failed node and cannot be accessed until node returns"
            ((inaccessible_count++))
        else
            echo "  Data: Pod not running"
            ((inaccessible_count++))
        fi
    done

    # Test Deployment app
    echo ""
    log "Testing Deployment app data accessibility..."
    local deployment_pod=$(kubectl get pods -n "$TEST_NAMESPACE" -l app=deployment-app --field-selector status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$deployment_pod" ]]; then
        local dep_pod_node=$(kubectl get pod "$deployment_pod" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.nodeName}')
        echo "Active deployment pod: $deployment_pod on node $dep_pod_node"

        if kubectl exec "$deployment_pod" -n "$TEST_NAMESPACE" -- cat /data/activity.log &>/dev/null; then
            echo "Deployment data: ACCESSIBLE ✓"
            echo "Recent activity:"
            kubectl exec "$deployment_pod" -n "$TEST_NAMESPACE" -- tail -5 /data/activity.log
            ((accessible_count++))
        else
            echo "Deployment data: INACCESSIBLE ✗"
            ((inaccessible_count++))
        fi
    else
        echo "No running deployment pods found"
    fi

    echo ""
    success "Data accessibility test completed"
    log "Accessible data locations: $accessible_count"
    log "Inaccessible data locations: $inaccessible_count"
}

explain_results() {
    log "Explaining test results..."

    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║         DATA ACCESSIBILITY EXPLANATION                         ║
╚════════════════════════════════════════════════════════════════╝

What happened when the server failed:

1. PODS ON FAILED NODE:
   - Pods on the failed node are stuck in "Terminating" state
   - They cannot be force-deleted because the kubelet is unreachable
   - After ~5 minutes, Kubernetes marks them for eviction

2. LOCAL PERSISTENT VOLUMES:
   - PVs on the failed node are INACCESSIBLE
   - StatefulSet pods with PVs on failed node CANNOT be rescheduled
   - Reason: Local PVs are tied to specific nodes (node affinity)
   - These pods wait for the node to return

3. PODS ON HEALTHY NODES:
   - Pods on k8s-stg1, k8s-stg1, k8s-stg2 continue running normally
   - Their data remains ACCESSIBLE
   - No interruption to their operation

4. DEPLOYMENTS WITH SHARED STORAGE:
   - If PVC is on a healthy node, deployment reschedules successfully
   - If PVC is on failed node, deployment cannot access data until node returns

5. DATA CONTINUITY:
   - 75% of cluster capacity remains available (3 out of 4 nodes)
   - Data on healthy nodes (3/4) is accessible
   - Data on failed node (1/4) is temporarily inaccessible
   - Overall: ~75% data availability maintained

KEY TAKEAWAYS:

✓ Cluster remains operational with 3/4 nodes
✓ New pods can be scheduled on healthy nodes
✓ Data on healthy nodes is fully accessible
✗ Data on failed node is inaccessible until node returns
✗ Pods with local PVs on failed node cannot reschedule

staging RECOMMENDATIONS:

1. Use distributed storage (Ceph, Longhorn) for critical data
2. Deploy applications with replicas across multiple nodes
3. Use ReadWriteMany (RWX) storage for shared data
4. Implement application-level data replication
5. Monitor node health and alert on failures

EOF
}

show_recovery_instructions() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║              SERVER RECOVERY INSTRUCTIONS                      ║
╚════════════════════════════════════════════════════════════════╝

TO RESTORE THE FAILED SERVER ($TEST_SERVER):

1. Power on the server:
   - Access the server console (iDRAC/IPMI)
   - Power on $TEST_SERVER at IP $TEST_SERVER_IP

2. Wait for server to boot and services to start:
   - Server should boot automatically
   - Kubelet will start automatically
   - Node will rejoin the cluster

3. Monitor node recovery:
   kubectl get nodes -w

4. Once node is Ready, verify pods:
   kubectl get pods -n $TEST_NAMESPACE -o wide

5. Verify data is accessible:
   kubectl exec stateful-app-0 -n $TEST_NAMESPACE -- cat /usr/share/nginx/html/index.html

CLEANUP TEST RESOURCES:

After testing is complete, clean up:
   kubectl delete namespace $TEST_NAMESPACE

CURRENT CLUSTER STATUS:

EOF

    kubectl get nodes
    echo ""
    kubectl get pods -n "$TEST_NAMESPACE" -o wide
}

test_after_recovery() {
    log "Testing cluster after server recovery..."

    # Wait for node to become Ready
    log "Waiting for $TEST_SERVER to become Ready..."
    local timeout=600
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        local node_status=$(kubectl get node "$TEST_SERVER" --no-headers 2>/dev/null | awk '{print $2}')
        if [[ "$node_status" == "Ready" ]]; then
            success "Node $TEST_SERVER is Ready!"
            break
        fi
        echo -n "."
        sleep 10
        ((counter+=10))
    done
    echo ""

    if [[ $counter -ge $timeout ]]; then
        error "Node $TEST_SERVER did not become Ready within $timeout seconds"
        return 1
    fi

    # Wait for pods to stabilize
    log "Waiting for pods to stabilize (60 seconds)..."
    sleep 60

    # Check all StatefulSet pods
    log "Checking StatefulSet pod status and data accessibility..."
    local all_accessible=true

    for i in {0..3}; do
        local pod_name="stateful-app-$i"

        # Wait for pod to be running
        local pod_timeout=180
        local pod_counter=0
        while [[ $pod_counter -lt $pod_timeout ]]; do
            local pod_status=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            if [[ "$pod_status" == "Running" ]]; then
                break
            fi
            sleep 5
            ((pod_counter+=5))
        done

        local pod_status=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        local pod_node=$(kubectl get pod "$pod_name" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Unknown")

        echo ""
        echo "Pod: $pod_name"
        echo "  Status: $pod_status"
        echo "  Node: $pod_node"

        if [[ "$pod_status" == "Running" ]]; then
            if kubectl exec "$pod_name" -n "$TEST_NAMESPACE" -- cat /usr/share/nginx/html/index.html &>/dev/null; then
                echo "  Data: ACCESSIBLE ✓"
                kubectl exec "$pod_name" -n "$TEST_NAMESPACE" -- cat /usr/share/nginx/html/index.html | head -2
            else
                echo "  Data: INACCESSIBLE ✗"
                all_accessible=false
            fi
        else
            echo "  Data: Pod not running ✗"
            all_accessible=false
        fi
    done

    echo ""
    if [[ "$all_accessible" == "true" ]]; then
        success "FULL RECOVERY: All data is now accessible!"
        success "All 4 StatefulSet pods are running with accessible data"
    else
        warning "Some pods or data may still be recovering"
    fi

    # Show final cluster state
    echo ""
    log "Final cluster state:"
    kubectl get nodes
    echo ""
    kubectl get pods -n "$TEST_NAMESPACE" -o wide
    echo ""
    kubectl get pvc -n "$TEST_NAMESPACE"

    success "Recovery testing complete!"
}

run_recovery_test() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║              RECOVERY TEST MODE                                ║
╚════════════════════════════════════════════════════════════════╝

This mode tests the cluster AFTER you have powered on $TEST_SERVER.

Prerequisites:
- $TEST_SERVER must be powered on and booting
- The test namespace '$TEST_NAMESPACE' must still exist
- You should have run the failure test first

EOF

    read -p "Has $TEST_SERVER been powered on and is booting? [y/N]: " CONFIRM_RECOVERY

    if [[ ! $CONFIRM_RECOVERY =~ ^[Yy]$ ]]; then
        log "Recovery test cancelled"
        exit 0
    fi

    test_after_recovery

    echo ""
    warning "After verifying recovery, you can cleanup with:"
    echo "  kubectl delete namespace $TEST_NAMESPACE"
}

main() {
    banner
    check_root
    confirm_test

    # Setup
    create_test_namespace
    deploy_test_applications

    # Capture initial state
    capture_pre_failure_state

    # Execute failure test
    shutdown_test_server
    monitor_pod_rescheduling
    test_data_accessibility

    # Explain and provide recovery instructions
    explain_results
    show_recovery_instructions

    success "Server failure test completed!"
    warning "Remember to power on $TEST_SERVER to restore full cluster capacity"
}

case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "This script tests HA cluster behavior when a server fails."
        echo ""
        echo "Modes:"
        echo "  $0                Run failure test (shuts down $TEST_SERVER)"
        echo "  $0 --recovery     Test cluster after powering on $TEST_SERVER"
        echo ""
        echo "The failure test will:"
        echo "  1. Create test applications with data"
        echo "  2. Shutdown $TEST_SERVER ($TEST_SERVER_IP)"
        echo "  3. Test data accessibility with server down"
        echo "  4. Provide recovery instructions"
        echo ""
        echo "The recovery test will:"
        echo "  1. Wait for $TEST_SERVER to rejoin cluster"
        echo "  2. Verify all pods return to Running state"
        echo "  3. Test that all data is accessible again"
        echo ""
        echo "WARNING: Make sure you can access the server console to power it back on."
        exit 0
        ;;
    --recovery)
        banner
        check_root
        run_recovery_test
        ;;
    *)
        main "$@"
        ;;
esac
