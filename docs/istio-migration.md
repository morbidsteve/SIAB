# Migrating from nginx-ingress to Istio

SIAB uses **Istio exclusively** for all ingress traffic. If you have nginx-ingress installed (either from a previous setup or manual installation), this guide will help you migrate to Istio.

## Why Istio Instead of nginx-ingress?

SIAB uses Istio for ingress because it provides:

- **Service Mesh Integration**: Istio is not just an ingress controller - it's a complete service mesh that provides traffic management, security, and observability across all services
- **mTLS by Default**: Automatic mutual TLS encryption between all services
- **Fine-grained Traffic Control**: Advanced routing, traffic splitting, retries, timeouts, circuit breaking
- **Security Features**: Authorization policies, authentication, and certificate management
- **Observability**: Built-in metrics, distributed tracing, and access logs
- **Dual Gateway Architecture**: Separate gateways for admin and user traffic

## Architecture Overview

SIAB uses a dual-gateway architecture:

### Admin Gateway (`istio-ingress-admin`)

For administrative interfaces that should be isolated:
- Grafana (monitoring)
- Keycloak (identity management)
- Kubernetes Dashboard
- MinIO Console
- Longhorn UI

**Hosts served**: `*.admin.siab.local`, `grafana.siab.local`, `keycloak.siab.local`, etc.

### User Gateway (`istio-ingress-user`)

For user applications and the application catalog:
- SIAB Dashboard
- Application Catalog
- User-deployed applications

**Hosts served**: `dashboard.siab.local`, `catalog.siab.local`, `*.apps.siab.local`

## Quick Start: Remove nginx-ingress

### Step 1: Diagnose Current State

Run the diagnostic script to see what's installed:

```bash
cd /home/user/SIAB
chmod +x scripts/diagnose-ingress.sh
./scripts/diagnose-ingress.sh
```

This will show:
- Whether nginx-ingress is installed
- Status of Istio components
- Any Ingress resources that need migration

### Step 2: Remove nginx-ingress

```bash
# Dry run first (see what would be removed)
DRY_RUN=true ./scripts/remove-nginx-ingress.sh

# Actually remove nginx-ingress
./scripts/remove-nginx-ingress.sh
```

The script will remove:
- nginx-ingress-controller deployments/daemonsets
- nginx-ingress services
- nginx IngressClass resources
- nginx-ingress helm releases
- Empty nginx-ingress namespaces

### Step 3: Validate Istio

```bash
./scripts/validate-istio-ingress.sh
```

This validates:
- Istio control plane is healthy
- Both gateways are running
- Gateway and VirtualService resources exist
- mTLS is configured

## Migrating Ingress Resources to VirtualServices

If you have existing Kubernetes Ingress resources, you'll need to convert them to Istio VirtualServices.

### Example: Kubernetes Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

### Converted to Istio VirtualService

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
  namespace: istio-system
spec:
  hosts:
    - "myapp.apps.siab.local"  # Use SIAB domain
  gateways:
    - user-gateway  # Use user-gateway for user apps
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: my-app.default.svc.cluster.local
            port:
              number: 80
```

### Key Differences

| Kubernetes Ingress | Istio VirtualService |
|-------------------|---------------------|
| `ingressClassName` or annotation | `spec.gateways` (use `user-gateway` or `admin-gateway`) |
| `spec.rules[].host` | `spec.hosts` |
| `spec.rules[].http.paths` | `spec.http[].match[].uri` |
| `backend.service` | `route[].destination.host` (use FQDN: `service.namespace.svc.cluster.local`) |

### Advanced Example: Path-based Routing

Kubernetes Ingress:
```yaml
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /v1
            backend:
              service:
                name: api-v1
                port:
                  number: 8080
          - path: /v2
            backend:
              service:
                name: api-v2
                port:
                  number: 8080
```

Istio VirtualService:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api
  namespace: istio-system
spec:
  hosts:
    - "api.apps.siab.local"
  gateways:
    - user-gateway
  http:
    - match:
        - uri:
            prefix: /v2
      route:
        - destination:
            host: api-v2.default.svc.cluster.local
            port:
              number: 8080
    - match:
        - uri:
            prefix: /v1
      route:
        - destination:
            host: api-v1.default.svc.cluster.local
            port:
              number: 8080
```

**Note**: Order matters! More specific matches should come first.

## Using SIAB's Application CRD

The easiest way to deploy applications with ingress is using SIAB's `SIABApplication` CRD:

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: my-app
  namespace: default
spec:
  image: nginx:1.25-alpine
  replicas: 2
  port: 80

  # Enable ingress automatically
  ingress:
    enabled: true
    hostname: myapp.apps.siab.local
    tls: true

  # Security scanning
  security:
    scanOnDeploy: true
```

The SIAB operator will automatically create:
- Deployment
- Service
- VirtualService (attached to the appropriate gateway)
- ServiceEntry (if needed)
- DestinationRule (for mTLS)

## Advanced Istio Features

Once you've migrated, you can leverage Istio's advanced features:

### Traffic Splitting (Canary Deployments)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app-canary
  namespace: istio-system
spec:
  hosts:
    - "myapp.apps.siab.local"
  gateways:
    - user-gateway
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: my-app.default.svc.cluster.local
            subset: v2
    - route:
        - destination:
            host: my-app.default.svc.cluster.local
            subset: v1
          weight: 90
        - destination:
            host: my-app.default.svc.cluster.local
            subset: v2
          weight: 10
```

### Retries and Timeouts

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app-resilient
  namespace: istio-system
spec:
  hosts:
    - "myapp.apps.siab.local"
  gateways:
    - user-gateway
  http:
    - route:
        - destination:
            host: my-app.default.svc.cluster.local
            port:
              number: 80
      timeout: 10s
      retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: 5xx,reset,connect-failure,refused-stream
```

### Circuit Breaking

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-app-circuit-breaker
  namespace: default
spec:
  host: my-app.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

## Accessing Services

### Get Gateway IPs

```bash
# Admin gateway
kubectl get svc istio-ingress-admin -n istio-system

# User gateway
kubectl get svc istio-ingress-user -n istio-system
```

### Configure DNS or /etc/hosts

For LoadBalancer type:
```bash
# Get the IP
ADMIN_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
USER_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Add to /etc/hosts (or configure DNS)
echo "$ADMIN_IP grafana.siab.local keycloak.siab.local minio.siab.local" | sudo tee -a /etc/hosts
echo "$USER_IP dashboard.siab.local catalog.siab.local" | sudo tee -a /etc/hosts
```

For NodePort type:
```bash
# Get node IP and ports
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
ADMIN_HTTP_PORT=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
USER_HTTP_PORT=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

# Access via
echo "Admin services: http://$NODE_IP:$ADMIN_HTTP_PORT"
echo "User services: http://$NODE_IP:$USER_HTTP_PORT"
```

## Troubleshooting

### Gateway Not Receiving Traffic

1. Check gateway pods:
   ```bash
   kubectl get pods -n istio-system -l app=istio-ingress-admin
   kubectl get pods -n istio-system -l app=istio-ingress-user
   ```

2. Check gateway configuration:
   ```bash
   kubectl get gateway -n istio-system
   kubectl describe gateway admin-gateway -n istio-system
   kubectl describe gateway user-gateway -n istio-system
   ```

3. Check VirtualService:
   ```bash
   kubectl get virtualservice -A
   kubectl describe virtualservice <name> -n <namespace>
   ```

### Service Not Accessible

1. Verify the service exists:
   ```bash
   kubectl get svc <service-name> -n <namespace>
   ```

2. Check if pods are ready:
   ```bash
   kubectl get pods -n <namespace> -l app=<app-label>
   ```

3. Verify VirtualService is attached to correct gateway:
   ```bash
   kubectl get virtualservice <name> -n istio-system -o yaml
   ```

4. Check DestinationRule exists:
   ```bash
   kubectl get destinationrule -n <namespace>
   ```

### mTLS Issues

If you see errors like "upstream connect error or disconnect/reset before headers":

1. Check PeerAuthentication:
   ```bash
   kubectl get peerauthentication -A
   ```

2. Ensure DestinationRule has correct mTLS settings:
   ```bash
   kubectl get destinationrule -A -o yaml | grep -A 5 "trafficPolicy"
   ```

3. Run the mTLS fix script:
   ```bash
   ./fix-istio-mtls.sh
   ```

## Reference

### Useful Commands

```bash
# List all gateways
kubectl get gateway -A

# List all VirtualServices
kubectl get virtualservice -A

# List all DestinationRules
kubectl get destinationrule -A

# Check Istio configuration status
istioctl analyze

# View gateway configuration
istioctl proxy-config route <gateway-pod-name>.istio-system

# Debug VirtualService
istioctl analyze virtualservice <name> -n <namespace>
```

### Documentation

- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Istio Gateway](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [Istio VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/)
- [SIAB Configuration Guide](./configuration.md)
- [SIAB Security Guide](./security.md)

## Getting Help

If you encounter issues:

1. Run diagnostics:
   ```bash
   ./scripts/diagnose-ingress.sh
   ./scripts/validate-istio-ingress.sh
   ./siab-diagnose.sh
   ```

2. Check logs:
   ```bash
   kubectl logs -n istio-system -l app=istiod
   kubectl logs -n istio-system -l app=istio-ingress-admin
   kubectl logs -n istio-system -l app=istio-ingress-user
   ```

3. Report issues: https://github.com/morbidsteve/SIAB/issues
