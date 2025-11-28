# HTTPS Configuration for SIAB

## Overview

SIAB is configured to enforce HTTPS for all external access. All HTTP (port 80) requests are automatically redirected to HTTPS (port 443).

## Configuration

### Gateway Configuration

All Istio gateways are configured with automatic HTTP to HTTPS redirection:

- **Admin Gateway**: Administrative services (Keycloak, MinIO, Grafana, Kubernetes Dashboard, Longhorn)
- **User Gateway**: User-facing services (Dashboard, Catalog, Applications)

### Manifest Location

Gateway configurations are stored in:
```
manifests/istio/gateways.yaml
```

### HTTP to HTTPS Redirect

Each gateway has two server configurations:

1. **HTTPS Server (Port 443)**
   - Terminates TLS using certificates from `siab-gateway-cert`
   - Configured with `mode: SIMPLE` for standard HTTPS

2. **HTTP Server (Port 80)**
   - Configured with `httpsRedirect: true`
   - Automatically redirects all HTTP requests to HTTPS

Example configuration:
```yaml
servers:
# HTTPS server
- hosts:
  - keycloak.siab.local
  - minio.siab.local
  port:
    name: https
    number: 443
    protocol: HTTPS
  tls:
    credentialName: siab-gateway-cert
    mode: SIMPLE
# HTTP server with redirect
- hosts:
  - keycloak.siab.local
  - minio.siab.local
  port:
    name: http
    number: 80
    protocol: HTTP
  tls:
    httpsRedirect: true
```

## TLS Certificates

### Certificate Management

SIAB uses cert-manager to automatically manage TLS certificates:

- **Certificate Name**: `siab-gateway-cert`
- **Secret Name**: `siab-gateway-cert` (in istio-system namespace)
- **CA**: Self-signed CA certificate `siab-ca`

### Certificate Location

View the certificate:
```bash
kubectl get certificate -n istio-system siab-gateway-cert
```

View the secret:
```bash
kubectl get secret -n istio-system siab-gateway-cert
```

### Certificate Renewal

Certificates are automatically renewed by cert-manager before expiration.

## Testing HTTPS Configuration

### Test HTTP Redirect

```bash
# Should return HTTP 301 or 308 redirect to HTTPS
curl -I http://keycloak.siab.local

# Expected response:
# HTTP/1.1 301 Moved Permanently
# location: https://keycloak.siab.local/
```

### Test HTTPS Access

```bash
# Should return successful response (200, 302, etc.)
curl -k -I https://keycloak.siab.local
```

### Test All Services

```bash
# Admin Gateway Services
for service in keycloak minio grafana k8s-dashboard longhorn; do
  echo "Testing $service.siab.local..."
  curl -I http://$service.siab.local 2>&1 | grep -E "(HTTP|location)"
done
```

## Accessing Services

### Admin Services

All admin services are accessible via HTTPS only:

| Service | URL |
|---------|-----|
| Keycloak | https://keycloak.siab.local |
| MinIO Console | https://minio.siab.local |
| Grafana | https://grafana.siab.local |
| Kubernetes Dashboard | https://k8s-dashboard.siab.local |
| Longhorn UI | https://longhorn.siab.local |

### User Services

User-facing services are also HTTPS-only:

| Service | URL |
|---------|-----|
| Main Dashboard | https://dashboard.siab.local |
| App Catalog | https://catalog.siab.local |
| Applications | https://*.apps.siab.local |

## Browser Certificate Warnings

Since SIAB uses self-signed certificates by default, browsers will show security warnings. Users must:

1. Click "Advanced" or similar option
2. Click "Proceed to [hostname]" or "Accept Risk"

### Production Deployment

For production deployments, configure cert-manager to use Let's Encrypt or another trusted CA:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
```

## Troubleshooting

### HTTP Not Redirecting to HTTPS

1. **Check gateway configuration:**
   ```bash
   kubectl get gateway -n istio-system admin-gateway -o yaml | grep -A 5 "httpsRedirect"
   ```

2. **Verify gateway is applied:**
   ```bash
   kubectl get gateway -n istio-system
   ```

3. **Re-apply gateway configuration:**
   ```bash
   kubectl apply -f manifests/istio/gateways.yaml
   ```

### Certificate Issues

1. **Check certificate status:**
   ```bash
   kubectl describe certificate -n istio-system siab-gateway-cert
   ```

2. **Check certificate secret:**
   ```bash
   kubectl get secret -n istio-system siab-gateway-cert
   ```

3. **Force certificate renewal:**
   ```bash
   kubectl delete certificate -n istio-system siab-gateway-cert
   kubectl apply -f <certificate-manifest>
   ```

### HTTPS Connection Refused

1. **Check ingress gateway pods:**
   ```bash
   kubectl get pods -n istio-system -l istio=ingress-admin
   kubectl get pods -n istio-system -l istio=ingress-user
   ```

2. **Check LoadBalancer IPs:**
   ```bash
   kubectl get svc -n istio-system | grep ingress
   ```

3. **Check firewall rules:**
   ```bash
   sudo firewall-cmd --list-ports | grep -E "80|443"
   ```

## Security Best Practices

1. **Always use HTTPS**: Never expose sensitive services over plain HTTP
2. **Use trusted certificates**: For production, use Let's Encrypt or commercial CA
3. **Enable HSTS**: Configure HTTP Strict Transport Security headers
4. **Regular certificate rotation**: Ensure cert-manager is monitoring and renewing certificates
5. **Monitor certificate expiration**: Set up alerts for certificate expiration

## References

- [Istio Gateway Documentation](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [Istio TLS Configuration](https://istio.io/latest/docs/tasks/traffic-management/ingress/secure-ingress/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
