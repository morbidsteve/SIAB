# Application Deployment Guide

## Overview

SIAB provides the `SIABApplication` Custom Resource Definition (CRD) for easy, secure application deployment. This abstraction handles:

- Deployment creation with security contexts
- Service mesh integration (Istio sidecar)
- Network policies
- Optional authentication (Keycloak)
- Optional storage (PVC, MinIO)
- Health checks
- Auto-scaling

## Basic Deployment

### Minimal Example

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: my-app
  namespace: default
spec:
  image: myregistry/myapp:v1.0.0
  port: 8080
```

This creates:
- Deployment with security contexts
- Service
- Network policies
- Istio sidecar injection

### With External Access

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: web-app
spec:
  image: myregistry/web:v2.0.0
  replicas: 3
  port: 8080

  ingress:
    enabled: true
    hostname: webapp.siab.local
    tls: true
```

## Security Configuration

### Vulnerability Scanning

```yaml
spec:
  security:
    # Scan image before deployment
    scanOnDeploy: true

    # Block if critical CVEs found
    blockCriticalVulns: true

    # Also block high severity
    blockHighVulns: true

    # Require signed images (Cosign)
    requireImageSigning: false
```

### Container Security

```yaml
spec:
  security:
    # Run as non-root user
    runAsNonRoot: true

    # Read-only filesystem
    readOnlyRootFilesystem: true

    # No privilege escalation
    allowPrivilegeEscalation: false

    # Seccomp profile
    seccompProfile: RuntimeDefault
```

## Authentication & Authorization

### Keycloak Integration

```yaml
spec:
  auth:
    enabled: true

    # Required roles (OR logic)
    requiredRoles:
      - app-user
      - app-admin

    # Required groups
    requiredGroups:
      - developers

    # Public paths (no auth needed)
    publicPaths:
      - /health
      - /metrics
      - /api/public
```

This automatically:
- Creates Istio RequestAuthentication
- Configures JWT validation
- Sets up AuthorizationPolicy

## Storage Options

### Persistent Volume

```yaml
spec:
  storage:
    enabled: true
    size: "10Gi"
    storageClass: "local-path"
    mountPath: "/data"
    accessMode: ReadWriteOnce
```

### MinIO Object Storage

```yaml
spec:
  objectStorage:
    enabled: true
    bucketName: "my-app-data"
    quotaSize: "10Gi"
    injectCredentials: true
```

Environment variables injected:
- `MINIO_ENDPOINT`
- `MINIO_ACCESS_KEY`
- `MINIO_SECRET_KEY`
- `MINIO_BUCKET_NAME`

## Resource Management

### Resource Limits

```yaml
spec:
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
```

### Auto-Scaling

```yaml
spec:
  scaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilization: 70
    targetMemoryUtilization: 80
```

## Network Configuration

### Network Policies

```yaml
spec:
  networking:
    # Allow outbound internet
    allowInternetEgress: false

    # Specific egress ports
    allowedEgressPorts:
      - 5432  # PostgreSQL
      - 6379  # Redis

    # Allowed CIDR blocks
    allowedEgressCIDRs:
      - "10.0.0.0/8"

    # Allow ingress from namespaces
    allowIngressFrom:
      - frontend
      - api-gateway
```

### Rate Limiting

```yaml
spec:
  ingress:
    enabled: true
    hostname: api.siab.local
    rateLimit:
      enabled: true
      requestsPerSecond: 100
      burstSize: 200
```

### CORS

```yaml
spec:
  ingress:
    cors:
      enabled: true
      allowOrigins:
        - "https://frontend.siab.local"
      allowMethods:
        - GET
        - POST
        - PUT
      allowHeaders:
        - Authorization
        - Content-Type
```

## Health Checks

### Configuration

```yaml
spec:
  healthCheck:
    enabled: true
    path: "/health"
    port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
```

This configures both:
- Liveness probe (restarts unhealthy containers)
- Readiness probe (removes from service)

## Environment Variables

### Static Values

```yaml
spec:
  env:
    - name: APP_ENV
      value: "production"
    - name: LOG_LEVEL
      value: "info"
```

### From Secrets

```yaml
spec:
  env:
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

### From ConfigMaps

```yaml
spec:
  env:
    - name: CONFIG_FILE
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: config.json
```

## Deployment Lifecycle

### Check Status

```bash
# List all applications
kubectl get siabapplications

# Detailed status
kubectl describe siabapplication my-app

# Check generated resources
kubectl get deployment,svc,networkpolicy -l siab.io/application=my-app
```

### Status Phases

- **Pending**: Application created
- **Scanning**: Vulnerability scan in progress
- **Deploying**: Resources being created
- **Running**: Application healthy
- **Failed**: Deployment failed
- **Blocked**: Security policy violation

### Update Application

```bash
# Edit the CRD
kubectl edit siabapplication my-app

# Or apply updated YAML
kubectl apply -f my-app.yaml
```

### Delete Application

```bash
kubectl delete siabapplication my-app
```

This cleans up all created resources.

## Best Practices

1. **Always specify image tags** - Never use `:latest`
2. **Set resource limits** - Prevent resource exhaustion
3. **Enable security scanning** - Catch vulnerabilities early
4. **Use health checks** - Ensure application reliability
5. **Apply network policies** - Principle of least privilege
6. **Enable authentication** - Secure your endpoints
7. **Use secrets properly** - Never hardcode credentials

## Troubleshooting

### Application Not Starting

```bash
# Check operator logs
kubectl logs -n siab-system -l app=siab-operator

# Check events
kubectl get events --field-selector involvedObject.name=my-app
```

### Security Scan Blocking Deployment

```bash
# Check vulnerability report
kubectl describe siabapplication my-app | grep -A 20 "Vulnerability Summary"
```

### Network Connectivity Issues

```bash
# Verify network policies
kubectl get networkpolicy -l siab.io/application=my-app -o yaml

# Test connectivity
kubectl exec -it <pod> -- curl http://target-service:port
```
