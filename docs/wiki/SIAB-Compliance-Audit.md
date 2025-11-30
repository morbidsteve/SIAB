# SIAB - Compliance & Audit Capabilities

## Overview

SIAB provides comprehensive compliance and audit capabilities designed to meet enterprise security requirements and regulatory frameworks. The platform implements multiple layers of logging, monitoring, and reporting to provide full visibility into system operations, security events, and policy compliance status.

---

## Compliance Framework Alignment

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      SIAB COMPLIANCE FRAMEWORK MAPPING                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    REGULATORY FRAMEWORK COVERAGE                         │    │
│  │                                                                          │    │
│  │  FRAMEWORK          │ SIAB CAPABILITIES                                  │    │
│  │  ───────────────────┼──────────────────────────────────────────────────  │    │
│  │                     │                                                    │    │
│  │  SOC 2 Type II      │ ✓ Access Control (Keycloak SSO/RBAC)               │    │
│  │                     │ ✓ Encryption in Transit (mTLS)                     │    │
│  │                     │ ✓ Encryption at Rest (Longhorn/MinIO)              │    │
│  │                     │ ✓ Audit Logging (Kubernetes Audit)                 │    │
│  │                     │ ✓ Monitoring & Alerting (Grafana)                  │    │
│  │  ───────────────────┼──────────────────────────────────────────────────  │    │
│  │                     │                                                    │    │
│  │  HIPAA              │ ✓ Authentication Controls (Keycloak MFA)           │    │
│  │                     │ ✓ Access Audit Trails (All actions logged)         │    │
│  │                     │ ✓ Encryption Requirements (TLS 1.2+, mTLS)         │    │
│  │                     │ ✓ Data Integrity Controls (SBOM, Signatures)       │    │
│  │  ───────────────────┼──────────────────────────────────────────────────  │    │
│  │                     │                                                    │    │
│  │  PCI-DSS            │ ✓ Network Segmentation (Istio, NetworkPolicy)      │    │
│  │                     │ ✓ Vulnerability Management (Trivy CVE Scanning)    │    │
│  │                     │ ✓ Strong Cryptography (FIPS 140-2 RKE2)            │    │
│  │                     │ ✓ Access Logging (Complete audit trail)            │    │
│  │  ───────────────────┼──────────────────────────────────────────────────  │    │
│  │                     │                                                    │    │
│  │  CIS Benchmarks     │ ✓ Kubernetes CIS (RKE2 hardened by default)        │    │
│  │                     │ ✓ Pod Security Standards (Gatekeeper policies)     │    │
│  │                     │ ✓ Network Security (mTLS, strict policies)         │    │
│  │  ───────────────────┼──────────────────────────────────────────────────  │    │
│  │                     │                                                    │    │
│  │  NIST 800-53        │ ✓ AC - Access Control (Keycloak RBAC)              │    │
│  │                     │ ✓ AU - Audit & Accountability (Full logging)       │    │
│  │                     │ ✓ SC - System & Comm Protection (Encryption)       │    │
│  │                     │ ✓ SI - System Integrity (Vulnerability Scans)      │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Audit Data Collection Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       AUDIT DATA COLLECTION FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                       AUDIT EVENT SOURCES                                │    │
│  │                                                                          │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │   KUBERNETES    │  │    KEYCLOAK     │  │     ISTIO       │          │    │
│  │  │   API SERVER    │  │   IDENTITY      │  │   SERVICE MESH  │          │    │
│  │  │                 │  │                 │  │                 │          │    │
│  │  │ • Resource CRUD │  │ • Login events  │  │ • Request logs  │          │    │
│  │  │ • Auth attempts │  │ • Token issues  │  │ • mTLS handshake│          │    │
│  │  │ • RBAC decisions│  │ • Role changes  │  │ • Policy denials│          │    │
│  │  │ • Admission     │  │ • MFA events    │  │ • Traffic flow  │          │    │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘          │    │
│  │           │                    │                    │                    │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │   GATEKEEPER    │  │     TRIVY       │  │  APPLICATION    │          │    │
│  │  │   POLICIES      │  │    SCANNER      │  │     LOGS        │          │    │
│  │  │                 │  │                 │  │                 │          │    │
│  │  │ • Policy evals  │  │ • Scan results  │  │ • App events    │          │    │
│  │  │ • Violations    │  │ • CVE detections│  │ • Errors        │          │    │
│  │  │ • Audit results │  │ • SBOM updates  │  │ • User actions  │          │    │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘          │    │
│  │           │                    │                    │                    │    │
│  └───────────┼────────────────────┼────────────────────┼────────────────────┘    │
│              │                    │                    │                         │
│              └────────────────────┼────────────────────┘                         │
│                                   │                                              │
│                                   ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    CENTRALIZED LOG AGGREGATION                           │    │
│  │                                                                          │    │
│  │    ┌─────────────────────────────────────────────────────────────────┐  │    │
│  │    │                     PROMETHEUS                                   │  │    │
│  │    │                                                                  │  │    │
│  │    │  • Time-series metrics                                           │  │    │
│  │    │  • Security metrics                                              │  │    │
│  │    │  • Performance data                                              │  │    │
│  │    │  • Retention: Configurable (default 15 days)                     │  │    │
│  │    └─────────────────────────────────────────────────────────────────┘  │    │
│  │                                   │                                      │    │
│  │                                   ▼                                      │    │
│  │    ┌─────────────────────────────────────────────────────────────────┐  │    │
│  │    │                      GRAFANA                                     │  │    │
│  │    │                                                                  │  │    │
│  │    │  • Security Dashboards                                           │  │    │
│  │    │  • Compliance Reports                                            │  │    │
│  │    │  • Alerting & Notifications                                      │  │    │
│  │    │  • Audit Trail Visualization                                     │  │    │
│  │    └─────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Audit Event Categories

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         AUDIT EVENT TAXONOMY                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    AUTHENTICATION EVENTS                                 │    │
│  │                                                                          │    │
│  │  EVENT TYPE              │ SOURCE      │ SEVERITY  │ RETENTION          │    │
│  │  ────────────────────────┼─────────────┼───────────┼─────────────────── │    │
│  │  Login Success           │ Keycloak    │ INFO      │ 90 days            │    │
│  │  Login Failure           │ Keycloak    │ WARNING   │ 1 year             │    │
│  │  MFA Challenge           │ Keycloak    │ INFO      │ 90 days            │    │
│  │  MFA Failure             │ Keycloak    │ WARNING   │ 1 year             │    │
│  │  Password Change         │ Keycloak    │ INFO      │ 1 year             │    │
│  │  Account Lockout         │ Keycloak    │ CRITICAL  │ 1 year             │    │
│  │  Session Timeout         │ Keycloak    │ INFO      │ 30 days            │    │
│  │  Token Refresh           │ Keycloak    │ DEBUG     │ 7 days             │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    AUTHORIZATION EVENTS                                  │    │
│  │                                                                          │    │
│  │  EVENT TYPE              │ SOURCE      │ SEVERITY  │ RETENTION          │    │
│  │  ────────────────────────┼─────────────┼───────────┼─────────────────── │    │
│  │  Access Granted          │ K8s RBAC    │ INFO      │ 30 days            │    │
│  │  Access Denied           │ K8s RBAC    │ WARNING   │ 1 year             │    │
│  │  Role Binding Created    │ K8s API     │ WARNING   │ 1 year             │    │
│  │  Role Binding Deleted    │ K8s API     │ WARNING   │ 1 year             │    │
│  │  Service Account Created │ K8s API     │ INFO      │ 1 year             │    │
│  │  Privilege Escalation    │ K8s API     │ CRITICAL  │ 1 year             │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    SECURITY POLICY EVENTS                                │    │
│  │                                                                          │    │
│  │  EVENT TYPE              │ SOURCE      │ SEVERITY  │ RETENTION          │    │
│  │  ────────────────────────┼─────────────┼───────────┼─────────────────── │    │
│  │  Policy Violation        │ Gatekeeper  │ WARNING   │ 1 year             │    │
│  │  Admission Denied        │ Gatekeeper  │ WARNING   │ 1 year             │    │
│  │  Constraint Created      │ Gatekeeper  │ INFO      │ 1 year             │    │
│  │  mTLS Failure            │ Istio       │ CRITICAL  │ 1 year             │    │
│  │  AuthPolicy Denied       │ Istio       │ WARNING   │ 1 year             │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    VULNERABILITY EVENTS                                  │    │
│  │                                                                          │    │
│  │  EVENT TYPE              │ SOURCE      │ SEVERITY  │ RETENTION          │    │
│  │  ────────────────────────┼─────────────┼───────────┼─────────────────── │    │
│  │  CRITICAL CVE Detected   │ Trivy       │ CRITICAL  │ 1 year             │    │
│  │  HIGH CVE Detected       │ Trivy       │ HIGH      │ 1 year             │    │
│  │  MEDIUM CVE Detected     │ Trivy       │ MEDIUM    │ 90 days            │    │
│  │  Image Scan Completed    │ Trivy       │ INFO      │ 30 days            │    │
│  │  SBOM Generated          │ Trivy       │ INFO      │ 1 year             │    │
│  │  Config Audit Finding    │ Trivy       │ WARNING   │ 90 days            │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Compliance Reporting

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      COMPLIANCE REPORT GENERATION                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    AUTOMATED COMPLIANCE CHECKS                           │    │
│  │                                                                          │    │
│  │   ┌───────────────────────────────────────────────────────────────┐     │    │
│  │   │                                                                │     │    │
│  │   │   DAILY AUTOMATED CHECKS                                       │     │    │
│  │   │   ─────────────────────────────────────────────────────────── │     │    │
│  │   │                                                                │     │    │
│  │   │   1. VULNERABILITY STATUS                                      │     │    │
│  │   │      └─ Trivy scans all running images                         │     │    │
│  │   │      └─ Reports CRITICAL/HIGH CVEs                             │     │    │
│  │   │      └─ Alerts on new vulnerabilities                          │     │    │
│  │   │                                                                │     │    │
│  │   │   2. POLICY COMPLIANCE                                         │     │    │
│  │   │      └─ Gatekeeper audits all resources                        │     │    │
│  │   │      └─ Reports policy violations                              │     │    │
│  │   │      └─ Tracks violation trends                                │     │    │
│  │   │                                                                │     │    │
│  │   │   3. CERTIFICATE HEALTH                                        │     │    │
│  │   │      └─ cert-manager checks expiry                             │     │    │
│  │   │      └─ Alerts on certificates expiring < 30 days              │     │    │
│  │   │      └─ Monitors mTLS certificate rotation                     │     │    │
│  │   │                                                                │     │    │
│  │   │   4. ACCESS REVIEW                                             │     │    │
│  │   │      └─ Lists all role bindings                                │     │    │
│  │   │      └─ Flags unused service accounts                          │     │    │
│  │   │      └─ Reports privilege changes                              │     │    │
│  │   │                                                                │     │    │
│  │   └───────────────────────────────────────────────────────────────┘     │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    SAMPLE COMPLIANCE REPORT                              │    │
│  │                                                                          │    │
│  │   ╔══════════════════════════════════════════════════════════════════╗  │    │
│  │   ║           SIAB SECURITY COMPLIANCE REPORT                        ║  │    │
│  │   ║           Generated: 2024-01-15 00:00:00 UTC                      ║  │    │
│  │   ╠══════════════════════════════════════════════════════════════════╣  │    │
│  │   ║                                                                   ║  │    │
│  │   ║   EXECUTIVE SUMMARY                                               ║  │    │
│  │   ║   ──────────────────────────────────────────────────────────────  ║  │    │
│  │   ║   Overall Compliance Score: 94%                                   ║  │    │
│  │   ║   Risk Level: LOW                                                 ║  │    │
│  │   ║   Critical Issues: 0                                              ║  │    │
│  │   ║   High Issues: 2                                                  ║  │    │
│  │   ║   Medium Issues: 5                                                ║  │    │
│  │   ║                                                                   ║  │    │
│  │   ║   VULNERABILITY STATUS                                            ║  │    │
│  │   ║   ──────────────────────────────────────────────────────────────  ║  │    │
│  │   ║   Images Scanned: 47                                              ║  │    │
│  │   ║   CRITICAL CVEs: 0                                                ║  │    │
│  │   ║   HIGH CVEs: 3 (all in non-production namespace)                  ║  │    │
│  │   ║   MEDIUM CVEs: 12                                                 ║  │    │
│  │   ║   LOW CVEs: 34                                                    ║  │    │
│  │   ║                                                                   ║  │    │
│  │   ║   POLICY COMPLIANCE                                               ║  │    │
│  │   ║   ──────────────────────────────────────────────────────────────  ║  │    │
│  │   ║   Active Constraints: 7                                           ║  │    │
│  │   ║   Total Violations: 5                                             ║  │    │
│  │   ║   - require-non-root: 2 violations                                ║  │    │
│  │   ║   - require-resource-limits: 3 violations                         ║  │    │
│  │   ║   Compliance Rate: 98.2%                                          ║  │    │
│  │   ║                                                                   ║  │    │
│  │   ║   AUTHENTICATION METRICS (Last 24 Hours)                          ║  │    │
│  │   ║   ──────────────────────────────────────────────────────────────  ║  │    │
│  │   ║   Successful Logins: 234                                          ║  │    │
│  │   ║   Failed Logins: 12                                               ║  │    │
│  │   ║   MFA Challenges: 234                                             ║  │    │
│  │   ║   Account Lockouts: 0                                             ║  │    │
│  │   ║                                                                   ║  │    │
│  │   ║   ENCRYPTION STATUS                                               ║  │    │
│  │   ║   ──────────────────────────────────────────────────────────────  ║  │    │
│  │   ║   mTLS Coverage: 100%                                             ║  │    │
│  │   ║   TLS Certificate Status: Valid (expires in 89 days)              ║  │    │
│  │   ║   Encryption at Rest: Enabled for all volumes                     ║  │    │
│  │   ║                                                                   ║  │    │
│  │   ╚══════════════════════════════════════════════════════════════════╝  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Metrics and KPIs

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       SECURITY METRICS DASHBOARD                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    KEY PERFORMANCE INDICATORS                            │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │  VULNERABILITY METRICS                                             │  │    │
│  │  │                                                                    │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────────┐  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  MTTR (Mean Time to Remediate)                               │  │  │    │
│  │  │  │  ─────────────────────────────                               │  │  │    │
│  │  │  │  CRITICAL: < 24 hours    │  Target: 24h  │  Actual: 8h       │  │  │    │
│  │  │  │  HIGH:     < 7 days      │  Target: 7d   │  Actual: 3d       │  │  │    │
│  │  │  │  MEDIUM:   < 30 days     │  Target: 30d  │  Actual: 14d      │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Vulnerability Density (CVEs per 1000 lines of code)         │  │  │    │
│  │  │  │  ─────────────────────────────────────────────────           │  │  │    │
│  │  │  │  Current: 0.3   │   Target: < 1.0   │   Status: ✓ PASS       │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  └─────────────────────────────────────────────────────────────┘  │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │  ACCESS CONTROL METRICS                                            │  │    │
│  │  │                                                                    │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────────┐  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Authentication Success Rate                                 │  │  │    │
│  │  │  │  ─────────────────────────────                               │  │  │    │
│  │  │  │  Last 24h: 95.1%   │   Target: > 90%   │   Status: ✓ PASS    │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  MFA Adoption Rate                                           │  │  │    │
│  │  │  │  ─────────────────────                                       │  │  │    │
│  │  │  │  Current: 100%   │   Target: 100%   │   Status: ✓ PASS       │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Privileged Access Reviews (Monthly)                         │  │  │    │
│  │  │  │  ─────────────────────────────────────                       │  │  │    │
│  │  │  │  Last Review: 2024-01-01   │   Next Due: 2024-02-01          │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  └─────────────────────────────────────────────────────────────┘  │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │  POLICY COMPLIANCE METRICS                                         │  │    │
│  │  │                                                                    │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────────┐  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Policy Compliance Rate                                      │  │  │    │
│  │  │  │  ────────────────────────                                    │  │  │    │
│  │  │  │  Current: 98.2%   │   Target: > 95%   │   Status: ✓ PASS     │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Admission Denial Rate                                       │  │  │    │
│  │  │  │  ─────────────────────────                                   │  │  │    │
│  │  │  │  Last 24h: 0.8%   │   Target: < 5%   │   Status: ✓ PASS      │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  │  Configuration Drift Score                                   │  │  │    │
│  │  │  │  ───────────────────────────                                 │  │  │    │
│  │  │  │  Current: 2%   │   Target: < 5%   │   Status: ✓ PASS         │  │  │    │
│  │  │  │                                                              │  │  │    │
│  │  │  └─────────────────────────────────────────────────────────────┘  │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Audit Trail Structure

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AUDIT LOG ENTRY FORMAT                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    KUBERNETES AUDIT LOG                                  │    │
│  │                                                                          │    │
│  │  {                                                                       │    │
│  │    "kind": "Event",                                                      │    │
│  │    "apiVersion": "audit.k8s.io/v1",                                      │    │
│  │    "level": "RequestResponse",                                           │    │
│  │    "auditID": "abc-123-def-456",                                         │    │
│  │    "stage": "ResponseComplete",                                          │    │
│  │    "requestURI": "/api/v1/namespaces/default/pods",                      │    │
│  │    "verb": "create",                                                     │    │
│  │    "user": {                                                             │    │
│  │      "username": "john@company.com",                                     │    │
│  │      "uid": "user-uuid-12345",                                           │    │
│  │      "groups": ["siab-admin", "system:authenticated"]                    │    │
│  │    },                                                                    │    │
│  │    "sourceIPs": ["10.0.0.50"],                                           │    │
│  │    "userAgent": "kubectl/v1.28.4",                                       │    │
│  │    "objectRef": {                                                        │    │
│  │      "resource": "pods",                                                 │    │
│  │      "namespace": "default",                                             │    │
│  │      "name": "my-app-pod"                                                │    │
│  │    },                                                                    │    │
│  │    "responseStatus": {                                                   │    │
│  │      "code": 201                                                         │    │
│  │    },                                                                    │    │
│  │    "requestReceivedTimestamp": "2024-01-15T10:30:00.000000Z",            │    │
│  │    "stageTimestamp": "2024-01-15T10:30:00.050000Z"                       │    │
│  │  }                                                                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    KEYCLOAK AUDIT LOG                                    │    │
│  │                                                                          │    │
│  │  {                                                                       │    │
│  │    "time": "2024-01-15T10:25:00.000Z",                                   │    │
│  │    "type": "LOGIN",                                                      │    │
│  │    "realmId": "siab",                                                    │    │
│  │    "clientId": "siab-dashboard",                                         │    │
│  │    "userId": "user-uuid-12345",                                          │    │
│  │    "sessionId": "session-uuid-67890",                                    │    │
│  │    "ipAddress": "10.0.0.50",                                             │    │
│  │    "details": {                                                          │    │
│  │      "auth_method": "openid-connect",                                    │    │
│  │      "auth_type": "code",                                                │    │
│  │      "mfa_method": "totp",                                               │    │
│  │      "redirect_uri": "https://dashboard.siab.local/callback",            │    │
│  │      "username": "john@company.com"                                      │    │
│  │    },                                                                    │    │
│  │    "outcome": "SUCCESS"                                                  │    │
│  │  }                                                                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    GATEKEEPER AUDIT LOG                                  │    │
│  │                                                                          │    │
│  │  {                                                                       │    │
│  │    "level": "warning",                                                   │    │
│  │    "ts": "2024-01-15T10:30:05.000Z",                                     │    │
│  │    "msg": "Constraint violation",                                        │    │
│  │    "constraint": "require-non-root",                                     │    │
│  │    "enforcement_action": "deny",                                         │    │
│  │    "resource": {                                                         │    │
│  │      "apiVersion": "v1",                                                 │    │
│  │      "kind": "Pod",                                                      │    │
│  │      "namespace": "default",                                             │    │
│  │      "name": "insecure-pod"                                              │    │
│  │    },                                                                    │    │
│  │    "violation_msg": "Container app must set runAsNonRoot to true",       │    │
│  │    "user": "john@company.com"                                            │    │
│  │  }                                                                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Evidence Collection for Auditors

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      AUDITOR EVIDENCE PACKAGE                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    EVIDENCE CATEGORIES                                   │    │
│  │                                                                          │    │
│  │  1. ACCESS CONTROL EVIDENCE                                              │    │
│  │     ────────────────────────────────────────────────────────────────────│    │
│  │     ├── User provisioning/deprovisioning logs                            │    │
│  │     ├── Role assignment audit trail                                      │    │
│  │     ├── Keycloak realm configuration export                              │    │
│  │     ├── RBAC role definitions (kubectl get clusterroles -o yaml)         │    │
│  │     └── Service account inventory                                        │    │
│  │                                                                          │    │
│  │  2. CHANGE MANAGEMENT EVIDENCE                                           │    │
│  │     ────────────────────────────────────────────────────────────────────│    │
│  │     ├── Git commit history for infrastructure changes                    │    │
│  │     ├── Kubernetes audit logs for resource modifications                 │    │
│  │     ├── Helm release history                                             │    │
│  │     └── Configuration change requests and approvals                      │    │
│  │                                                                          │    │
│  │  3. VULNERABILITY MANAGEMENT EVIDENCE                                    │    │
│  │     ────────────────────────────────────────────────────────────────────│    │
│  │     ├── Trivy vulnerability scan reports                                 │    │
│  │     ├── SBOM exports (CycloneDX/SPDX format)                             │    │
│  │     ├── CVE remediation tracking                                         │    │
│  │     └── Image signature verification logs                                │    │
│  │                                                                          │    │
│  │  4. ENCRYPTION EVIDENCE                                                  │    │
│  │     ────────────────────────────────────────────────────────────────────│    │
│  │     ├── TLS certificate inventory                                        │    │
│  │     ├── mTLS configuration exports                                       │    │
│  │     ├── Encryption at rest configuration                                 │    │
│  │     └── Key rotation schedules                                           │    │
│  │                                                                          │    │
│  │  5. MONITORING & INCIDENT RESPONSE EVIDENCE                              │    │
│  │     ────────────────────────────────────────────────────────────────────│    │
│  │     ├── Alert configuration and history                                  │    │
│  │     ├── Security incident logs                                           │    │
│  │     ├── Response time metrics                                            │    │
│  │     └── Post-incident review reports                                     │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    EVIDENCE COLLECTION COMMANDS                          │    │
│  │                                                                          │    │
│  │  # Export RBAC configuration                                             │    │
│  │  kubectl get clusterroles,clusterrolebindings -o yaml > rbac-export.yaml │    │
│  │                                                                          │    │
│  │  # Export Gatekeeper constraints and violations                          │    │
│  │  kubectl get constraints -o yaml > gatekeeper-constraints.yaml           │    │
│  │                                                                          │    │
│  │  # Export all Trivy vulnerability reports                                │    │
│  │  kubectl get vulnerabilityreports -A -o yaml > trivy-vulns.yaml          │    │
│  │                                                                          │    │
│  │  # Export Keycloak realm configuration                                   │    │
│  │  # (Via Keycloak Admin API or UI export)                                 │    │
│  │                                                                          │    │
│  │  # List all certificates                                                 │    │
│  │  kubectl get certificates -A -o yaml > certificates.yaml                 │    │
│  │                                                                          │    │
│  │  # Export Istio mTLS configuration                                       │    │
│  │  kubectl get peerauthentication -A -o yaml > mtls-config.yaml            │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Continuous Compliance Monitoring

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                   CONTINUOUS COMPLIANCE ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │                     COMPLIANCE MONITORING LOOP                           │    │
│  │                                                                          │    │
│  │       ┌─────────────────────────────────────────────────────────┐       │    │
│  │       │                                                          │       │    │
│  │       │  ┌──────────┐                                            │       │    │
│  │       │  │  DETECT  │◄────────────────────────────────────┐      │       │    │
│  │       │  │          │                                     │      │       │    │
│  │       │  │ • Trivy  │                                     │      │       │    │
│  │       │  │ • Gatekpr│                                     │      │       │    │
│  │       │  │ • Audit  │                                     │      │       │    │
│  │       │  └────┬─────┘                                     │      │       │    │
│  │       │       │                                           │      │       │    │
│  │       │       ▼                                           │      │       │    │
│  │       │  ┌──────────┐    ┌──────────┐    ┌──────────┐    │      │       │    │
│  │       │  │  ALERT   │───▶│ RESPOND  │───▶│ REMEDIATE│────┘      │       │    │
│  │       │  │          │    │          │    │          │           │       │    │
│  │       │  │ • Grafana│    │ • Oncall │    │ • Fix    │           │       │    │
│  │       │  │ • Slack  │    │ • Triage │    │ • Verify │           │       │    │
│  │       │  │ • Email  │    │ • Assign │    │ • Close  │           │       │    │
│  │       │  └──────────┘    └──────────┘    └──────────┘           │       │    │
│  │       │                                                          │       │    │
│  │       └──────────────────────────────────────────────────────────┘       │    │
│  │                                                                          │    │
│  │                     AUTOMATED COMPLIANCE CHECKS                          │    │
│  │       ┌──────────────────────────────────────────────────────────┐      │    │
│  │       │                                                           │      │    │
│  │       │  HOURLY:                                                  │      │    │
│  │       │  └─ Certificate expiry check                              │      │    │
│  │       │  └─ Service health verification                           │      │    │
│  │       │                                                           │      │    │
│  │       │  DAILY:                                                   │      │    │
│  │       │  └─ Full vulnerability scan                               │      │    │
│  │       │  └─ Policy compliance audit                               │      │    │
│  │       │  └─ Access review report                                  │      │    │
│  │       │                                                           │      │    │
│  │       │  WEEKLY:                                                  │      │    │
│  │       │  └─ SBOM regeneration                                     │      │    │
│  │       │  └─ Security metrics report                               │      │    │
│  │       │  └─ Trend analysis                                        │      │    │
│  │       │                                                           │      │    │
│  │       │  MONTHLY:                                                 │      │    │
│  │       │  └─ Comprehensive compliance report                       │      │    │
│  │       │  └─ Privileged access review                              │      │    │
│  │       │  └─ Policy effectiveness review                           │      │    │
│  │       │                                                           │      │    │
│  │       └──────────────────────────────────────────────────────────┘      │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Operational Commands

### Generate Compliance Reports
```bash
# List all Gatekeeper violations
kubectl get constraints -o json | jq '.items[] | {name: .metadata.name, violations: .status.totalViolations}'

# Export vulnerability summary
kubectl get vulnerabilityreports -A -o json | jq '[.items[] | {image: .metadata.name, critical: .report.summary.criticalCount, high: .report.summary.highCount}]'

# List recent security events
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | head -20
```

### Access Audit Logs
```bash
# View Kubernetes audit logs (RKE2)
sudo cat /var/lib/rancher/rke2/server/logs/audit.log | jq

# View Keycloak events
kubectl logs -n keycloak deployment/keycloak | grep -i "event"

# View Gatekeeper audit results
kubectl describe constrainttemplates
```

### Export Evidence
```bash
# Create compliance evidence package
mkdir -p /tmp/compliance-evidence
kubectl get all -A -o yaml > /tmp/compliance-evidence/resources.yaml
kubectl get constraints -o yaml > /tmp/compliance-evidence/constraints.yaml
kubectl get vulnerabilityreports -A -o yaml > /tmp/compliance-evidence/vulns.yaml
kubectl get certificates -A -o yaml > /tmp/compliance-evidence/certs.yaml
```

---

## Related Documentation

- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Keycloak SSO Configuration](./SIAB-Keycloak-SSO.md)
- [Trivy Vulnerability Scanning](./SIAB-Trivy-Security-Scanning.md)
- [OPA Gatekeeper Policies](./SIAB-OPA-Gatekeeper-Policies.md)
- [Network Security & Istio](./SIAB-Network-Security.md)
