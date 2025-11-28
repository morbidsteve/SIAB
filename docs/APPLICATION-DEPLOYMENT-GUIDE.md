# Application Deployment Guide

## Overview

This comprehensive guide explains how to deploy applications on SIAB's secure Kubernetes runtime. SIAB provides a production-ready, security-hardened platform with built-in service mesh, identity management, and policy enforcement.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding SIAB Architecture](#understanding-siab-architecture)
3. [Deployment Methods](#deployment-methods)
4. [Security Considerations](#security-considerations)
5. [Step-by-Step Examples](#step-by-step-examples)
6. [Exposing Applications via Istio](#exposing-applications-via-istio)
7. [Integrating with Keycloak](#integrating-with-keycloak)
8. [Monitoring and Observability](#monitoring-and-observability)
9. [Troubleshooting](#troubleshooting)

## Prerequisites

Before deploying applications, ensure you have:

- ✅ SIAB installed and running (`siab-status.sh` shows all components healthy)
- ✅ `kubectl` configured to access the cluster
- ✅ Understanding of Kubernetes basics (pods, services, deployments)
- ✅ Firewalld properly configured (see [Firewalld Configuration Guide](./FIREWALLD-CONFIGURATION.md))
- ✅ HTTPS access working (see [HTTPS Configuration Guide](./HTTPS-CONFIGURATION.md))

### Verify SIAB is Ready

```bash
# Check SIAB status
./siab-status.sh

# Verify all namespaces
kubectl get namespaces

# Check Istio is running
kubectl get pods -n istio-system

# Verify gateways
kubectl get gateway -n istio-system
```

## Understanding SIAB Architecture

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    External Clients                         │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS (443)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│               Istio Ingress Gateways                        │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │  Admin Gateway      │    │  User Gateway       │        │
│  │  (10.10.30.240)     │    │  (10.10.30.242)     │        │
│  └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ mTLS
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Istio Service Mesh                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ Service A  │←→│ Service B  │←→│ Service C  │          │
│  │ (+ sidecar)│  │ (+ sidecar)│  │ (+ sidecar)│          │
│  └────────────┘  └────────────┘  └────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### Security Layers

1. **Network Security**: Firewalld with CNI-aware rules
2. **Transport Security**: HTTPS for external, mTLS for internal
3. **Identity**: Keycloak OIDC/SAML authentication
4. **Authorization**: Istio AuthorizationPolicies + Kubernetes RBAC
5. **Policy Enforcement**: OPA Gatekeeper
6. **Vulnerability Scanning**: Trivy continuous scanning

## Deployment Methods

### Method 1: Using kubectl (Basic)

Best for simple applications without special requirements.

```bash
kubectl apply -f my-app.yaml
```

### Method 2: Using Helm Charts (Recommended)

Best for complex applications with configurable parameters.

```bash
helm install my-app ./my-chart -n my-namespace
```

### Method 3: Using SIAB Application CRD

Best for leveraging SIAB's built-in features (automatic Istio integration, Keycloak auth, etc.).

```yaml
apiVersion: siab.local/v1alpha1
kind: SIABApplication
metadata:
  name: my-app
spec:
  # Application spec
```

### Method 4: Using SIAB Catalog

Best for quick deployment of pre-configured applications.

Access the catalog at: https://catalog.siab.local

## Security Considerations

### Namespace Creation

Always create a dedicated namespace with Istio injection enabled:

```bash
# Create namespace
kubectl create namespace my-app

# Enable Istio sidecar injection
kubectl label namespace my-app istio-injection=enabled

# Verify label
kubectl get namespace my-app --show-labels
```

### Network Policies

SIAB uses network policies for pod-to-pod communication control:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: my-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - {}  # Allow all ingress (adjust as needed)
```

### Security Contexts

Always define security contexts for your pods:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
  - name: app
    image: my-app:latest
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true
```

## Step-by-Step Examples

### Example 1: Deploy a Simple Web Application

#### Step 1: Create Namespace

```bash
kubectl create namespace web-app
kubectl label namespace web-app istio-injection=enabled
```

#### Step 2: Create Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-app
  namespace: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-app
  template:
    metadata:
      labels:
        app: nginx-app
        version: v1
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101  # nginx user
        fsGroup: 101
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

Apply:
```bash
kubectl apply -f deployment.yaml
```

#### Step 3: Create Service

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-app
  namespace: web-app
  labels:
    app: nginx-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: nginx-app
```

Apply:
```bash
kubectl apply -f service.yaml
```

#### Step 4: Verify Pods Have Istio Sidecars

```bash
# Should show 2/2 (app + istio-proxy)
kubectl get pods -n web-app

# Verify sidecar injection
kubectl get pods -n web-app -o jsonpath='{.items[*].spec.containers[*].name}'
# Should show: nginx istio-proxy
```

#### Step 5: Create VirtualService for External Access

```yaml
# virtualservice.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: nginx-app
  namespace: istio-system
spec:
  hosts:
  - "nginx.apps.siab.local"
  gateways:
  - user-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: nginx-app.web-app.svc.cluster.local
        port:
          number: 80
```

Apply:
```bash
kubectl apply -f virtualservice.yaml
```

#### Step 6: Access Your Application

```bash
# Test HTTP redirect
curl -I http://nginx.apps.siab.local
# Should return: HTTP/1.1 301 Moved Permanently
# location: https://nginx.apps.siab.local/

# Test HTTPS access
curl -k https://nginx.apps.siab.local
```

### Example 2: Deploy a Database with Persistence

#### Step 1: Create Namespace

```bash
kubectl create namespace database
kubectl label namespace database istio-injection=enabled
```

#### Step 2: Create PersistentVolumeClaim

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: database
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn  # SIAB uses Longhorn for storage
  resources:
    requests:
      storage: 10Gi
```

Apply:
```bash
kubectl apply -f pvc.yaml
```

#### Step 3: Create Secret for Database Credentials

```bash
kubectl create secret generic postgres-secret \
  --from-literal=postgres-password=YourSecurePassword \
  -n database
```

#### Step 4: Create StatefulSet

```yaml
# statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: database
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        version: v1
    spec:
      securityContext:
        fsGroup: 999
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
```

Apply:
```bash
kubectl apply -f statefulset.yaml
```

#### Step 5: Create Service

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: database
  labels:
    app: postgres
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
  selector:
    app: postgres
```

Apply:
```bash
kubectl apply -f service.yaml
```

#### Step 6: Configure DestinationRule for Database (Disable mTLS)

Databases typically don't support Istio sidecars, so we need to disable mTLS:

```yaml
# destinationrule.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgres-mtls-disable
  namespace: istio-system
spec:
  host: postgres.database.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
```

Apply:
```bash
kubectl apply -f destinationrule.yaml
```

#### Step 7: Test Database Connection

```bash
# Create a test pod
kubectl run -it --rm postgres-client \
  --image=postgres:15-alpine \
  --restart=Never \
  -n database -- \
  psql -h postgres.database.svc.cluster.local -U postgres
```

## Exposing Applications via Istio

### Prerequisites for External Access

1. **Create a VirtualService** pointing to your service
2. **Attach to the appropriate Gateway** (user-gateway or admin-gateway)
3. **Configure DNS or /etc/hosts** to point your hostname to the ingress IP

### VirtualService Template

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
  namespace: istio-system  # VirtualServices should be in istio-system
spec:
  hosts:
  - "my-app.apps.siab.local"  # Your application hostname
  gateways:
  - user-gateway  # or admin-gateway for admin apps
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: my-app.my-namespace.svc.cluster.local
        port:
          number: 80
```

### Configure DNS/Hosts File

On your client machine:

```bash
# Linux/Mac: /etc/hosts
# Windows: C:\Windows\System32\drivers\etc\hosts

10.10.30.242  my-app.apps.siab.local
10.10.30.240  admin-app.siab.local
```

### Test Access

```bash
# Test HTTP redirect
curl -I http://my-app.apps.siab.local

# Test HTTPS access
curl -k -I https://my-app.apps.siab.local
```

## Integrating with Keycloak

### Enable Authentication for Your Application

#### Step 1: Create Keycloak Client

1. Access Keycloak: https://keycloak.siab.local
2. Login with admin credentials
3. Navigate to: Clients → Create
4. Configure:
   - Client ID: `my-app`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://my-app.apps.siab.local/*`

#### Step 2: Create AuthorizationPolicy

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: my-app-require-jwt
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  action: ALLOW
  rules:
  - to:
    - operation:
        hosts:
        - "my-app.apps.siab.local"
    when:
    - key: request.auth.claims[iss]
      values:
      - "https://keycloak.siab.local/realms/siab"
```

#### Step 3: Configure Your Application

Configure your application to use Keycloak for OIDC authentication:

```yaml
env:
- name: OAUTH2_PROXY_PROVIDER
  value: "keycloak-oidc"
- name: OAUTH2_PROXY_CLIENT_ID
  value: "my-app"
- name: OAUTH2_PROXY_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: keycloak-client-secret
      key: secret
- name: OAUTH2_PROXY_OIDC_ISSUER_URL
  value: "https://keycloak.siab.local/realms/siab"
```

## Monitoring and Observability

### Grafana Dashboards

Access Grafana: https://grafana.siab.local

Pre-configured dashboards:
- Kubernetes Cluster Monitoring
- Istio Service Mesh
- Application Performance
- Custom application metrics (if instrumented)

### Viewing Application Logs

```bash
# View pod logs
kubectl logs -n my-namespace my-pod-name

# Follow logs
kubectl logs -n my-namespace my-pod-name -f

# View logs from all replicas
kubectl logs -n my-namespace -l app=my-app --all-containers=true
```

### Istio Traffic Metrics

```bash
# View service metrics
kubectl exec -it -n istio-system deployment/istiod -- \
  pilot-discovery request GET /debug/edsz

# View proxy configuration
kubectl exec -it -n my-namespace my-pod-name -c istio-proxy -- \
  curl localhost:15000/config_dump
```

## Troubleshooting

### Pod Not Starting

```bash
# Describe pod for events
kubectl describe pod -n my-namespace my-pod-name

# Check pod logs
kubectl logs -n my-namespace my-pod-name

# Check if sidecar injection failed
kubectl get pod -n my-namespace my-pod-name -o jsonpath='{.spec.containers[*].name}'
```

### Application Not Accessible via HTTPS

```bash
# Check VirtualService
kubectl get virtualservice -n istio-system my-app -o yaml

# Check Gateway
kubectl get gateway -n istio-system user-gateway -o yaml

# Check ingress logs
kubectl logs -n istio-system -l istio=ingress-user --tail=50

# Test from within cluster
kubectl run -it --rm test-curl --image=curlimages/curl --restart=Never -- \
  curl -I http://my-app.my-namespace.svc.cluster.local
```

### mTLS Issues

```bash
# Check PeerAuthentication
kubectl get peerauthentication -A

# Check DestinationRules
kubectl get destinationrule -A | grep my-app

# Verify pod has sidecar
kubectl get pod -n my-namespace my-pod-name -o jsonpath='{.spec.containers[*].name}'
```

### Network Policy Blocking Traffic

```bash
# Check network policies
kubectl get networkpolicies -n my-namespace

# Temporarily test without network policy
kubectl delete networkpolicy my-policy -n my-namespace

# Re-create if needed
kubectl apply -f my-networkpolicy.yaml
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n my-namespace

# Check Longhorn volumes
kubectl get volumes -n longhorn-system

# Access Longhorn UI
# https://longhorn.siab.local
```

## Best Practices

1. **Always use namespaces** - Isolate applications in dedicated namespaces
2. **Enable Istio injection** - Label namespaces with `istio-injection=enabled`
3. **Use security contexts** - Run containers as non-root with minimal privileges
4. **Implement health checks** - Define liveness and readiness probes
5. **Use secrets for sensitive data** - Never hard-code credentials
6. **Set resource limits** - Define CPU and memory requests/limits
7. **Use PersistentVolumes** - For stateful applications
8. **Monitor your applications** - Use Grafana dashboards and logs
9. **Test thoroughly** - Validate in development before production
10. **Document your deployments** - Maintain deployment manifests in version control

## Additional Resources

- [SIAB Quick Start](../QUICK-START.md)
- [Security Configuration](../SECURITY.md)
- [Firewalld Configuration](./FIREWALLD-CONFIGURATION.md)
- [HTTPS Configuration](./HTTPS-CONFIGURATION.md)
- [Istio Documentation](https://istio.io/latest/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Getting Help

- Check logs: `kubectl logs` and `siab-diagnose.sh`
- Review status: `siab-status.sh`
- Test connectivity: `test-https-access.sh`
- Report issues: https://github.com/morbidsteve/SIAB/issues
