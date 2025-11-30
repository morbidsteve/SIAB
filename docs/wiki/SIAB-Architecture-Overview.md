# SIAB - Secure Infrastructure Application Box

## Executive Summary

SIAB (Secure Infrastructure Application Box) is an enterprise-grade, security-first Kubernetes platform that provides a complete, hardened runtime environment for deploying and managing containerized applications. It implements defense-in-depth security principles with multiple layers of protection including identity management, network security, vulnerability scanning, policy enforcement, and comprehensive audit logging.

---

## Platform Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SIAB PLATFORM ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         EXTERNAL ACCESS LAYER                            │    │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                │    │
│  │  │  Admin Users  │  │ Operators     │  │  End Users    │                │    │
│  │  │  (siab-admin) │  │ (siab-operator│  │  (siab-user)  │                │    │
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘                │    │
│  │          │                  │                  │                         │    │
│  │          ▼                  ▼                  ▼                         │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    KEYCLOAK SSO GATEWAY                         │    │    │
│  │  │         Identity Provider │ OIDC/SAML │ MFA │ RBAC              │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         INGRESS LAYER (ISTIO)                           │    │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐             │    │
│  │  │    ADMIN GATEWAY        │    │     USER GATEWAY        │             │    │
│  │  │  ┌─────────────────┐    │    │  ┌─────────────────┐    │             │    │
│  │  │  │ TLS Termination │    │    │  │ TLS Termination │    │             │    │
│  │  │  │ JWT Validation  │    │    │  │ JWT Validation  │    │             │    │
│  │  │  │ Rate Limiting   │    │    │  │ OAuth2 Proxy    │    │             │    │
│  │  │  └─────────────────┘    │    │  └─────────────────┘    │             │    │
│  │  │  Services:              │    │  Services:              │             │    │
│  │  │  • Keycloak             │    │  • Dashboard            │             │    │
│  │  │  • Grafana              │    │  • App Deployer         │             │    │
│  │  │  • K8s Dashboard        │    │  • User Applications    │             │    │
│  │  │  • MinIO Console        │    │  • App Catalog          │             │    │
│  │  │  • Longhorn UI          │    │                         │             │    │
│  │  └─────────────────────────┘    └─────────────────────────┘             │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                       SERVICE MESH LAYER (ISTIO)                        │    │
│  │                                                                          │    │
│  │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │    │
│  │   │   mTLS       │  │  Traffic     │  │  Telemetry   │                  │    │
│  │   │  Encryption  │  │  Management  │  │  & Tracing   │                  │    │
│  │   └──────────────┘  └──────────────┘  └──────────────┘                  │    │
│  │                                                                          │    │
│  │   Every pod-to-pod communication is encrypted and authenticated         │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                       SECURITY ENFORCEMENT LAYER                         │    │
│  │                                                                          │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │  OPA GATEKEEPER │  │     TRIVY       │  │  NETWORK        │          │    │
│  │  │                 │  │                 │  │  POLICIES       │          │    │
│  │  │ • Pod Security  │  │ • CVE Scanning  │  │                 │          │    │
│  │  │ • Image Policy  │  │ • SBOM Analysis │  │ • Namespace     │          │    │
│  │  │ • Resource      │  │ • Config Audit  │  │   Isolation     │          │    │
│  │  │   Constraints   │  │ • Secret Scan   │  │ • Egress Rules  │          │    │
│  │  │ • Label         │  │ • License Check │  │ • Ingress Rules │          │    │
│  │  │   Requirements  │  │                 │  │                 │          │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        APPLICATION LAYER                                 │    │
│  │                                                                          │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │    │
│  │  │   User      │  │   User      │  │   User      │  │   System    │     │    │
│  │  │   App 1     │  │   App 2     │  │   App N     │  │   Services  │     │    │
│  │  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │  │             │     │    │
│  │  │  │Sidecar│  │  │  │Sidecar│  │  │  │Sidecar│  │  │             │     │    │
│  │  │  │Proxy  │  │  │  │Proxy  │  │  │  │Proxy  │  │  │             │     │    │
│  │  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │  │             │     │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         STORAGE LAYER                                    │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐             │    │
│  │  │      LONGHORN           │    │        MinIO            │             │    │
│  │  │  Distributed Block      │    │   S3-Compatible Object  │             │    │
│  │  │      Storage            │    │       Storage           │             │    │
│  │  │                         │    │                         │             │    │
│  │  │ • Replicated Volumes    │    │ • Bucket Storage        │             │    │
│  │  │ • Snapshots             │    │ • Versioning            │             │    │
│  │  │ • Backup/Restore        │    │ • Encryption at Rest    │             │    │
│  │  │ • Encryption            │    │ • Access Policies       │             │    │
│  │  └─────────────────────────┘    └─────────────────────────┘             │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                      INFRASTRUCTURE LAYER                                │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    RKE2 KUBERNETES                               │    │    │
│  │  │  • FIPS 140-2 Compliant  • CIS Hardened  • SELinux Enforcing    │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    CANAL CNI (Calico + Flannel)                  │    │    │
│  │  │  • Network Policies  • VXLAN Overlay  • Pod Networking          │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    FIREWALLD + SELinux                           │    │    │
│  │  │  • Host Firewall  • Mandatory Access Control  • Audit Logging   │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Summary

| Component | Purpose | Security Benefit |
|-----------|---------|------------------|
| **RKE2** | Kubernetes distribution | FIPS 140-2 compliant, CIS hardened by default |
| **Istio** | Service mesh | mTLS encryption, traffic policies, observability |
| **Keycloak** | Identity provider | SSO, MFA, RBAC, OIDC/SAML federation |
| **OAuth2 Proxy** | Authentication proxy | Enforces SSO for all applications |
| **OPA Gatekeeper** | Policy engine | Admission control, security constraints |
| **Trivy** | Security scanner | CVE detection, SBOM generation, compliance |
| **Longhorn** | Block storage | Encrypted, replicated persistent volumes |
| **MinIO** | Object storage | S3-compatible, encrypted, versioned storage |
| **Grafana** | Monitoring | Security dashboards, alerting, audit trails |
| **cert-manager** | Certificate management | Automated TLS certificate lifecycle |
| **Canal** | Container networking | Network policies, pod isolation |

---

## Security Layers Summary

### Layer 1: Perimeter Security
- HTTPS-only access with automatic HTTP→HTTPS redirect
- TLS 1.2+ with strong cipher suites
- DDoS protection via rate limiting
- Web Application Firewall capabilities

### Layer 2: Identity & Access
- Centralized SSO via Keycloak
- Role-Based Access Control (RBAC)
- Multi-Factor Authentication (MFA) support
- Session management and token validation

### Layer 3: Network Security
- Service mesh with mTLS (mutual TLS)
- Network policies for namespace isolation
- Micro-segmentation between services
- Encrypted pod-to-pod communication

### Layer 4: Workload Security
- Container vulnerability scanning
- Image signature verification
- Runtime security policies
- Resource constraints and limits

### Layer 5: Data Security
- Encryption at rest for all storage
- Encryption in transit via mTLS
- Secret management via Kubernetes Secrets
- Backup and disaster recovery

### Layer 6: Compliance & Audit
- Comprehensive audit logging
- Policy compliance reporting
- Vulnerability assessment reports
- SBOM (Software Bill of Materials) generation

---

## Related Documentation

- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Keycloak SSO Configuration](./SIAB-Keycloak-SSO.md)
- [Vulnerability Scanning with Trivy](./SIAB-Trivy-Security-Scanning.md)
- [Policy Enforcement with OPA Gatekeeper](./SIAB-OPA-Gatekeeper-Policies.md)
- [Network Security & Istio](./SIAB-Network-Security.md)
- [Compliance & Audit](./SIAB-Compliance-Audit.md)
