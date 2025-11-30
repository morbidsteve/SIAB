# Trivy Security Scanning & SBOM Generation

## Overview

Trivy is an integrated security scanner in SIAB that provides comprehensive vulnerability detection, Software Bill of Materials (SBOM) generation, and security compliance checking for all container images deployed to the platform.

---

## Scanning Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         TRIVY SCANNING ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                          SCANNING PIPELINE                               │   │
│   │                                                                          │   │
│   │                                                                          │   │
│   │    ┌──────────────┐                                                      │   │
│   │    │  Container   │                                                      │   │
│   │    │   Image      │                                                      │   │
│   │    │ (Registry)   │                                                      │   │
│   │    └──────┬───────┘                                                      │   │
│   │           │                                                              │   │
│   │           │ Pull Image                                                   │   │
│   │           ▼                                                              │   │
│   │    ┌──────────────────────────────────────────────────────────────┐     │   │
│   │    │                      TRIVY SCANNER                            │     │   │
│   │    │                                                               │     │   │
│   │    │   ┌─────────────────────────────────────────────────────┐    │     │   │
│   │    │   │              IMAGE ANALYSIS                          │    │     │   │
│   │    │   │                                                      │    │     │   │
│   │    │   │  ┌────────────────────────────────────────────────┐ │    │     │   │
│   │    │   │  │ 1. Extract Image Layers                        │ │    │     │   │
│   │    │   │  │    • Base OS identification                    │ │    │     │   │
│   │    │   │  │    • Layer-by-layer analysis                   │ │    │     │   │
│   │    │   │  │    • File system inspection                    │ │    │     │   │
│   │    │   │  └────────────────────────────────────────────────┘ │    │     │   │
│   │    │   │                         │                            │    │     │   │
│   │    │   │                         ▼                            │    │     │   │
│   │    │   │  ┌────────────────────────────────────────────────┐ │    │     │   │
│   │    │   │  │ 2. Package Detection                           │ │    │     │   │
│   │    │   │  │    • OS packages (apt, yum, apk)               │ │    │     │   │
│   │    │   │  │    • Language packages (npm, pip, gem, etc)    │ │    │     │   │
│   │    │   │  │    • Application dependencies                  │ │    │     │   │
│   │    │   │  └────────────────────────────────────────────────┘ │    │     │   │
│   │    │   │                         │                            │    │     │   │
│   │    │   │                         ▼                            │    │     │   │
│   │    │   │  ┌────────────────────────────────────────────────┐ │    │     │   │
│   │    │   │  │ 3. Vulnerability Matching                      │ │    │     │   │
│   │    │   │  │    • CVE database lookup                       │ │    │     │   │
│   │    │   │  │    • Severity classification                   │ │    │     │   │
│   │    │   │  │    • Fixed version identification              │ │    │     │   │
│   │    │   │  └────────────────────────────────────────────────┘ │    │     │   │
│   │    │   │                         │                            │    │     │   │
│   │    │   │                         ▼                            │    │     │   │
│   │    │   │  ┌────────────────────────────────────────────────┐ │    │     │   │
│   │    │   │  │ 4. SBOM Generation                             │ │    │     │   │
│   │    │   │  │    • CycloneDX format                          │ │    │     │   │
│   │    │   │  │    • SPDX format                               │ │    │     │   │
│   │    │   │  │    • Dependency tree                           │ │    │     │   │
│   │    │   │  └────────────────────────────────────────────────┘ │    │     │   │
│   │    │   │                                                      │    │     │   │
│   │    │   └─────────────────────────────────────────────────────┘    │     │   │
│   │    │                                                               │     │   │
│   │    └───────────────────────────┬──────────────────────────────────┘     │   │
│   │                                │                                         │   │
│   │                                ▼                                         │   │
│   │    ┌──────────────────────────────────────────────────────────────┐     │   │
│   │    │                    SCAN RESULTS                               │     │   │
│   │    │                                                               │     │   │
│   │    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │     │   │
│   │    │  │    CVE      │  │   SBOM      │  │  Config     │           │     │   │
│   │    │  │   Report    │  │   Report    │  │   Report    │           │     │   │
│   │    │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘           │     │   │
│   │    │         │                │                │                   │     │   │
│   │    │         └────────────────┼────────────────┘                   │     │   │
│   │    │                          │                                    │     │   │
│   │    └──────────────────────────┼────────────────────────────────────┘     │   │
│   │                               │                                          │   │
│   │                               ▼                                          │   │
│   │    ┌──────────────────────────────────────────────────────────────┐     │   │
│   │    │                   OUTPUT DESTINATIONS                         │     │   │
│   │    │                                                               │     │   │
│   │    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │     │   │
│   │    │  │  Grafana    │  │   MinIO     │  │  Webhook    │           │     │   │
│   │    │  │ Dashboards  │  │  Storage    │  │  Alerts     │           │     │   │
│   │    │  └─────────────┘  └─────────────┘  └─────────────┘           │     │   │
│   │    │                                                               │     │   │
│   │    └──────────────────────────────────────────────────────────────┘     │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Vulnerability Detection

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         VULNERABILITY DETECTION FLOW                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                     CVE DATABASE SOURCES                                 │   │
│   │                                                                          │   │
│   │   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐             │   │
│   │   │     NVD       │   │  GitHub       │   │    Vendor     │             │   │
│   │   │  (National    │   │  Security     │   │  Advisories   │             │   │
│   │   │ Vulnerability │   │  Advisories   │   │               │             │   │
│   │   │  Database)    │   │               │   │ • Red Hat     │             │   │
│   │   │               │   │               │   │ • Ubuntu      │             │   │
│   │   │               │   │               │   │ • Debian      │             │   │
│   │   │               │   │               │   │ • Alpine      │             │   │
│   │   └───────┬───────┘   └───────┬───────┘   └───────┬───────┘             │   │
│   │           │                   │                   │                      │   │
│   │           └───────────────────┼───────────────────┘                      │   │
│   │                               │                                          │   │
│   │                               ▼                                          │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                  TRIVY VULNERABILITY DB                          │   │   │
│   │   │                                                                  │   │   │
│   │   │   • Updated every 6 hours automatically                          │   │   │
│   │   │   • Contains 100,000+ CVE records                                │   │   │
│   │   │   • Covers 20+ OS distributions                                  │   │   │
│   │   │   • Includes language-specific vulnerabilities                   │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                    SEVERITY CLASSIFICATION                               │   │
│   │                                                                          │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                                                                  │   │   │
│   │   │   SEVERITY     CVSS SCORE    ACTION REQUIRED                     │   │   │
│   │   │   ─────────────────────────────────────────────────────────────  │   │   │
│   │   │                                                                  │   │   │
│   │   │   ████████████                                                   │   │   │
│   │   │   CRITICAL     9.0 - 10.0    Immediate remediation required      │   │   │
│   │   │                              Block deployment if found            │   │   │
│   │   │                                                                  │   │   │
│   │   │   ████████░░░░                                                   │   │   │
│   │   │   HIGH         7.0 - 8.9     Remediate within 7 days             │   │   │
│   │   │                              Flag for security review             │   │   │
│   │   │                                                                  │   │   │
│   │   │   █████░░░░░░░                                                   │   │   │
│   │   │   MEDIUM       4.0 - 6.9     Remediate within 30 days            │   │   │
│   │   │                              Include in patch cycle               │   │   │
│   │   │                                                                  │   │   │
│   │   │   ██░░░░░░░░░░                                                   │   │   │
│   │   │   LOW          0.1 - 3.9     Remediate as resources allow        │   │   │
│   │   │                              Monitor for escalation               │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Software Bill of Materials (SBOM)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      SOFTWARE BILL OF MATERIALS (SBOM)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   An SBOM is a comprehensive inventory of all software components in an         │
│   application, similar to an ingredient list for food products.                 │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                        SBOM CONTENT                                      │   │
│   │                                                                          │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                                                                  │   │   │
│   │   │   APPLICATION: my-webapp:v1.2.3                                  │   │   │
│   │   │   ─────────────────────────────────────────────────────────────  │   │   │
│   │   │                                                                  │   │   │
│   │   │   BASE IMAGE                                                     │   │   │
│   │   │   ├── node:18-alpine (sha256:abc123...)                         │   │   │
│   │   │   │   ├── alpine:3.18 (sha256:def456...)                        │   │   │
│   │   │   │   └── nodejs v18.19.0                                       │   │   │
│   │   │   │                                                              │   │   │
│   │   │   OS PACKAGES (apk)                                              │   │   │
│   │   │   ├── musl 1.2.4-r2                                             │   │   │
│   │   │   ├── busybox 1.36.1-r2                                         │   │   │
│   │   │   ├── openssl 3.1.4-r0                                          │   │   │
│   │   │   ├── ca-certificates 20230506-r0                               │   │   │
│   │   │   └── ... (45 more packages)                                    │   │   │
│   │   │                                                                  │   │   │
│   │   │   NPM DEPENDENCIES                                               │   │   │
│   │   │   ├── express 4.18.2                                            │   │   │
│   │   │   │   ├── accepts 1.3.8                                         │   │   │
│   │   │   │   ├── body-parser 1.20.1                                    │   │   │
│   │   │   │   │   └── bytes 3.1.2                                       │   │   │
│   │   │   │   └── ... (28 dependencies)                                 │   │   │
│   │   │   ├── lodash 4.17.21                                            │   │   │
│   │   │   ├── axios 1.6.2                                               │   │   │
│   │   │   └── ... (127 total dependencies)                              │   │   │
│   │   │                                                                  │   │   │
│   │   │   LICENSES                                                       │   │   │
│   │   │   ├── MIT: 89 packages                                          │   │   │
│   │   │   ├── Apache-2.0: 23 packages                                   │   │   │
│   │   │   ├── ISC: 12 packages                                          │   │   │
│   │   │   └── BSD-3-Clause: 3 packages                                  │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      SBOM FORMATS SUPPORTED                              │   │
│   │                                                                          │   │
│   │   ┌───────────────────────┐   ┌───────────────────────┐                 │   │
│   │   │       CycloneDX       │   │         SPDX          │                 │   │
│   │   │                       │   │                       │                 │   │
│   │   │  • OWASP Standard     │   │  • Linux Foundation   │                 │   │
│   │   │  • JSON/XML format    │   │  • ISO/IEC 5962:2021  │                 │   │
│   │   │  • Rich vulnerability │   │  • JSON/RDF/Tag-Value │                 │   │
│   │   │    integration        │   │  • License focus      │                 │   │
│   │   │  • Supply chain       │   │  • Industry standard  │                 │   │
│   │   │    metadata           │   │    for compliance     │                 │   │
│   │   │                       │   │                       │                 │   │
│   │   └───────────────────────┘   └───────────────────────┘                 │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      SBOM USE CASES                                      │   │
│   │                                                                          │   │
│   │   1. VULNERABILITY TRACKING                                              │   │
│   │      • When a new CVE is published, quickly identify affected images    │   │
│   │      • Track which deployments need patching                            │   │
│   │                                                                          │   │
│   │   2. LICENSE COMPLIANCE                                                  │   │
│   │      • Ensure all dependencies have compatible licenses                 │   │
│   │      • Identify GPL or other copyleft license usage                     │   │
│   │      • Generate license attribution documents                           │   │
│   │                                                                          │   │
│   │   3. SUPPLY CHAIN SECURITY                                              │   │
│   │      • Verify component origins and authenticity                        │   │
│   │      • Track transitive dependencies                                    │   │
│   │      • Identify abandoned or unmaintained packages                      │   │
│   │                                                                          │   │
│   │   4. REGULATORY COMPLIANCE                                              │   │
│   │      • Meet Executive Order 14028 requirements                          │   │
│   │      • Support FDA medical device regulations                           │   │
│   │      • Enable NIST SSDF compliance                                      │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Scan Types

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              TRIVY SCAN TYPES                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │   1. CONTAINER IMAGE SCANNING                                            │   │
│   │   ═══════════════════════════════════════════════════════════════════   │   │
│   │                                                                          │   │
│   │   Scans container images for:                                            │   │
│   │   • OS package vulnerabilities                                           │   │
│   │   • Language-specific vulnerabilities (npm, pip, gem, etc.)             │   │
│   │   • Application dependencies                                             │   │
│   │   • Embedded secrets and credentials                                     │   │
│   │                                                                          │   │
│   │   Command: trivy image nginx:latest                                      │   │
│   │                                                                          │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │ nginx:latest (debian 12.2)                                       │   │   │
│   │   │ ════════════════════════════════════════════════════════════════ │   │   │
│   │   │ Total: 127 (CRITICAL: 2, HIGH: 15, MEDIUM: 45, LOW: 65)         │   │   │
│   │   │                                                                  │   │   │
│   │   │ ┌──────────┬──────────┬──────────┬─────────────┬────────────┐   │   │   │
│   │   │ │ Library  │ Vuln ID  │ Severity │ Installed   │ Fixed      │   │   │   │
│   │   │ ├──────────┼──────────┼──────────┼─────────────┼────────────┤   │   │   │
│   │   │ │ openssl  │CVE-2024- │ CRITICAL │ 3.0.11      │ 3.0.13     │   │   │   │
│   │   │ │          │ 0001     │          │             │            │   │   │   │
│   │   │ │ curl     │CVE-2024- │ HIGH     │ 7.88.1      │ 7.88.2     │   │   │   │
│   │   │ │          │ 0002     │          │             │            │   │   │   │
│   │   │ │ ...      │ ...      │ ...      │ ...         │ ...        │   │   │   │
│   │   │ └──────────┴──────────┴──────────┴─────────────┴────────────┘   │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │   2. FILESYSTEM SCANNING                                                 │   │
│   │   ═══════════════════════════════════════════════════════════════════   │   │
│   │                                                                          │   │
│   │   Scans local directories and code repositories:                         │   │
│   │   • Dependency files (package.json, requirements.txt, etc.)             │   │
│   │   • Lock files (package-lock.json, Pipfile.lock, etc.)                  │   │
│   │   • Configuration files                                                  │   │
│   │   • Infrastructure as Code                                               │   │
│   │                                                                          │   │
│   │   Command: trivy fs /path/to/project                                     │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │   3. KUBERNETES CLUSTER SCANNING                                         │   │
│   │   ═══════════════════════════════════════════════════════════════════   │   │
│   │                                                                          │   │
│   │   Scans running Kubernetes clusters:                                     │   │
│   │   • All deployed container images                                        │   │
│   │   • Workload configurations                                              │   │
│   │   • RBAC misconfigurations                                               │   │
│   │   • Network policy gaps                                                  │   │
│   │   • Secret exposure risks                                                │   │
│   │                                                                          │   │
│   │   Command: trivy k8s cluster                                             │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │   4. CONFIGURATION SCANNING                                              │   │
│   │   ═══════════════════════════════════════════════════════════════════   │   │
│   │                                                                          │   │
│   │   Scans Infrastructure as Code files:                                    │   │
│   │   • Kubernetes manifests (YAML)                                          │   │
│   │   • Terraform configurations                                             │   │
│   │   • CloudFormation templates                                             │   │
│   │   • Dockerfiles                                                          │   │
│   │   • Helm charts                                                          │   │
│   │                                                                          │   │
│   │   Command: trivy config /path/to/manifests                               │   │
│   │                                                                          │   │
│   │   Example findings:                                                      │   │
│   │   ┌──────────────────────────────────────────────────────────────────┐  │   │
│   │   │ deployment.yaml                                                   │  │   │
│   │   │ ├─ DS002: Container running as root (HIGH)                       │  │   │
│   │   │ ├─ DS005: Container has no resource limits (MEDIUM)              │  │   │
│   │   │ ├─ DS012: Secrets in environment variables (HIGH)                │  │   │
│   │   │ └─ DS017: Privileged container (CRITICAL)                        │  │   │
│   │   └──────────────────────────────────────────────────────────────────┘  │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │   5. SECRET SCANNING                                                     │   │
│   │   ═══════════════════════════════════════════════════════════════════   │   │
│   │                                                                          │   │
│   │   Detects exposed secrets and credentials:                               │   │
│   │   • API keys (AWS, GCP, Azure)                                          │   │
│   │   • Private keys (SSH, PGP)                                             │   │
│   │   • Tokens (GitHub, GitLab, Slack)                                      │   │
│   │   • Passwords in configuration files                                     │   │
│   │   • Database connection strings                                          │   │
│   │                                                                          │   │
│   │   Command: trivy image --scanners secret nginx:latest                    │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Integration with SIAB

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         TRIVY INTEGRATION IN SIAB                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                     DEPLOYMENT PIPELINE                                  │   │
│   │                                                                          │   │
│   │   ┌──────────────┐                                                       │   │
│   │   │   User       │                                                       │   │
│   │   │   deploys    │                                                       │   │
│   │   │   app        │                                                       │   │
│   │   └──────┬───────┘                                                       │   │
│   │          │                                                               │   │
│   │          ▼                                                               │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                    APP DEPLOYER API                              │   │   │
│   │   │                                                                  │   │   │
│   │   │   1. Receive deployment request                                  │   │   │
│   │   │   2. Trigger pre-deployment scan                                 │   │   │
│   │   │                                                                  │   │   │
│   │   └──────────────────────────┬──────────────────────────────────────┘   │   │
│   │                              │                                           │   │
│   │                              ▼                                           │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                    TRIVY OPERATOR                                │   │   │
│   │   │                                                                  │   │   │
│   │   │   ┌───────────────────────────────────────────────────────┐     │   │   │
│   │   │   │              SCAN IMAGE                                │     │   │   │
│   │   │   │                                                        │     │   │   │
│   │   │   │   • Pull image from registry                          │     │   │   │
│   │   │   │   • Run vulnerability scan                            │     │   │   │
│   │   │   │   • Generate SBOM                                     │     │   │   │
│   │   │   │   • Check against policy                              │     │   │   │
│   │   │   │                                                        │     │   │   │
│   │   │   └───────────────────────────────────────────────────────┘     │   │   │
│   │   │                                                                  │   │   │
│   │   │   Scan Result:                                                   │   │   │
│   │   │   ┌───────────────────────────────────────────────────────┐     │   │   │
│   │   │   │ Critical: 0  High: 2  Medium: 15  Low: 23              │     │   │   │
│   │   │   │ Policy: MAX_HIGH=5 ──► PASS                           │     │   │   │
│   │   │   └───────────────────────────────────────────────────────┘     │   │   │
│   │   │                                                                  │   │   │
│   │   └──────────────────────────┬──────────────────────────────────────┘   │   │
│   │                              │                                           │   │
│   │               ┌──────────────┼──────────────┐                           │   │
│   │               │              │              │                           │   │
│   │               ▼              │              ▼                           │   │
│   │   ┌───────────────┐         │    ┌───────────────┐                     │   │
│   │   │    PASS       │         │    │    FAIL       │                     │   │
│   │   │               │         │    │               │                     │   │
│   │   │  Continue     │         │    │  Block        │                     │   │
│   │   │  deployment   │         │    │  deployment   │                     │   │
│   │   │               │         │    │               │                     │   │
│   │   └───────┬───────┘         │    │  Notify user  │                     │   │
│   │           │                 │    │  with report  │                     │   │
│   │           │                 │    │               │                     │   │
│   │           │                 │    └───────────────┘                     │   │
│   │           ▼                 │                                           │   │
│   │   ┌─────────────────────────┴───────────────────────────────────────┐   │   │
│   │   │                    KUBERNETES CLUSTER                            │   │   │
│   │   │                                                                  │   │   │
│   │   │   Application deployed with scan results stored as annotations  │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Sample Vulnerability Report

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      VULNERABILITY SCAN REPORT                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  Image: myapp:v1.2.3                                                             │
│  Scanned: 2024-01-15 14:30:00 UTC                                               │
│  Scanner: Trivy v0.48.0                                                         │
│                                                                                  │
│  ═══════════════════════════════════════════════════════════════════════════   │
│                                                                                  │
│  SUMMARY                                                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │                                                                         │     │
│  │   ████████████████████████████████████████  Total: 85                  │     │
│  │                                                                         │     │
│  │   ██ CRITICAL:  2  ──────────────────────── Immediate action required  │     │
│  │   ████████ HIGH:  8  ────────────────────── Remediate within 7 days    │     │
│  │   ████████████████████ MEDIUM: 25  ──────── Remediate within 30 days   │     │
│  │   ████████████████████████████████████ LOW: 50  ─ Monitor              │     │
│  │                                                                         │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                  │
│  ═══════════════════════════════════════════════════════════════════════════   │
│                                                                                  │
│  CRITICAL VULNERABILITIES (Requires Immediate Attention)                         │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │                                                                         │     │
│  │  CVE-2024-0001                                                          │     │
│  │  ────────────────────────────────────────────────────────────────────  │     │
│  │  Package:      openssl                                                  │     │
│  │  Installed:    3.0.11                                                   │     │
│  │  Fixed:        3.0.13                                                   │     │
│  │  CVSS:         9.8                                                      │     │
│  │                                                                         │     │
│  │  Description:  Remote code execution vulnerability in OpenSSL's        │     │
│  │                X.509 certificate verification. An attacker can         │     │
│  │                execute arbitrary code by providing a malicious         │     │
│  │                certificate chain.                                       │     │
│  │                                                                         │     │
│  │  References:                                                            │     │
│  │  • https://nvd.nist.gov/vuln/detail/CVE-2024-0001                      │     │
│  │  • https://www.openssl.org/news/secadv/20240115.txt                    │     │
│  │                                                                         │     │
│  │  Remediation:  Update openssl to version 3.0.13 or later               │     │
│  │                                                                         │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                  │
│  ═══════════════════════════════════════════════════════════════════════════   │
│                                                                                  │
│  SBOM SUMMARY                                                                    │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │                                                                         │     │
│  │  Total Components: 247                                                  │     │
│  │  ├── OS Packages: 68                                                   │     │
│  │  ├── Node.js Packages: 156                                             │     │
│  │  └── Python Packages: 23                                               │     │
│  │                                                                         │     │
│  │  License Distribution:                                                  │     │
│  │  ├── MIT: 142 (57%)                                                    │     │
│  │  ├── Apache-2.0: 45 (18%)                                              │     │
│  │  ├── BSD-3-Clause: 28 (11%)                                            │     │
│  │  ├── ISC: 19 (8%)                                                      │     │
│  │  └── Other: 13 (6%)                                                    │     │
│  │                                                                         │     │
│  │  SBOM Format: CycloneDX v1.5                                           │     │
│  │  Download: /reports/myapp-v1.2.3-sbom.json                             │     │
│  │                                                                         │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Policy Enforcement with OPA Gatekeeper](./SIAB-OPA-Gatekeeper-Policies.md)
- [Compliance & Audit](./SIAB-Compliance-Audit.md)
