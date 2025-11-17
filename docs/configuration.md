# Configuration Guide

## Environment Variables

Configure SIAB installation using environment variables:

### Domain Configuration

```bash
# Primary domain for the platform
export SIAB_DOMAIN="mycompany.com"

# Admin email for certificates
export SIAB_ADMIN_EMAIL="admin@mycompany.com"
```

### Component Selection

```bash
# Skip monitoring stack (Prometheus/Grafana)
export SIAB_SKIP_MONITORING="false"

# Skip storage (MinIO)
export SIAB_SKIP_STORAGE="false"

# Single node deployment
export SIAB_SINGLE_NODE="true"
```

### Resource Configuration

```bash
# MinIO storage size
export SIAB_MINIO_SIZE="100Gi"
```

### Version Pinning

```bash
# Pin specific versions
export RKE2_VERSION="v1.28.4+rke2r1"
export ISTIO_VERSION="1.20.1"
export KEYCLOAK_VERSION="23.0.3"
```

## Post-Installation Configuration

### Keycloak Configuration

#### Create a New Realm

1. Access Keycloak admin console
2. Click "Create Realm"
3. Import or configure your realm

#### Configure OIDC Client

For application integration:

```json
{
  "clientId": "my-app",
  "enabled": true,
  "publicClient": false,
  "redirectUris": ["https://myapp.siab.local/*"],
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false
}
```

### MinIO Configuration

#### Create a Bucket

```bash
# Port-forward to MinIO
kubectl port-forward svc/minio 9000:9000 -n minio

# Use mc client
mc alias set siab http://localhost:9000 <access-key> <secret-key>
mc mb siab/my-bucket
```

#### Set Bucket Policy

```bash
mc policy set download siab/my-bucket/public/
```

### Istio Configuration

#### Custom Gateway

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: custom-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: custom-cert
      hosts:
        - "*.custom.com"
```

#### Traffic Policies

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: circuit-breaker
spec:
  host: my-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 60s
```

### Gatekeeper Policies

#### Add Custom Constraint

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireLabels
metadata:
  name: require-team-label
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    labels:
      - "team"
      - "app"
```

### Network Policies

#### Allow Specific Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-api
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 203.0.113.0/24
      ports:
        - protocol: TCP
          port: 443
```

## Resource Quotas

### Namespace Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "50"
```

### Limit Ranges

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
```

## TLS Certificate Configuration

### Use Let's Encrypt

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@mycompany.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: istio
```

### Custom CA

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: custom-ca-issuer
spec:
  ca:
    secretName: custom-ca-key-pair
```

## Backup Configuration

### etcd Backup

```bash
# Manual etcd snapshot
/var/lib/rancher/rke2/bin/etcdctl \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  snapshot save /backup/etcd-snapshot.db
```

### Application Data Backup

Configure Velero for application backups:

```bash
velero backup create my-backup --include-namespaces=production
```

## High Availability

### Multi-Node Setup

Edit `/etc/rancher/rke2/config.yaml`:

```yaml
server: https://first-server:9345
token: <node-token>
```

### Load Balancer

For production, use an external load balancer for the API server (port 6443) and Istio ingress (ports 80/443).
