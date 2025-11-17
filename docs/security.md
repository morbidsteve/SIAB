# Security Guide

SIAB is designed with security as the highest priority. This guide explains the security features and best practices.

## Security Architecture

### Defense in Depth

SIAB implements multiple layers of security:

```
┌─────────────────────────────────────────┐
│ Application Layer                       │
│ - Container scanning                    │
│ - Image signing verification            │
│ - Application-level auth (Keycloak)     │
├─────────────────────────────────────────┤
│ Network Layer                           │
│ - mTLS everywhere (Istio)               │
│ - Network policies                      │
│ - Zero-trust networking                 │
├─────────────────────────────────────────┤
│ Platform Layer                          │
│ - Policy enforcement (OPA Gatekeeper)   │
│ - Pod Security Standards                │
│ - RBAC                                  │
│ - Audit logging                         │
├─────────────────────────────────────────┤
│ Infrastructure Layer                    │
│ - CIS hardened Kubernetes (RKE2)        │
│ - SELinux enforcing                     │
│ - Encrypted secrets (at rest)           │
│ - Firewall rules                        │
└─────────────────────────────────────────┘
```

## Security Features

### 1. Container Security

#### Vulnerability Scanning

Trivy Operator automatically scans:
- Container images for CVEs
- Kubernetes configurations
- Infrastructure as Code
- Secrets in code

```bash
# View vulnerability reports
kubectl get vulnerabilityreports -A

# Check specific image
kubectl get vulnerabilityreport -n default <pod-name>-<container> -o yaml
```

#### Image Signing (Optional)

Enable Cosign verification:

```yaml
spec:
  security:
    requireImageSigning: true
```

#### Runtime Security

Falco monitors for:
- Privilege escalation attempts
- Unexpected system calls
- File integrity violations
- Network anomalies

### 2. Network Security

#### Mutual TLS (mTLS)

Istio provides automatic mTLS for all service-to-service communication:

```bash
# Verify mTLS status
istioctl authn tls-check <pod-name>.<namespace>
```

Features:
- Automatic certificate rotation
- Strong cipher suites only
- TLS 1.2+ minimum

#### Network Policies

Default deny-all with explicit allows:

```yaml
# Example: Allow only necessary traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-netpol
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: database
      ports:
        - port: 5432
```

#### Zero-Trust Networking

Every connection is:
1. Encrypted (mTLS)
2. Authenticated (service identity)
3. Authorized (policies)
4. Audited (logs)

### 3. Identity & Access Management

#### Keycloak Integration

Features:
- Single Sign-On (SSO)
- Multi-factor Authentication (MFA)
- Role-Based Access Control (RBAC)
- OIDC/SAML support

#### Kubernetes RBAC

Principle of least privilege:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]
  - apiGroups: ["siab.io"]
    resources: ["siabapplications"]
    verbs: ["get", "list", "create", "update"]
```

### 4. Policy Enforcement

#### OPA Gatekeeper

Enforces policies at admission time:

```yaml
# Constraint: Require non-root
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNonRoot
metadata:
  name: require-non-root
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

#### Pod Security Standards

Enforced profile: **Restricted**

Prevents:
- Privileged containers
- Host namespace access
- Privilege escalation
- Root users
- Insecure capabilities

### 5. Secrets Management

#### Encryption at Rest

All secrets encrypted in etcd using AES-CBC:

```yaml
# /etc/rancher/rke2/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-key>
```

#### External Secrets (Recommended)

Use External Secrets Operator for:
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- Google Secret Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "siab-app"
```

### 6. Audit Logging

#### Kubernetes Audit Logs

All API requests logged:

```bash
# View audit logs
tail -f /var/log/kubernetes/audit/audit.log
```

Captures:
- Who made the request
- What was requested
- When it occurred
- Whether it was allowed

#### Istio Access Logs

All HTTP requests logged:

```bash
kubectl logs -n istio-system -l app=istiod
```

## Security Best Practices

### Application Development

1. **Never use :latest tag**
   ```yaml
   # Bad
   image: nginx:latest

   # Good
   image: nginx:1.25.3-alpine
   ```

2. **Set resource limits**
   ```yaml
   resources:
     limits:
       cpu: "500m"
       memory: "512Mi"
   ```

3. **Use read-only filesystem**
   ```yaml
   securityContext:
     readOnlyRootFilesystem: true
   ```

4. **Drop all capabilities**
   ```yaml
   securityContext:
     capabilities:
       drop:
         - ALL
   ```

5. **Use non-root user**
   ```dockerfile
   FROM alpine:3.19
   RUN adduser -D appuser
   USER appuser
   ```

### Deployment

1. **Enable vulnerability scanning**
   ```yaml
   security:
     scanOnDeploy: true
     blockCriticalVulns: true
   ```

2. **Use authentication**
   ```yaml
   auth:
     enabled: true
     requiredRoles: ["user"]
   ```

3. **Apply network policies**
   ```yaml
   networking:
     allowInternetEgress: false
   ```

4. **Enable rate limiting**
   ```yaml
   ingress:
     rateLimit:
       enabled: true
       requestsPerSecond: 100
   ```

### Operations

1. **Regular updates**
   ```bash
   # Update platform components
   helm upgrade istio-base istio/base -n istio-system
   ```

2. **Monitor security events**
   ```bash
   # Check Falco alerts
   kubectl logs -n falco -l app=falco
   ```

3. **Review audit logs**
   ```bash
   # Check for unauthorized access
   grep "Forbidden" /var/log/kubernetes/audit/audit.log
   ```

4. **Scan images regularly**
   ```bash
   # Trigger manual scan
   kubectl annotate pod <pod-name> trivy-operator.aquasecurity.github.io/scan-trigger=true
   ```

## Compliance

### CIS Kubernetes Benchmark

RKE2 is CIS hardened by default. Verify compliance:

```bash
# Download CIS benchmark tool
curl -L https://github.com/aquasecurity/kube-bench/releases/download/v0.7.0/kube-bench_0.7.0_linux_amd64.tar.gz | tar xz

# Run benchmark
./kube-bench run --targets=master,node,etcd
```

### SOC 2 / ISO 27001

SIAB provides controls for:
- Access control (Keycloak + RBAC)
- Encryption (mTLS, secrets encryption)
- Audit logging (comprehensive logs)
- Change management (GitOps ready)
- Vulnerability management (Trivy)
- Network segmentation (Network Policies)

## Security Incident Response

### Suspected Compromise

1. **Isolate the workload**
   ```bash
   kubectl scale deployment <name> --replicas=0
   ```

2. **Collect evidence**
   ```bash
   kubectl logs <pod-name> > evidence-logs.txt
   kubectl describe pod <pod-name> > evidence-pod.txt
   ```

3. **Check audit logs**
   ```bash
   grep <pod-name> /var/log/kubernetes/audit/audit.log
   ```

4. **Review network traffic**
   ```bash
   # Check Istio logs
   kubectl logs -n istio-system <istio-proxy-container>
   ```

### Vulnerability Discovered

1. **Assess impact**
   ```bash
   kubectl get vulnerabilityreport -A -o json | \
     jq '.items[] | select(.report.summary.criticalCount > 0)'
   ```

2. **Update affected images**
   ```yaml
   spec:
     image: myapp:patched-version
   ```

3. **Force re-scan**
   ```bash
   kubectl delete pod <pod-name>
   ```

## Security Checklist

Before going to production:

- [ ] Update all default passwords
- [ ] Configure external authentication (Keycloak)
- [ ] Enable MFA for admin accounts
- [ ] Configure backup strategy
- [ ] Set up monitoring and alerting
- [ ] Review and update network policies
- [ ] Configure log aggregation
- [ ] Test incident response procedures
- [ ] Document security architecture
- [ ] Train team on security practices
- [ ] Schedule regular security audits
- [ ] Configure automated security updates

## Additional Resources

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)
