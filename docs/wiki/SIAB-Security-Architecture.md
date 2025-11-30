# SIAB Security Architecture

## Defense in Depth Model

SIAB implements a comprehensive defense-in-depth security model with six distinct security layers. Each layer provides independent security controls that work together to protect the platform and its workloads.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         DEFENSE IN DEPTH MODEL                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│    ┌─────────────────────────────────────────────────────────────────────┐      │
│    │ LAYER 6: COMPLIANCE & AUDIT                                         │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │   Audit     │ │  Compliance │ │    SBOM     │ │   Policy    │    │      │
│    │ │   Logging   │ │  Reporting  │ │  Generation │ │  Dashboards │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                      │                                           │
│    ┌─────────────────────────────────▼───────────────────────────────────┐      │
│    │ LAYER 5: DATA SECURITY                                              │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │ Encryption  │ │   Secret    │ │   Backup    │ │    Data     │    │      │
│    │ │  at Rest    │ │ Management  │ │   & DR      │ │  Isolation  │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                      │                                           │
│    ┌─────────────────────────────────▼───────────────────────────────────┐      │
│    │ LAYER 4: WORKLOAD SECURITY                                          │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │    CVE      │ │   Image     │ │  Resource   │ │   Runtime   │    │      │
│    │ │  Scanning   │ │  Policies   │ │   Limits    │ │  Security   │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                      │                                           │
│    ┌─────────────────────────────────▼───────────────────────────────────┐      │
│    │ LAYER 3: NETWORK SECURITY                                           │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │    mTLS     │ │  Network    │ │   Service   │ │   Traffic   │    │      │
│    │ │ Encryption  │ │  Policies   │ │    Mesh     │ │   Control   │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                      │                                           │
│    ┌─────────────────────────────────▼───────────────────────────────────┐      │
│    │ LAYER 2: IDENTITY & ACCESS                                          │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │     SSO     │ │    RBAC     │ │     MFA     │ │   Session   │    │      │
│    │ │  (Keycloak) │ │   Roles     │ │   Support   │ │ Management  │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                      │                                           │
│    ┌─────────────────────────────────▼───────────────────────────────────┐      │
│    │ LAYER 1: PERIMETER SECURITY                                         │      │
│    │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│    │ │    TLS      │ │  Firewall   │ │    Rate     │ │   Ingress   │    │      │
│    │ │ Termination │ │   Rules     │ │  Limiting   │ │   Gateway   │    │      │
│    │ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │      │
│    └─────────────────────────────────────────────────────────────────────┘      │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Request Flow Security

Every request to SIAB passes through multiple security checkpoints before reaching the target application:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              REQUEST SECURITY FLOW                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   USER REQUEST                                                                   │
│        │                                                                         │
│        ▼                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ CHECKPOINT 1: FIREWALL (firewalld)                                      │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ • Source IP validation                                           │     │   │
│   │ │ • Port filtering (only 80/443 allowed externally)               │     │   │
│   │ │ • Rate limiting at network level                                 │     │   │
│   │ │ • Stateful connection tracking                                   │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   │                              │                                           │   │
│   │                    ┌─────────┴─────────┐                                │   │
│   │                    │ PASS      BLOCK   │                                │   │
│   │                    │  ▼          ▼     │                                │   │
│   │                    │  │       ┌──────┐ │                                │   │
│   │                    │  │       │ DROP │ │                                │   │
│   │                    │  │       └──────┘ │                                │   │
│   │                    └─────────┬─────────┘                                │   │
│   └──────────────────────────────┼──────────────────────────────────────────┘   │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ CHECKPOINT 2: TLS TERMINATION (Istio Gateway)                           │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ • TLS 1.2+ enforcement                                           │     │   │
│   │ │ • Certificate validation                                         │     │   │
│   │ │ • HTTP → HTTPS redirect                                          │     │   │
│   │ │ • Cipher suite enforcement                                       │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   │                              │                                           │   │
│   │                    ┌─────────┴─────────┐                                │   │
│   │                    │ VALID    INVALID  │                                │   │
│   │                    │  ▼          ▼     │                                │   │
│   │                    │  │       ┌──────┐ │                                │   │
│   │                    │  │       │ 400  │ │                                │   │
│   │                    │  │       └──────┘ │                                │   │
│   │                    └─────────┬─────────┘                                │   │
│   └──────────────────────────────┼──────────────────────────────────────────┘   │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ CHECKPOINT 3: AUTHENTICATION (Keycloak + OAuth2 Proxy)                  │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ • JWT token validation                                           │     │   │
│   │ │ • Session verification                                           │     │   │
│   │ │ • OAuth2 flow for unauthenticated users                          │     │   │
│   │ │ • Token refresh handling                                         │     │   │
│   │ │ • MFA challenge if configured                                    │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   │                              │                                           │   │
│   │           ┌──────────────────┼──────────────────┐                       │   │
│   │           │ AUTHENTICATED    │  UNAUTHENTICATED │                       │   │
│   │           │      ▼           │         ▼        │                       │   │
│   │           │      │           │  ┌────────────┐  │                       │   │
│   │           │      │           │  │  Redirect  │  │                       │   │
│   │           │      │           │  │ to Keycloak│  │                       │   │
│   │           │      │           │  │   Login    │  │                       │   │
│   │           │      │           │  └────────────┘  │                       │   │
│   │           └──────┼──────────────────────────────┘                       │   │
│   └──────────────────┼──────────────────────────────────────────────────────┘   │
│                      ▼                                                           │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ CHECKPOINT 4: AUTHORIZATION (Istio + RBAC)                              │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ • Role-based access control                                      │     │   │
│   │ │ • JWT claims validation (roles, groups)                          │     │   │
│   │ │ • Service-level authorization policies                           │     │   │
│   │ │ • Namespace access control                                       │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   │                              │                                           │   │
│   │                    ┌─────────┴─────────┐                                │   │
│   │                    │ ALLOWED   DENIED  │                                │   │
│   │                    │   ▼         ▼     │                                │   │
│   │                    │   │      ┌──────┐ │                                │   │
│   │                    │   │      │ 403  │ │                                │   │
│   │                    │   │      └──────┘ │                                │   │
│   │                    └─────────┬─────────┘                                │   │
│   └──────────────────────────────┼──────────────────────────────────────────┘   │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ CHECKPOINT 5: SERVICE MESH (Istio Sidecar)                              │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ • mTLS encryption between services                               │     │   │
│   │ │ • Service identity verification (SPIFFE)                         │     │   │
│   │ │ • Traffic policies enforcement                                   │     │   │
│   │ │ • Circuit breaking / retry logic                                 │     │   │
│   │ │ • Request telemetry collection                                   │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │ DESTINATION: APPLICATION POD                                            │   │
│   │ ┌─────────────────────────────────────────────────────────────────┐     │   │
│   │ │ Request arrives with:                                            │     │   │
│   │ │ • Verified identity (X-Auth-Request-User)                        │     │   │
│   │ │ • Validated roles (X-Auth-Request-Groups)                        │     │   │
│   │ │ • Access token for downstream calls                              │     │   │
│   │ │ • Encrypted channel guarantee                                    │     │   │
│   │ └─────────────────────────────────────────────────────────────────┘     │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Zero Trust Architecture

SIAB implements Zero Trust principles where no user, device, or service is trusted by default:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           ZERO TRUST PRINCIPLES                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     NEVER TRUST, ALWAYS VERIFY                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌───────────────────────┐  ┌───────────────────────┐  ┌──────────────────────┐ │
│  │                       │  │                       │  │                      │ │
│  │   VERIFY IDENTITY     │  │   VERIFY DEVICE       │  │   VERIFY ACCESS      │ │
│  │                       │  │                       │  │                      │ │
│  │  ┌─────────────────┐  │  │  ┌─────────────────┐  │  │  ┌────────────────┐  │ │
│  │  │ • SSO Required  │  │  │  │ • Certificate   │  │  │  │ • RBAC Roles   │  │ │
│  │  │ • MFA Available │  │  │  │   Validation    │  │  │  │ • JWT Claims   │  │ │
│  │  │ • Session Mgmt  │  │  │  │ • mTLS Identity │  │  │  │ • Policies     │  │ │
│  │  │ • Token Expiry  │  │  │  │ • SPIFFE/SPIRE  │  │  │  │ • Audit Log    │  │ │
│  │  └─────────────────┘  │  │  └─────────────────┘  │  │  └────────────────┘  │ │
│  │                       │  │                       │  │                      │ │
│  └───────────────────────┘  └───────────────────────┘  └──────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    LEAST PRIVILEGE PRINCIPLE                            │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │   USER ROLES               CAPABILITIES                                  │    │
│  │   ──────────────────────────────────────────────────────────────────    │    │
│  │                                                                          │    │
│  │   siab-admin              Full platform access                           │    │
│  │   ├── Keycloak admin      • Manage all users and roles                  │    │
│  │   ├── K8s admin           • Full cluster access                         │    │
│  │   ├── Grafana admin       • View all metrics and logs                   │    │
│  │   └── All services        • Deploy/manage all applications              │    │
│  │                                                                          │    │
│  │   siab-operator           Application management                         │    │
│  │   ├── App Deployer        • Deploy new applications                     │    │
│  │   ├── App Management      • Scale and configure apps                    │    │
│  │   ├── Grafana viewer      • View application metrics                    │    │
│  │   └── Limited K8s         • Namespace-scoped access                     │    │
│  │                                                                          │    │
│  │   siab-user               Application access only                        │    │
│  │   ├── Dashboard           • View available applications                 │    │
│  │   └── User apps           • Access deployed applications                │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    MICRO-SEGMENTATION                                   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │    │
│  │   │  Namespace A │     │  Namespace B │     │  Namespace C │            │    │
│  │   │              │     │              │     │              │            │    │
│  │   │  ┌────────┐  │     │  ┌────────┐  │     │  ┌────────┐  │            │    │
│  │   │  │ Pod 1  │  │     │  │ Pod 1  │  │     │  │ Pod 1  │  │            │    │
│  │   │  └───┬────┘  │     │  └───┬────┘  │     │  └───┬────┘  │            │    │
│  │   │      │       │     │      │       │     │      │       │            │    │
│  │   │  ┌───▼────┐  │     │  ┌───▼────┐  │     │  ┌───▼────┐  │            │    │
│  │   │  │ Pod 2  │  │     │  │ Pod 2  │  │     │  │ Pod 2  │  │            │    │
│  │   │  └────────┘  │     │  └────────┘  │     │  └────────┘  │            │    │
│  │   │              │     │              │     │              │            │    │
│  │   │   Allowed    │     │    Denied    │     │    Denied    │            │    │
│  │   │   internally │  ╳  │   cross-NS   │  ╳  │   cross-NS   │            │    │
│  │   └──────────────┘     └──────────────┘     └──────────────┘            │    │
│  │                                                                          │    │
│  │   Network Policies enforce namespace isolation by default                │    │
│  │   Cross-namespace communication requires explicit policy                 │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Encryption Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          ENCRYPTION ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     ENCRYPTION IN TRANSIT                               │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│     External Traffic                    Internal Traffic                         │
│     ─────────────────                   ────────────────                         │
│                                                                                  │
│     Client ──────────────────────────────────────────────────────► Application  │
│            │           │              │              │           │              │
│            │  TLS 1.2+ │   mTLS       │    mTLS      │   mTLS    │              │
│            │           │   (Istio)    │   (Istio)    │  (Istio)  │              │
│            ▼           ▼              ▼              ▼           ▼              │
│     ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐ ┌──────────┐       │
│     │  HTTPS   │ │ Ingress  │ │   Sidecar    │ │ Sidecar  │ │   App    │       │
│     │ Request  │ │ Gateway  │ │    Proxy     │ │  Proxy   │ │   Pod    │       │
│     └──────────┘ └──────────┘ └──────────────┘ └──────────┘ └──────────┘       │
│                                                                                  │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │ Certificate Chain:                                                   │    │
│     │                                                                      │    │
│     │   ┌─────────────────┐                                               │    │
│     │   │  SIAB Root CA   │ ◄─── Self-signed CA (cert-manager)            │    │
│     │   │  (ClusterIssuer)│                                               │    │
│     │   └────────┬────────┘                                               │    │
│     │            │                                                         │    │
│     │            ▼                                                         │    │
│     │   ┌─────────────────┐                                               │    │
│     │   │ Gateway Cert    │ ◄─── *.siab.local wildcard certificate        │    │
│     │   │ (siab-gateway-  │                                               │    │
│     │   │  cert)          │                                               │    │
│     │   └─────────────────┘                                               │    │
│     │                                                                      │    │
│     │   Istio automatically manages mTLS certificates for all sidecars    │    │
│     │   using its built-in certificate authority (Citadel)                │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     ENCRYPTION AT REST                                  │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │                                                                      │    │
│     │   LONGHORN VOLUMES              MinIO OBJECTS                        │    │
│     │   ─────────────────             ─────────────                        │    │
│     │                                                                      │    │
│     │   ┌─────────────────┐          ┌─────────────────┐                  │    │
│     │   │                 │          │                 │                  │    │
│     │   │  ┌───────────┐  │          │  ┌───────────┐  │                  │    │
│     │   │  │Application│  │          │  │Application│  │                  │    │
│     │   │  │   Data    │  │          │  │  Objects  │  │                  │    │
│     │   │  └─────┬─────┘  │          │  └─────┬─────┘  │                  │    │
│     │   │        │        │          │        │        │                  │    │
│     │   │        ▼        │          │        ▼        │                  │    │
│     │   │  ┌───────────┐  │          │  ┌───────────┐  │                  │    │
│     │   │  │ Encrypted │  │          │  │ Encrypted │  │                  │    │
│     │   │  │  Volume   │  │          │  │  Bucket   │  │                  │    │
│     │   │  │ (dm-crypt)│  │          │  │(SSE-S3/KMS│  │                  │    │
│     │   │  └───────────┘  │          │  └───────────┘  │                  │    │
│     │   │                 │          │                 │                  │    │
│     │   └─────────────────┘          └─────────────────┘                  │    │
│     │                                                                      │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     SECRET MANAGEMENT                                   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│     ┌─────────────────────────────────────────────────────────────────────┐    │
│     │                                                                      │    │
│     │   Kubernetes Secrets                                                 │    │
│     │   ───────────────────                                                │    │
│     │                                                                      │    │
│     │   • Base64 encoded by default                                        │    │
│     │   • etcd encryption at rest (RKE2 default)                          │    │
│     │   • RBAC-controlled access                                           │    │
│     │   • Audit logging for secret access                                  │    │
│     │                                                                      │    │
│     │   Secret Types Managed:                                              │    │
│     │   ┌─────────────────────────────────────────────────────────┐       │    │
│     │   │ • Keycloak admin credentials                             │       │    │
│     │   │ • OAuth2 proxy client secrets                            │       │    │
│     │   │ • MinIO access keys                                      │       │    │
│     │   │ • Grafana admin password                                 │       │    │
│     │   │ • TLS certificates                                       │       │    │
│     │   │ • Database passwords                                     │       │    │
│     │   │ • Application-specific secrets                           │       │    │
│     │   └─────────────────────────────────────────────────────────┘       │    │
│     │                                                                      │    │
│     └─────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Controls Matrix

| Control Category | Implementation | Standard Alignment |
|-----------------|----------------|-------------------|
| **Access Control** | Keycloak SSO + RBAC | NIST AC-2, AC-3, AC-6 |
| **Audit & Accountability** | Grafana + Kubernetes Audit Logs | NIST AU-2, AU-3, AU-6 |
| **Security Assessment** | Trivy CVE Scanning | NIST CA-2, CA-7, RA-5 |
| **Configuration Management** | OPA Gatekeeper Policies | NIST CM-2, CM-6, CM-7 |
| **Identification & Authentication** | Keycloak OIDC + MFA | NIST IA-2, IA-4, IA-5 |
| **System & Communications Protection** | Istio mTLS + TLS | NIST SC-8, SC-12, SC-13 |
| **System & Information Integrity** | Trivy + Image Scanning | NIST SI-2, SI-3, SI-7 |

---

## Related Documentation

- [Keycloak SSO Configuration](./SIAB-Keycloak-SSO.md)
- [Vulnerability Scanning with Trivy](./SIAB-Trivy-Security-Scanning.md)
- [Policy Enforcement with OPA Gatekeeper](./SIAB-OPA-Gatekeeper-Policies.md)
- [Network Security & Istio](./SIAB-Network-Security.md)
