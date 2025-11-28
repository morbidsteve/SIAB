# Troubleshooting "Upstream Connect Error"

This guide helps you fix the common error:
```
upstream connect error or disconnect/reset before headers.
retried and the latest reset reason: remote connection failure,
transport failure reason: delayed connect error: 113
```

## Quick Fix

**Most Common Cause**: Missing DestinationRules for backend services with mTLS STRICT mode.

```bash
# 1. Diagnose the issue
./diagnose-upstream-errors.sh -v

# 2. Auto-fix (creates missing DestinationRules)
./diagnose-upstream-errors.sh --fix

# 3. Test from external client
./test-external-access.sh --k8s-host <YOUR_K8S_HOST_IP>
```

## Understanding the Error

When you see "upstream connect error", it means:
- The **Istio gateway** received your request successfully
- The gateway tried to forward the request to the **backend service**
- The connection to the backend **failed**

With mTLS STRICT mode (which SIAB uses), this usually means:
1. Backend service doesn't exist
2. DestinationRule is missing for the backend service
3. Backend pods are not running
4. VirtualService points to wrong namespace

## Step-by-Step Diagnosis

### Step 1: Run the diagnostic script

```bash
./diagnose-upstream-errors.sh -v
```

This will check:
- ✓ Each VirtualService and its backend
- ✓ Whether backend services exist
- ✓ Whether pods are running
- ✓ Whether DestinationRules exist
- ✓ mTLS configuration
- ✓ Namespace injection labels

**Example output:**
```
ℹ Analyzing VirtualService: keycloak (namespace: istio-system)
  → Hosts: keycloak.siab.local
  → Checking destination: keycloak.keycloak.svc.cluster.local
  → Service: keycloak, Namespace: keycloak
✗ Service keycloak NOT FOUND in namespace keycloak
  ⚠ This is likely why you're getting 503 errors!
  ⚠ VirtualService points to: keycloak.keycloak.svc.cluster.local
  ⚠ But service doesn't exist in namespace: keycloak
```

### Step 2: Common Issues and Fixes

#### Issue 1: Service in Wrong Namespace

**Symptom:**
```
✗ Service keycloak NOT FOUND in namespace keycloak
⚠ Found keycloak in namespace(s): auth-system
```

**Fix:**
Update the VirtualService to point to the correct namespace:

```bash
# Edit the VirtualService
kubectl edit virtualservice keycloak -n istio-system

# Change the host from:
#   host: keycloak.keycloak.svc.cluster.local
# To:
#   host: keycloak.auth-system.svc.cluster.local
```

#### Issue 2: Missing DestinationRule

**Symptom:**
```
✗ DestinationRule NOT FOUND for keycloak
⚠ This is likely causing 'upstream connect error'!
⚠ With mTLS STRICT mode, DestinationRule is required
```

**Auto-fix:**
```bash
./diagnose-upstream-errors.sh --fix
```

**Manual fix:**
```bash
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak
  namespace: auth-system  # Same namespace as the service
spec:
  host: keycloak.auth-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
```

#### Issue 3: Pods Not Running

**Symptom:**
```
✗ No pods are running for service keycloak
```

**Diagnose:**
```bash
# Check pod status
kubectl get pods -n <namespace> -l app=keycloak

# Check why pods failed
kubectl describe pods -n <namespace> -l app=keycloak

# Check pod logs
kubectl logs -n <namespace> -l app=keycloak
```

**Common causes:**
- Image pull errors
- Resource constraints
- Configuration errors
- Missing secrets/configmaps

#### Issue 4: Namespace Not Labeled for Istio Injection

**Symptom:**
```
⚠ Namespace auth-system: No Istio injection
```

**Fix:**
```bash
# Enable Istio injection
kubectl label namespace auth-system istio-injection=enabled --overwrite

# Restart pods to inject sidecar
kubectl rollout restart deployment -n auth-system
```

### Step 3: Test Access

#### From the K8s Host (Internal Test)

```bash
./test-istio-access.sh -v
```

This tests services from within the cluster.

#### From Your Client Machine (External Test)

First, get the gateway information:
```bash
# On K8s host
kubectl get svc -n istio-system | grep istio-ingress

# Note the NodePort numbers and the host IP
```

Then on your **client machine**:
```bash
# Copy the script to your client
scp test-external-access.sh user@client-machine:

# Run the test
./test-external-access.sh --k8s-host 192.168.1.100 \
  --admin-nodeport 31367 \
  --user-nodeport 30435 \
  -v
```

## Real Example: Fixing Keycloak

Let's say you get errors accessing `keycloak.siab.local`. Here's the complete process:

### 1. Check where Keycloak actually is

```bash
# Find keycloak service
kubectl get svc -A | grep keycloak
```

Output might show:
```
auth-system   keycloak   ClusterIP   10.43.100.10   <none>   8080/TCP   5d
```

So keycloak is in the `auth-system` namespace, not `keycloak` namespace!

### 2. Check the VirtualService

```bash
kubectl get virtualservice keycloak -n istio-system -o yaml | grep -A 5 destination
```

If it shows:
```yaml
destination:
  host: keycloak.keycloak.svc.cluster.local  # WRONG namespace!
```

**Fix it:**
```bash
kubectl edit virtualservice keycloak -n istio-system

# Change to:
destination:
  host: keycloak.auth-system.svc.cluster.local
```

### 3. Create/Check DestinationRule

```bash
# Check if it exists
kubectl get destinationrule -A | grep keycloak

# If not, create it:
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak
  namespace: auth-system
spec:
  host: keycloak.auth-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
```

### 4. Verify Pods are Running

```bash
kubectl get pods -n auth-system | grep keycloak
```

Should show pods in `Running` state.

### 5. Test Access

```bash
# From K8s host
./test-istio-access.sh -v

# From client machine
./test-external-access.sh --k8s-host <IP> -v
```

## Scripts Reference

### diagnose-upstream-errors.sh

Comprehensive diagnostic tool that checks all VirtualServices and their backends.

```bash
# Usage
./diagnose-upstream-errors.sh           # Diagnose only
./diagnose-upstream-errors.sh --fix     # Diagnose and auto-fix
./diagnose-upstream-errors.sh -v --fix  # Verbose with auto-fix
```

**What it checks:**
- VirtualService → Backend service mapping
- Service existence in correct namespace
- Backend pod health
- DestinationRule existence
- mTLS configuration
- Namespace injection labels

**What it fixes (with --fix):**
- Creates missing DestinationRules
- Adds mTLS to existing DestinationRules
- Enables Istio injection on namespaces

### test-external-access.sh

Tests access from an external client machine (not the K8s host).

```bash
# Basic usage
./test-external-access.sh --k8s-host 192.168.1.100

# Specify NodePorts
./test-external-access.sh --k8s-host 192.168.1.100 \
  --admin-nodeport 31367 --user-nodeport 30435

# Use LoadBalancer IPs
./test-external-access.sh --k8s-host 192.168.1.100 \
  --admin-ip 10.10.30.240 --user-ip 10.10.30.242

# Verbose output
./test-external-access.sh --k8s-host 192.168.1.100 -v

# Test HTTPS
./test-external-access.sh --k8s-host 192.168.1.100 --https
```

**Tests:**
- Gateway connectivity
- Admin services (grafana, keycloak, etc.)
- User services (dashboard, catalog)
- Provides detailed error messages

### test-istio-access.sh

Tests access from within the K8s cluster.

```bash
# Full test
./test-istio-access.sh -v

# Internal only
./test-istio-access.sh --internal-only

# Save report
./test-istio-access.sh -v -o report.txt
```

## Common Error Patterns

### Error: "upstream connect error or disconnect/reset before headers"

**Cause**: DestinationRule missing or backend service unreachable

**Fix**:
```bash
./diagnose-upstream-errors.sh --fix
```

### Error: "no healthy upstream"

**Cause**: All backend pods are down or not ready

**Fix**:
```bash
kubectl get pods -A | grep -v Running
kubectl describe pod <pod-name> -n <namespace>
```

### Error: "HTTP 404" from gateway

**Cause**: VirtualService not found or hostname mismatch

**Fix**:
```bash
kubectl get virtualservice -A
# Check that hostname matches what you're requesting
```

### Error: "Connection refused" or "Connection timeout"

**Cause**: Gateway not reachable or firewall blocking

**Fix**:
- Check gateway pods: `kubectl get pods -n istio-system`
- Check NodePort is accessible: `netstat -an | grep <nodeport>`
- Check firewall rules

## DNS Configuration

Make sure your client machine can resolve the hostnames:

### Option 1: /etc/hosts

```bash
# On your client machine
sudo nano /etc/hosts

# Add entries (replace with your K8s host IP):
192.168.1.100  grafana.siab.local keycloak.siab.local
192.168.1.100  dashboard.siab.local catalog.siab.local
192.168.1.100  k8s-dashboard.siab.local longhorn.siab.local minio.siab.local
```

### Option 2: DNS Server

Configure your DNS server to point `*.siab.local` to your K8s host IP.

### Option 3: Browser Extension

Use a browser extension like "Virtual Hosts" to override DNS for specific domains.

## Advanced Debugging

### View Gateway Logs

```bash
# Admin gateway logs
kubectl logs -n istio-system -l istio=ingress-admin --tail=100 -f

# User gateway logs
kubectl logs -n istio-system -l istio=ingress-user --tail=100 -f
```

Look for:
- "upstream connect error" messages
- "no healthy upstream" messages
- Certificate errors
- TLS handshake failures

### Check Istio Configuration

```bash
# Analyze configuration (requires istioctl)
istioctl analyze

# Check proxy status
istioctl proxy-status

# Get gateway routes
kubectl get pods -n istio-system -l istio=ingress-admin
istioctl proxy-config routes <pod-name>.istio-system
```

### Test Direct Service Access

```bash
# Port-forward to service
kubectl port-forward -n <namespace> svc/<service-name> 8080:80

# Test from localhost
curl http://localhost:8080
```

If this works, the issue is in Istio routing, not the service.

### Check mTLS Status

```bash
# Check PeerAuthentication
kubectl get peerauthentication -A

# Check DestinationRules
kubectl get destinationrule -A -o yaml | grep -A 5 "trafficPolicy"
```

## Still Having Issues?

1. **Run all diagnostic tools:**
   ```bash
   ./diagnose-upstream-errors.sh -v --fix
   ./test-istio-access.sh -v -o internal-report.txt
   ./test-external-access.sh --k8s-host <IP> -v
   ```

2. **Collect logs:**
   ```bash
   kubectl logs -n istio-system -l app=istiod > istiod.log
   kubectl logs -n istio-system -l istio=ingress-admin > admin-gateway.log
   kubectl logs -n istio-system -l istio=ingress-user > user-gateway.log
   ```

3. **Check events:**
   ```bash
   kubectl get events -A --sort-by='.lastTimestamp' | tail -50
   ```

4. **Report issue:**
   - Include diagnostic output
   - Include relevant logs
   - Describe what you were trying to access
   - https://github.com/morbidsteve/SIAB/issues

## Prevention

To avoid these issues in the future:

1. **Always create DestinationRules** when deploying services with Istio
2. **Use the SIAB operator** - it creates DestinationRules automatically
3. **Enable namespace injection** before deploying apps
4. **Use correct FQDNs** in VirtualServices (service.namespace.svc.cluster.local)
5. **Test internally first** before testing externally
6. **Run diagnostics regularly** to catch configuration drift
