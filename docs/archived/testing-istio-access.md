# Testing Istio Access

This guide explains how to use the comprehensive Istio access test script to diagnose connectivity issues.

## Overview

The `test-istio-access.sh` script provides comprehensive testing of all Istio-routed services from multiple perspectives:

- **Internal Cluster Tests**: Tests services from within the cluster
- **VirtualService Routing Tests**: Validates routing through Istio gateways
- **External Client Tests**: Tests access from outside the cluster
- **Backend Health Checks**: Verifies backend pods are running
- **Configuration Analysis**: Analyzes Istio configurations

## Quick Start

```bash
# Run all tests with default settings
./test-istio-access.sh

# Run with verbose output for detailed diagnostics
./test-istio-access.sh -v

# Save detailed report to file
./test-istio-access.sh -v -o istio-test-report.txt

# Test only external access
./test-istio-access.sh --external-only

# Test with custom domain
./test-istio-access.sh --domain mysiab.local
```

## Usage

```
./test-istio-access.sh [OPTIONS]

Options:
  --domain DOMAIN          SIAB domain (default: siab.local)
  --timeout SECONDS        Request timeout in seconds (default: 10)
  -v, --verbose           Verbose output with detailed diagnostics
  --internal-only         Only test internal cluster access
  --external-only         Only test external client access
  --no-diagnostics        Skip diagnostic data collection
  -o, --output FILE       Write detailed report to file
  -h, --help             Show help message
```

## What It Tests

### 1. Istio Infrastructure

- **Control Plane**: Checks if istiod is running
- **Gateway Pods**: Verifies admin and user gateway pods are healthy
- **Gateway Services**: Confirms services are configured correctly
- **Configuration**: Counts VirtualServices, Gateways, and DestinationRules

### 2. Internal Cluster Access

Tests direct access to services from within the cluster:

- Dashboard service (`siab-dashboard.siab-system`)
- Catalog service (`catalog-frontend.siab-catalog`)
- Admin gateway service
- User gateway service

These tests use temporary curl pods to verify services are reachable at the cluster level.

### 3. VirtualService Routing

Tests routing through Istio gateways using Host headers:

**User Gateway:**
- `dashboard.siab.local`
- `catalog.siab.local`
- `siab.local`

**Admin Gateway:**
- `grafana.siab.local`
- `keycloak.siab.local`

These tests verify that VirtualServices are correctly routing traffic through the gateways to backend services.

### 4. External Client Access

Tests access from outside the cluster:

**NodePort Access:**
- Tests services via NodePort if configured
- Uses actual node IPs and ports
- Simulates real client access patterns

**LoadBalancer Access:**
- Tests via LoadBalancer IP if available
- Verifies external IP allocation and routing

### 5. Backend Health

Checks that backend application pods are running:
- Dashboard pods in `siab-system` namespace
- Catalog pods in `siab-catalog` namespace

### 6. Configuration Analysis

Analyzes Istio configuration for common issues:
- VirtualService existence and configuration
- DestinationRule configuration for mTLS
- PeerAuthentication policies
- Namespace injection labels
- NetworkPolicies that might block traffic

## Understanding the Output

### Test Results

The script uses colored output to indicate test status:

- ✓ **Green (PASS)**: Test passed successfully
- ✗ **Red (FAIL)**: Test failed, action required
- ⚠ **Yellow (WARN)**: Warning, might not be critical
- ℹ **Blue (INFO)**: Informational message

### Verbose Mode

Use `-v` or `--verbose` for detailed diagnostics:

```bash
./test-istio-access.sh -v
```

This shows:
- Actual HTTP status codes
- ClusterIP addresses
- NodePort numbers
- Pod counts and status
- Individual VirtualService details

### Example Output

```
═══════════════════════════════════════════════════════════════
  SIAB Istio Access Test Suite
═══════════════════════════════════════════════════════════════
Domain: siab.local
Timeout: 10s
Tests: Internal=✓ External=✓

▸ Collecting Istio Diagnostics
✓ Istio version: 1.20.0
  → Istiod: 2/2 ready
  → Admin Gateway: 2/2 ready
  → User Gateway: 2/2 ready
  → User Gateway IP: 10.43.100.50
  → User Gateway NodePort (HTTP): 30080

▸ Testing Internal Cluster Access
✓ Dashboard service accessible internally (HTTP 200)
✓ Catalog service accessible internally (HTTP 200)
✓ Admin gateway service reachable (HTTP 404)
✓ User gateway service reachable (HTTP 404)

▸ Testing VirtualService Routing
✓ VirtualService routing for dashboard.siab.local working (HTTP 200)
✓ VirtualService routing for catalog.siab.local working (HTTP 200)
✗ VirtualService routing for grafana.siab.local failed (HTTP 503)

═══════════════════════════════════════════════════════════════
  Diagnostic Summary
═══════════════════════════════════════════════════════════════
Istio Components:
  Istio Version: 1.20.0
  Istiod Status: 2/2 ready
  Admin Gateway: 2/2 ready pods, IP: 10.43.100.51
  User Gateway:  2/2 ready pods, IP: 10.43.100.50
  User NodePort: 30080 (HTTP)

Configuration:
  VirtualServices: 5
  Gateways: 3
  DestinationRules: 12
  mTLS Mode: STRICT

═══════════════════════════════════════════════════════════════
  Test Results Summary
═══════════════════════════════════════════════════════════════
Tests Run: 15
Passed: 12
Warnings: 2
Failed: 1

Failed Tests:
  ✗ vs_admin_grafana: HTTP 503
```

## Common Issues and Solutions

### HTTP 503 - Upstream Unavailable

**Symptoms:**
- VirtualService tests return HTTP 503
- Services work internally but not through gateway

**Diagnosis:**
```bash
# Check backend pods
kubectl get pods -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>

# Check DestinationRules
kubectl get destinationrule -A
```

**Solution:**
- Ensure backend pods are running and ready
- Run `./fix-istio-mtls.sh` to fix mTLS configuration
- Verify DestinationRules exist for services

### HTTP 404 - Not Found

**Symptoms:**
- Requests return 404 when accessing via hostname
- Gateway returns 404 for all requests

**Diagnosis:**
```bash
# Check VirtualServices
kubectl get virtualservice -A

# Check if VirtualService hosts match
kubectl get virtualservice <name> -n istio-system -o yaml

# Verify gateway configuration
kubectl get gateway -A -o yaml
```

**Solution:**
- Ensure VirtualService exists for the hostname
- Verify VirtualService is attached to correct gateway
- Check that hostname matches what you're requesting

### Connection Timeout or Connection Refused

**Symptoms:**
- Tests time out waiting for response
- External tests can't connect

**Diagnosis:**
```bash
# Check gateway pods are running
kubectl get pods -n istio-system -l istio=ingress-user

# Check gateway service
kubectl get svc -n istio-system istio-ingress-user

# Check node IP and NodePort
kubectl get nodes -o wide
```

**Solution:**
- Verify gateway pods are healthy
- Ensure NodePort or LoadBalancer is properly configured
- Check firewall rules allow traffic to NodePort
- Verify DNS or /etc/hosts has correct entries

### Backend Pods Not Running

**Symptoms:**
- Internal service tests fail
- Backend health checks fail

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n siab-system
kubectl get pods -n siab-catalog

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
```

**Solution:**
- Check pod events for scheduling issues
- Verify image exists and is pullable
- Check resource requests/limits
- Review pod logs for startup errors

### mTLS Configuration Issues

**Symptoms:**
- "upstream connect error or disconnect/reset before headers"
- Services accessible directly but not through Istio

**Diagnosis:**
```bash
# Check PeerAuthentication
kubectl get peerauthentication -A

# Check DestinationRules
kubectl get destinationrule -A -o yaml | grep -A 5 "trafficPolicy"

# Run Istio analyzer
istioctl analyze
```

**Solution:**
```bash
# Run the mTLS fix script
./fix-istio-mtls.sh

# Or manually create DestinationRule
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: <service-name>
  namespace: <namespace>
spec:
  host: <service-name>.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
```

## Advanced Usage

### Testing Specific Services

You can modify the script to test additional services by editing the service arrays:

```bash
# Edit the script and add to user_services or admin_services arrays
declare -A user_services=(
    ["dashboard"]="dashboard.$SIAB_DOMAIN"
    ["catalog"]="catalog.$SIAB_DOMAIN"
    ["myapp"]="myapp.apps.$SIAB_DOMAIN"  # Add your service
)
```

### Running in CI/CD

The script exits with code 0 on success and 1 on failure, making it suitable for CI/CD:

```yaml
# Example GitLab CI
test_istio:
  stage: test
  script:
    - ./test-istio-access.sh -v -o test-report.txt
  artifacts:
    paths:
      - test-report.txt
    when: always
```

### Automated Reporting

Save reports for comparison over time:

```bash
# Save report with timestamp
./test-istio-access.sh -v -o "reports/istio-test-$(date +%Y%m%d-%H%M%S).txt"

# Compare with previous report
diff reports/istio-test-20240101-120000.txt reports/istio-test-20240102-120000.txt
```

### Custom Timeout for Slow Networks

If you have a slow network or high-latency environment:

```bash
# Increase timeout to 30 seconds
./test-istio-access.sh --timeout 30
```

## Integration with Other Tools

### Use with SIAB Diagnostics

Combine with the general SIAB diagnostic tool:

```bash
# Run general diagnostics first
./siab-diagnose.sh

# Then run Istio-specific tests
./test-istio-access.sh -v
```

### Use with Istio CLI Tools

Combine with istioctl for comprehensive analysis:

```bash
# Run the test script
./test-istio-access.sh -v

# If issues found, use istioctl for deeper analysis
istioctl analyze
istioctl proxy-status
istioctl proxy-config routes <gateway-pod>.istio-system
```

### Monitoring and Alerting

You can integrate the script into monitoring systems:

```bash
#!/bin/bash
# Example monitoring wrapper
if ! ./test-istio-access.sh --no-diagnostics; then
    # Send alert
    curl -X POST https://alerting-system/alert \
        -d "Istio access tests failed on $(hostname)"
fi
```

## Troubleshooting the Test Script Itself

### kubectl Not Found

The script requires kubectl. Install it:

```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl
```

### Permission Denied

Make the script executable:

```bash
chmod +x test-istio-access.sh
```

### Test Pods Fail to Start

If the script reports issues creating test pods:

```bash
# Check if you can create pods
kubectl run test-pod --rm -i --image=curlimages/curl:latest -- echo "test"

# Check pod security policies
kubectl get podsecuritypolicy

# Check resource quotas
kubectl get resourcequota -A
```

## Best Practices

1. **Run Regularly**: Include in your monitoring routine
2. **Save Reports**: Keep historical reports for trend analysis
3. **Use Verbose Mode**: When investigating issues, always use `-v`
4. **Test After Changes**: Run after any Istio configuration changes
5. **Combine Tools**: Use with other diagnostic tools for complete picture

## Reference

### Related Scripts

- `./siab-diagnose.sh` - General SIAB diagnostics
- `./fix-istio-mtls.sh` - Fix mTLS configuration issues
- `./scripts/validate-istio-ingress.sh` - Validate Istio ingress setup

### Related Documentation

- [Istio Migration Guide](./istio-migration.md)
- [SIAB Configuration](./configuration.md)
- [External VM Access](./external-vm-access.md)

### Istio Resources

- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Istio Troubleshooting](https://istio.io/latest/docs/ops/common-problems/)
- [Gateway Configuration](https://istio.io/latest/docs/reference/config/networking/gateway/)

## Getting Help

If the test script reveals issues you can't resolve:

1. Review the recommendations section in the output
2. Check the diagnostic summary for configuration issues
3. Run `./siab-diagnose.sh` for broader system analysis
4. Review Istio logs: `kubectl logs -n istio-system -l app=istiod`
5. Report issues: https://github.com/morbidsteve/SIAB/issues
