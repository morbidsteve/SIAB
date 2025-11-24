# SIAB Testing Quick Reference

## Run Full Test Suite

```bash
sudo ./siab-test.sh
```

## What Gets Tested

| Category | Components Tested |
|----------|------------------|
| **Prerequisites** | kubectl, cluster access, helm |
| **Namespaces** | 11 core namespaces |
| **MetalLB** | Controller, speaker, IP pools, L2 advertisement |
| **Istio** | Istiod, admin/user gateways, VirtualServices |
| **Storage** | MinIO, Longhorn, StorageClass, PVC provisioning |
| **Security** | Trivy, OPA Gatekeeper, cert-manager, TLS certs |
| **Auth** | Keycloak deployment and service |
| **Monitoring** | Prometheus, Grafana |
| **Dashboard** | Deployment, service, VirtualService |
| **Endpoints** | HTTP(S) connectivity to all 8 service endpoints |
| **Network** | NetworkPolicies configured |
| **Pod Health** | No crashes, errors, or pending pods |
| **DNS** | CoreDNS and service resolution |
| **RBAC** | ClusterRoles and ServiceAccounts |

## Test Results

✅ **PASS** - Component working correctly
⚠️ **WARN** - Optional component or minor issue
❌ **FAIL** - Critical component not working

## Quick Manual Tests

### Test Gateway IPs
```bash
kubectl get svc -n istio-system | grep ingress
```

### Test Endpoint from Host
```bash
# Get gateway IP
GATEWAY_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test dashboard
curl -k -H "Host: dashboard.siab.local" https://$GATEWAY_IP
```

### Test Storage
```bash
# Check storage class
kubectl get storageclass

# Create test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF

# Check status
kubectl get pvc test-pvc

# Cleanup
kubectl delete pvc test-pvc
```

### Test from External VM

1. **Get IPs on SIAB host:**
   ```bash
   sudo siab-info
   ```

2. **Add to /etc/hosts on laptop VM:**
   ```bash
   192.168.1.240 keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local
   192.168.1.242 dashboard.siab.local siab.local catalog.siab.local
   ```

3. **Test connectivity:**
   ```bash
   ping 192.168.1.242
   curl -k https://dashboard.siab.local
   ```

4. **Open in browser:**
   - https://dashboard.siab.local
   - https://keycloak.siab.local

## Common Issues

### LoadBalancer IP Stuck in Pending
```bash
# Check MetalLB
kubectl logs -n metallb-system -l app=metallb
kubectl get ipaddresspool -n metallb-system
kubectl rollout restart deployment -n metallb-system controller
```

### Endpoint Not Responding
```bash
# Check VirtualService
kubectl get virtualservice -A
kubectl describe virtualservice -n istio-system <name>

# Check gateway pods
kubectl get pods -n istio-system -l istio=ingress-user
kubectl logs -n istio-system -l istio=ingress-user
```

### PVC Stuck in Pending
```bash
# Check Longhorn
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# Check storage class
kubectl get storageclass
kubectl describe pvc <pvc-name>
```

### Pods Crashing
```bash
# Get details
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Full Documentation

See [docs/testing-guide.md](./docs/testing-guide.md) for comprehensive testing documentation.

## Other Useful Commands

```bash
# View access information
sudo siab-info

# Check platform status
sudo siab-status

# Run diagnostics
sudo siab-diagnose

# View all pods
kubectl get pods -A

# Check specific service
kubectl get all -n <namespace>
```
