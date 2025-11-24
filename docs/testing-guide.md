# SIAB Testing Guide

Comprehensive guide to testing your SIAB installation and validating all components.

## Quick Test

Run the comprehensive test suite:

```bash
sudo ./siab-test.sh
```

This script validates all SIAB components including networking, storage, security, and endpoints.

## What Gets Tested

### 1. Prerequisites & Environment
- ✓ kubectl availability and cluster access
- ✓ helm installation
- ✓ Kubernetes cluster connectivity

### 2. Core Namespaces
Tests that all required namespaces exist:
- `kube-system` - Core Kubernetes
- `istio-system` - Service mesh
- `siab-system` - SIAB platform
- `metallb-system` - Load balancer
- `cert-manager` - TLS certificates
- `keycloak` - Authentication
- `minio` - Object storage
- `monitoring` - Metrics & logs
- `longhorn-system` - Block storage
- `trivy-system` - Security scanning
- `gatekeeper-system` - Policy enforcement

### 3. MetalLB Load Balancer
- ✓ Controller deployment health
- ✓ Speaker daemonset running on all nodes
- ✓ IP address pools configured (admin-pool, user-pool)
- ✓ L2 advertisement configured
- ✓ LoadBalancer IPs assigned

### 4. Istio Service Mesh & Gateways
- ✓ Istiod (control plane) running
- ✓ Admin ingress gateway deployment
- ✓ User ingress gateway deployment
- ✓ LoadBalancer IPs assigned to gateways
- ✓ Gateway resources configured
- ✓ VirtualServices deployed

### 5. Storage Systems
- ✓ MinIO deployment and console service
- ✓ Longhorn manager and driver
- ✓ Default StorageClass configured
- ✓ Dynamic PVC provisioning (creates test PVC)

### 6. Security Components
- ✓ Trivy Operator for vulnerability scanning
- ✓ OPA Gatekeeper for policy enforcement
- ✓ Cert-Manager for TLS
- ✓ TLS certificates issued and ready

### 7. Authentication (Keycloak)
- ✓ Keycloak deployment health
- ✓ Keycloak service accessibility

### 8. Monitoring Stack
- ✓ Prometheus pods running
- ✓ Grafana deployment health

### 9. SIAB Dashboard
- ✓ Dashboard deployment
- ✓ Dashboard service
- ✓ Dashboard VirtualService routing

### 10. Endpoint Connectivity
Tests actual HTTP(S) connectivity to all services:

**Admin Gateway Endpoints:**
- Keycloak: `https://keycloak.siab.local`
- MinIO: `https://minio.siab.local`
- Grafana: `https://grafana.siab.local`
- K8s Dashboard: `https://k8s-dashboard.siab.local`
- Longhorn: `https://longhorn.siab.local`

**User Gateway Endpoints:**
- Dashboard: `https://dashboard.siab.local`
- Main Site: `https://siab.local`
- Catalog: `https://catalog.siab.local`

### 11. Network Policies
- ✓ NetworkPolicy resources configured

### 12. Pod Health
- ✓ No pods in CrashLoopBackOff
- ✓ No pods in Error state
- ✓ No pods stuck in Pending

### 13. DNS Resolution
- ✓ CoreDNS running
- ✓ Internal service DNS resolution

### 14. RBAC & Permissions
- ✓ ClusterRoles configured
- ✓ Service accounts present

## Test Output

The test script provides color-coded output:

- 🟢 **PASS** - Component working correctly
- 🟡 **WARN** - Optional component or minor issue
- 🔴 **FAIL** - Critical component not working

### Example Output

```
╔════════════════════════════════════════════════════════════════╗
║  3. MetalLB Load Balancer                                     ║
╚════════════════════════════════════════════════════════════════╝

▸ Testing: MetalLB controller deployment
  ✓ PASS - MetalLB controller is running (1 replicas)
▸ Testing: MetalLB speaker daemonset
  ✓ PASS - MetalLB speaker running on 1/1 nodes
▸ Testing: IP address pools configured
  ✓ PASS - Found 2 IP address pools
    admin-pool   [192.168.1.240-192.168.1.241]
    user-pool    [192.168.1.242-192.168.1.243]
▸ Testing: L2 advertisement configured
  ✓ PASS - L2 advertisement configured
```

## Manual Testing

### Test Individual Components

#### 1. Test MetalLB

```bash
# Check MetalLB status
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Verify gateway IPs
kubectl get svc -n istio-system istio-ingress-admin
kubectl get svc -n istio-system istio-ingress-user
```

#### 2. Test Istio Gateways

```bash
# Check gateway pods
kubectl get pods -n istio-system -l istio=ingress-admin
kubectl get pods -n istio-system -l istio=ingress-user

# Check gateway configurations
kubectl get gateway -n istio-system
kubectl get virtualservice -A
```

#### 3. Test Storage

```bash
# Check storage classes
kubectl get storageclass

# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Check if bound
kubectl get pvc test-pvc -n default

# Cleanup
kubectl delete pvc test-pvc -n default
```

#### 4. Test MinIO Access

```bash
# Port forward MinIO console
kubectl port-forward -n minio svc/minio-console 9001:9001 --address 0.0.0.0

# Access at http://<host-ip>:9001
```

#### 5. Test Dashboard

```bash
# Check dashboard
kubectl get pods -n siab-system
kubectl get svc -n siab-system
kubectl get virtualservice -n istio-system siab-dashboard

# Port forward for testing
kubectl port-forward -n siab-system svc/siab-dashboard 8080:80 --address 0.0.0.0

# Access at http://<host-ip>:8080
```

### Test External Access

#### From the SIAB host:

```bash
# Test with curl (bypass DNS)
curl -k -H "Host: dashboard.siab.local" https://<USER_GATEWAY_IP>
curl -k -H "Host: keycloak.siab.local" https://<ADMIN_GATEWAY_IP>
```

#### From an external VM:

1. **Add /etc/hosts entries:**
   ```bash
   # On your laptop VM
   sudo nano /etc/hosts
   ```

   Add:
   ```
   <admin-gateway-ip> keycloak.siab.local minio.siab.local grafana.siab.local
   <user-gateway-ip> dashboard.siab.local siab.local catalog.siab.local
   ```

2. **Test connectivity:**
   ```bash
   # Ping gateway IPs
   ping <admin-gateway-ip>
   ping <user-gateway-ip>

   # Test HTTPS
   curl -k https://dashboard.siab.local
   curl -k https://keycloak.siab.local
   ```

3. **Open in browser:**
   - https://dashboard.siab.local
   - https://keycloak.siab.local

## Troubleshooting Failed Tests

### MetalLB Issues

**Problem:** LoadBalancer IPs not assigned (stuck in `<pending>`)

**Solutions:**
```bash
# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb

# Verify IP pools
kubectl get ipaddresspool -n metallb-system -o yaml

# Check L2 advertisement
kubectl get l2advertisement -n metallb-system -o yaml

# Restart MetalLB
kubectl rollout restart deployment -n metallb-system controller
kubectl rollout restart daemonset -n metallb-system speaker
```

### Istio Gateway Issues

**Problem:** Gateways not responding

**Solutions:**
```bash
# Check gateway pods
kubectl get pods -n istio-system -l istio=ingress-admin
kubectl logs -n istio-system -l istio=ingress-admin

# Check gateway service
kubectl get svc -n istio-system istio-ingress-admin
kubectl describe svc -n istio-system istio-ingress-admin

# Restart gateway
kubectl rollout restart deployment -n istio-system istio-ingress-admin
kubectl rollout restart deployment -n istio-system istio-ingress-user
```

### Endpoint Connectivity Issues

**Problem:** curl fails with connection refused

**Solutions:**
```bash
# 1. Check if gateway has IP
kubectl get svc -n istio-system

# 2. Test from within cluster
kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v http://siab-dashboard.siab-system.svc.cluster.local

# 3. Check VirtualService
kubectl get virtualservice -n istio-system siab-dashboard -o yaml

# 4. Check if host header matters
curl -k -v -H "Host: dashboard.siab.local" https://<gateway-ip>
```

### Storage Issues

**Problem:** PVCs stuck in Pending

**Solutions:**
```bash
# Check storage class
kubectl get storageclass

# Check Longhorn
kubectl get pods -n longhorn-system

# Describe PVC to see error
kubectl describe pvc <pvc-name>

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager
```

### Pod Health Issues

**Problem:** Pods in CrashLoopBackOff

**Solutions:**
```bash
# Get pod details
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Continuous Testing

### Set up automated tests

Create a cron job to run tests periodically:

```bash
# Create test script in /usr/local/bin
sudo cp siab-test.sh /usr/local/bin/siab-test
sudo chmod +x /usr/local/bin/siab-test

# Add to crontab (daily at 2 AM)
sudo crontab -e
```

Add:
```
0 2 * * * /usr/local/bin/siab-test >> /var/log/siab-test.log 2>&1
```

### Monitor test results

```bash
# View test log
sudo tail -f /var/log/siab-test.log

# Run test and save results
sudo siab-test | tee siab-test-$(date +%Y%m%d).log
```

## Integration with CI/CD

You can integrate the test script into your CI/CD pipeline:

```yaml
# Example GitHub Actions
name: SIAB Tests
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run SIAB Tests
        run: sudo ./siab-test.sh
```

## Performance Testing

### Load test endpoints

```bash
# Install Apache Bench
sudo dnf install httpd-tools  # Rocky/RHEL
sudo apt install apache2-utils  # Ubuntu

# Test dashboard
ab -n 100 -c 10 -H "Host: dashboard.siab.local" https://<user-gateway-ip>/

# Test Keycloak
ab -n 50 -c 5 -H "Host: keycloak.siab.local" https://<admin-gateway-ip>/
```

### Stress test storage

```bash
# Create multiple PVCs
for i in {1..10}; do
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: stress-test-pvc-$i
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
done

# Wait and check
kubectl get pvc -n default

# Cleanup
kubectl delete pvc -n default -l app=stress-test
```

## Validation Checklist

Before considering SIAB production-ready, ensure:

- [ ] All test categories pass (0 failures)
- [ ] Both gateway IPs are assigned
- [ ] All endpoints accessible from external VM
- [ ] Storage provisioning works (test PVC)
- [ ] TLS certificates valid and ready
- [ ] No pods in CrashLoopBackOff
- [ ] Monitoring stack operational
- [ ] Authentication (Keycloak) accessible
- [ ] Dashboard loads correctly
- [ ] All service links work from dashboard

## Support

If tests fail consistently:

1. Run full diagnostics: `sudo siab-diagnose`
2. Check component status: `sudo siab-status`
3. Review logs: `kubectl logs -n <namespace> <pod-name>`
4. Consult documentation: `./docs/`
5. Open issue: https://github.com/morbidsteve/SIAB/issues
