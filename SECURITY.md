# Security Configuration

## Overview

SIAB is designed with security as a foundational principle. This document outlines the security features and best practices for production deployments.

## Security Features

### 1. HTTPS-Only Access

**All external access to SIAB services is enforced over HTTPS.** HTTP requests are automatically redirected to HTTPS.

- ✅ Automatic HTTP to HTTPS redirect on all gateways
- ✅ TLS termination at Istio ingress gateways
- ✅ Self-signed certificates managed by cert-manager
- ✅ Support for custom/production certificates

**Documentation:** [HTTPS Configuration Guide](./docs/HTTPS-CONFIGURATION.md)

### 2. Firewall Configuration

**SIAB requires proper firewalld configuration to work with RKE2 and Canal networking.**

⚠️ **IMPORTANT**: Disabling firewalld entirely is NOT recommended for production. Instead, configure it properly using our provided script.

**Quick Setup:**
```bash
sudo /home/fscyber/soc/SIAB/scripts/configure-firewalld.sh
```

**Features:**
- ✅ CNI interfaces in trusted zone for pod-to-pod communication
- ✅ Required ports opened for RKE2, Canal, and Istio
- ✅ Pod and service CIDRs configured as trusted sources
- ✅ Masquerading enabled for container networking

**Documentation:** [Firewalld Configuration Guide](./docs/FIREWALLD-CONFIGURATION.md)

### 3. Mutual TLS (mTLS)

**All service-to-service communication within the mesh uses mTLS.**

- ✅ STRICT mTLS mode for internal services
- ✅ PERMISSIVE mode for ingress gateways (to accept external traffic)
- ✅ Automatic certificate rotation via Istio
- ✅ Identity-based service authentication

**Configuration:** `manifests/istio/peer-authentication.yaml`

### 4. Identity and Access Management

**Keycloak provides enterprise-grade IAM:**

- ✅ OIDC/SAML authentication
- ✅ Role-based access control (RBAC)
- ✅ Multi-factor authentication (MFA) support
- ✅ Integration with external identity providers

**Access:** https://keycloak.siab.local

### 5. Network Policies

**Kubernetes NetworkPolicies control pod-to-pod communication:**

- ✅ Default deny-all policy in namespaces
- ✅ Explicit allow rules for required communication
- ✅ Calico GlobalNetworkPolicy for cluster-wide rules
- ✅ Istio authorization policies for application-layer control

**Configuration:** `manifests/security/network-policies.yaml`

### 6. Policy Enforcement

**OPA Gatekeeper enforces security policies:**

- ✅ Pod security standards
- ✅ Resource constraints
- ✅ Image registry restrictions
- ✅ Security context enforcement

**Configuration:** `manifests/security/gatekeeper-constraints.yaml`

### 7. Vulnerability Scanning

**Trivy continuously scans containers for vulnerabilities:**

- ✅ Automatic scanning of all deployed images
- ✅ CVE database updates
- ✅ Integration with admission control
- ✅ Vulnerability reports and alerts

### 8. SELinux

**SELinux is enforcing by default on Rocky Linux:**

- ✅ Provides mandatory access control (MAC)
- ✅ Isolates containers from host
- ✅ Configured for RKE2 compatibility

**Note:** Istio CNI requires privileged containers when SELinux is enforcing.

## Production Security Checklist

### Before Deploying to Production

- [ ] **Replace self-signed certificates** with trusted CA certificates (Let's Encrypt, commercial CA)
- [ ] **Configure firewalld** using the provided script
- [ ] **Set up external authentication** in Keycloak (LDAP, SAML, etc.)
- [ ] **Enable MFA** for administrative accounts
- [ ] **Review and customize** network policies for your environment
- [ ] **Configure vulnerability scanning policies** and alert thresholds
- [ ] **Set up monitoring and alerting** for security events
- [ ] **Perform security audit** of all deployed applications
- [ ] **Implement backup and disaster recovery** procedures
- [ ] **Document security procedures** for your team

### Regular Security Maintenance

- [ ] **Update RKE2** to latest stable version
- [ ] **Update Istio** to latest supported version
- [ ] **Review Trivy scan results** weekly
- [ ] **Rotate certificates** before expiration (cert-manager handles this automatically)
- [ ] **Review access logs** for anomalies
- [ ] **Update OPA policies** as requirements change
- [ ] **Audit user access** and remove unused accounts
- [ ] **Review firewall rules** and remove unused ports

## Service Access URLs

All services are accessible via HTTPS only:

### Administrative Services

| Service | URL | Purpose |
|---------|-----|---------|
| Keycloak | https://keycloak.siab.local | Identity and Access Management |
| MinIO Console | https://minio.siab.local | Object Storage Management |
| Grafana | https://grafana.siab.local | Monitoring and Dashboards |
| Kubernetes Dashboard | https://k8s-dashboard.siab.local | Kubernetes Web UI |
| Longhorn UI | https://longhorn.siab.local | Storage Management |

### User Services

| Service | URL | Purpose |
|---------|-----|---------|
| Main Dashboard | https://dashboard.siab.local | SIAB Landing Page |
| App Catalog | https://catalog.siab.local | Application Catalog |
| Applications | https://*.apps.siab.local | Deployed Applications |

## Firewall Ports Reference

### RKE2 Ports

| Port(s) | Protocol | Purpose |
|---------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 9345 | TCP | RKE2 Supervisor |
| 10250 | TCP | Kubelet |
| 2379-2380 | TCP | etcd |
| 30000-32767 | TCP | NodePort range |

### Canal (Calico + Flannel) Ports

| Port(s) | Protocol | Purpose |
|---------|----------|---------|
| 8472 | UDP | Flannel VXLAN |
| 4789 | UDP | Flannel VXLAN (alt) |
| 51820-51821 | UDP | Flannel Wireguard |
| 179 | TCP | Calico BGP |
| 5473 | TCP | Calico Typha |

### Istio Ports

| Port(s) | Protocol | Purpose |
|---------|----------|---------|
| 80 | TCP | HTTP ingress (redirects to HTTPS) |
| 443 | TCP | HTTPS ingress |
| 15010-15017 | TCP | Istio control plane |
| 15021 | TCP | Health checks |
| 15090 | TCP | Metrics |

## Troubleshooting Security Issues

### Connection Issues After Enabling Firewalld

**Symptom:** "No route to host" errors, pod-to-pod connectivity failures

**Solution:**
1. Verify CNI interfaces are in trusted zone:
   ```bash
   sudo firewall-cmd --zone=trusted --list-interfaces
   ```

2. Check pod CIDR is trusted:
   ```bash
   sudo firewall-cmd --zone=trusted --list-sources
   ```

3. Re-run configuration script:
   ```bash
   sudo /home/fscyber/soc/SIAB/scripts/configure-firewalld.sh
   ```

### Certificate Errors

**Symptom:** Browser shows "Not Secure" or certificate warnings

**Expected:** Self-signed certificates will show warnings - this is normal for development

**Production Solution:** Configure Let's Encrypt or use commercial certificates

### HTTPS Not Working

**Symptom:** Cannot access services via HTTPS

**Troubleshooting:**
1. Check certificate exists:
   ```bash
   kubectl get certificate -n istio-system siab-gateway-cert
   ```

2. Check ingress gateway pods:
   ```bash
   kubectl get pods -n istio-system | grep ingress
   ```

3. Check firewall allows port 443:
   ```bash
   sudo firewall-cmd --list-ports | grep 443
   ```

## Security References

- [RKE2 Security Documentation](https://docs.rke2.io/security/hardening_guide)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/overview/)
- [NIST Kubernetes Hardening Guide](https://www.nist.gov/publications/application-container-security-guide)

## Reporting Security Issues

If you discover a security vulnerability in SIAB, please report it responsibly:

1. **Do NOT** create a public GitHub issue
2. Email security details to: [your-security-email@domain.com]
3. Include: detailed description, steps to reproduce, potential impact
4. Allow time for investigation and patching before public disclosure

## License

See [LICENSE](./LICENSE) for details.
