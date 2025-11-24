# SIAB Fix Instructions

## Problem Summary

You're experiencing two main issues:
1. **Upstream connection errors** when accessing services (error 113: No route to host)
2. **Missing block storage** for persistent volumes

## Solution

Run the comprehensive fix script on your Rocky OS machine.

## Steps to Fix

### On your Rocky OS machine (10.10.30.100):

```bash
# 1. Navigate to the SIAB directory
cd /path/to/SIAB

# 2. Make the fix script executable
chmod +x fix-siab-complete.sh

# 3. Run the fix script as root
sudo bash fix-siab-complete.sh
```

### On your client machine (where you browse from):

After the script completes, add these entries to your `/etc/hosts` file:

**For Linux/Mac:** Edit `/etc/hosts`
```bash
sudo nano /etc/hosts
```

**For Windows:** Edit `C:\Windows\System32\drivers\etc\hosts` as Administrator

Add these lines:
```
# SIAB Admin Plane (restricted)
10.10.30.240 keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local

# SIAB User Plane
10.10.30.242 siab.local dashboard.siab.local catalog.siab.local
```

## What the Fix Script Does

1. **Installs Longhorn Block Storage**
   - Provides dynamic persistent volume provisioning
   - Sets Longhorn as the default StorageClass
   - Exposes Longhorn UI on admin plane

2. **Fixes Network Policies**
   - Creates allow-all ingress policies for all backend services
   - Ensures traffic can flow between Istio gateways and services

3. **Fixes Calico/Canal Network**
   - Applies permissive Calico configuration
   - Creates GlobalNetworkPolicy to allow pod-to-pod traffic
   - Configures Felix for proper connectivity

4. **Fixes Istio Service Mesh Routing**
   - Moves DestinationRules to istio-system namespace (correct location)
   - Disables mTLS for backend services (they don't have Envoy sidecars)
   - Creates/updates VirtualServices with correct gateway bindings
   - Adds authorization policies to allow traffic

5. **Restarts Components**
   - Restarts Canal/Calico pods
   - Restarts Istio gateways
   - Restarts backend services
   - Waits for everything to be ready

6. **Verifies Connectivity**
   - Tests gateway-to-backend connectivity
   - Reports any remaining issues

## After Running the Fix

### Access Your Services

**Admin Services (https):**
- Keycloak: https://keycloak.siab.local
- MinIO Console: https://minio.siab.local
- Grafana: https://grafana.siab.local
- Kubernetes Dashboard: https://k8s-dashboard.siab.local
- Longhorn UI: https://longhorn.siab.local

**User Services (https):**
- Main Dashboard: https://dashboard.siab.local or https://siab.local
- App Catalog: https://catalog.siab.local

### Get Credentials

```bash
cd /path/to/SIAB
./siab-info.sh
```

This will display all admin credentials for Keycloak, MinIO, Grafana, etc.

### Verify Block Storage

```bash
# Check Longhorn is running
kubectl get pods -n longhorn-system

# Check StorageClass
kubectl get storageclass

# You should see 'longhorn' marked as (default)
```

### Test Storage

Create a test PVC to verify block storage works:

```bash
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

# Check it was created
kubectl get pvc test-pvc

# Should show STATUS: Bound
```

## Troubleshooting

### If services still don't work after the fix:

1. **Check pod status:**
```bash
kubectl get pods -A | grep -v Running
```

2. **Check Istio gateway status:**
```bash
kubectl get pods -n istio-system
```

3. **Check gateway IPs:**
```bash
kubectl get svc -n istio-system | grep ingress
```

4. **Run diagnostics:**
```bash
./siab-diagnose.sh --fix
```

5. **Check specific service logs:**
```bash
# Keycloak
kubectl logs -n keycloak -l app=keycloak --tail=50

# Dashboard
kubectl logs -n siab-system -l app=siab-dashboard --tail=50

# Istio gateway
kubectl logs -n istio-system -l istio=ingress-admin --tail=50
```

### Certificate Warnings

You'll see SSL certificate warnings because SIAB uses self-signed certificates. This is normal. Click "Advanced" and "Proceed" (or equivalent) in your browser.

### Port 443 vs Port 80

All services are exposed on ports 80 (HTTP) and 443 (HTTPS). The gateways redirect HTTP to HTTPS automatically.

## Need Help?

If issues persist:
1. Run `./siab-diagnose.sh -v` for verbose diagnostics
2. Check logs: `/var/log/siab/`
3. Check RKE2 status: `systemctl status rke2-server`

## What's Different Now?

### Before Fix:
- ❌ No block storage (PVCs couldn't be provisioned)
- ❌ Istio routing misconfigured (DestinationRules in wrong namespace)
- ❌ Network policies blocking traffic
- ❌ Calico/Canal default-deny blocking pod communication
- ❌ Upstream connection errors (error 113)

### After Fix:
- ✅ Longhorn block storage installed and working
- ✅ Istio routing properly configured
- ✅ Network policies allow necessary traffic
- ✅ Calico/Canal configured for connectivity
- ✅ All services reachable via Istio gateways
- ✅ Longhorn UI available for storage management

Enjoy your fully functional SIAB platform!
