# SIAB - OPA Gatekeeper Policy Enforcement

## Overview

Open Policy Agent (OPA) Gatekeeper provides admission control policy enforcement for Kubernetes. In SIAB, Gatekeeper acts as a validating webhook that intercepts all resource creation and modification requests, ensuring they comply with organizational security policies before being admitted to the cluster.

---

## Policy Enforcement Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     OPA GATEKEEPER ADMISSION CONTROL FLOW                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐                                                               │
│  │   kubectl    │                                                               │
│  │   apply      │                                                               │
│  │   create     │                                                               │
│  └──────┬───────┘                                                               │
│         │                                                                        │
│         ▼                                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        KUBERNETES API SERVER                             │    │
│  │                                                                          │    │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐   │    │
│  │  │ Authenti-  │───▶│ Authori-   │───▶│ Admission  │───▶│  Persist   │   │    │
│  │  │ cation     │    │ zation     │    │ Controllers│    │  to etcd   │   │    │
│  │  └────────────┘    └────────────┘    └─────┬──────┘    └────────────┘   │    │
│  │                                            │                             │    │
│  └────────────────────────────────────────────┼─────────────────────────────┘    │
│                                               │                                  │
│                                               ▼                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                      GATEKEEPER VALIDATING WEBHOOK                       │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    ADMISSION REQUEST                             │    │    │
│  │  │                                                                  │    │    │
│  │  │   {                                                              │    │    │
│  │  │     "kind": "AdmissionReview",                                   │    │    │
│  │  │     "request": {                                                 │    │    │
│  │  │       "uid": "abc-123",                                          │    │    │
│  │  │       "kind": {"kind": "Pod"},                                   │    │    │
│  │  │       "object": { ... pod spec ... },                            │    │    │
│  │  │       "operation": "CREATE"                                      │    │    │
│  │  │     }                                                            │    │    │
│  │  │   }                                                              │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                    │                                     │    │
│  │                                    ▼                                     │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    POLICY EVALUATION ENGINE                      │    │    │
│  │  │                                                                  │    │    │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │    │    │
│  │  │  │ Constraint  │  │ Constraint  │  │ Constraint  │   ...        │    │    │
│  │  │  │ Templates   │  │ Instances   │  │ Parameters  │              │    │    │
│  │  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │    │    │
│  │  │         │                │                │                      │    │    │
│  │  │         └────────────────┼────────────────┘                      │    │    │
│  │  │                          ▼                                       │    │    │
│  │  │              ┌───────────────────────┐                           │    │    │
│  │  │              │     REGO POLICIES     │                           │    │    │
│  │  │              │                       │                           │    │    │
│  │  │              │  • Non-root check     │                           │    │    │
│  │  │              │  • Resource limits    │                           │    │    │
│  │  │              │  • Privileged block   │                           │    │    │
│  │  │              │  • Image tag check    │                           │    │    │
│  │  │              │  • Host namespace     │                           │    │    │
│  │  │              │  • Label requirements │                           │    │    │
│  │  │              └───────────────────────┘                           │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                    │                                     │    │
│  │                                    ▼                                     │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                    ADMISSION RESPONSE                            │    │    │
│  │  │                                                                  │    │    │
│  │  │   ALLOWED ────────────────────────────────────▶ Resource Created │    │    │
│  │  │                                                                  │    │    │
│  │  │   DENIED  ────────────────────────────────────▶ Error Message    │    │    │
│  │  │              "Container X must specify cpu limits"               │    │    │
│  │  │              "Privileged containers not allowed"                 │    │    │
│  │  │                                                                  │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Gatekeeper Components

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         GATEKEEPER COMPONENT ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  NAMESPACE: gatekeeper-system                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  ┌──────────────────────────────┐  ┌──────────────────────────────┐     │    │
│  │  │    GATEKEEPER CONTROLLER     │  │     GATEKEEPER AUDIT         │     │    │
│  │  │       (2 Replicas)           │  │       (1 Replica)            │     │    │
│  │  │                              │  │                              │     │    │
│  │  │  • Validates admission       │  │  • Scans existing resources  │     │    │
│  │  │    requests in real-time     │  │  • Reports violations        │     │    │
│  │  │  • Enforces constraints      │  │  • Runs every 60 seconds     │     │    │
│  │  │  • HA deployment             │  │  • Background compliance     │     │    │
│  │  │                              │  │                              │     │    │
│  │  └──────────────────────────────┘  └──────────────────────────────┘     │    │
│  │                                                                          │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │                    VALIDATING WEBHOOK CONFIG                      │   │    │
│  │  │                                                                   │   │    │
│  │  │  webhooks:                                                        │   │    │
│  │  │  - name: validation.gatekeeper.sh                                 │   │    │
│  │  │    rules:                                                         │   │    │
│  │  │    - apiGroups: ["*"]                                             │   │    │
│  │  │      apiVersions: ["*"]                                           │   │    │
│  │  │      operations: ["CREATE", "UPDATE"]                             │   │    │
│  │  │      resources: ["*"]                                             │   │    │
│  │  │    failurePolicy: Fail                                            │   │    │
│  │  │    sideEffects: None                                              │   │    │
│  │  └──────────────────────────────────────────────────────────────────┘   │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  CUSTOM RESOURCE DEFINITIONS:                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  ┌────────────────────────┐    ┌────────────────────────┐               │    │
│  │  │  ConstraintTemplate    │    │     Config             │               │    │
│  │  │                        │    │                        │               │    │
│  │  │  Defines reusable      │    │  Gatekeeper settings   │               │    │
│  │  │  policy logic in Rego  │    │  Sync configuration    │               │    │
│  │  └────────────────────────┘    └────────────────────────┘               │    │
│  │                                                                          │    │
│  │  ┌────────────────────────┐    ┌────────────────────────┐               │    │
│  │  │  Constraint            │    │     Provider           │               │    │
│  │  │                        │    │                        │               │    │
│  │  │  Instance of template  │    │  External data source  │               │    │
│  │  │  with specific params  │    │  for policy decisions  │               │    │
│  │  └────────────────────────┘    └────────────────────────┘               │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## SIAB Policy Templates and Constraints

### Policy Summary Matrix

| Policy | Purpose | Enforcement Level | Excluded Namespaces |
|--------|---------|-------------------|---------------------|
| **K8sRequireNonRoot** | Prevent root containers | Block | kube-system, istio-system, cert-manager, gatekeeper-system, trivy-system |
| **K8sRequireResourceLimits** | Enforce resource quotas | Block | kube-system |
| **K8sBlockPrivileged** | Block privileged mode | Block | kube-system |
| **K8sBlockLatestImage** | Require explicit tags | Block | kube-system, local-path-storage |
| **K8sBlockHostNamespace** | Block host networking | Block | kube-system, istio-system |
| **K8sRequireLabels** | Enforce labeling standards | Block | Configurable |
| **K8sRequireReadOnlyRootFS** | Require immutable containers | Audit | None |

---

## Policy 1: Require Non-Root Containers

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         K8sRequireNonRoot POLICY                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PURPOSE: Prevent containers from running as root user (UID 0)                   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         SECURITY RATIONALE                               │    │
│  │                                                                          │    │
│  │  Running as root inside a container poses significant security risks:    │    │
│  │                                                                          │    │
│  │  1. CONTAINER ESCAPE: Root in container = potential root on host         │    │
│  │  2. FILE SYSTEM ACCESS: Root can read/write any file in container        │    │
│  │  3. PRIVILEGE ESCALATION: Root can modify security settings              │    │
│  │  4. LATERAL MOVEMENT: Compromised root container aids attackers          │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  REGO POLICY LOGIC:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  package k8srequirenonroot                                               │    │
│  │                                                                          │    │
│  │  violation[{"msg": msg}] {                                               │    │
│  │      container := input.review.object.spec.containers[_]                 │    │
│  │      not container.securityContext.runAsNonRoot                          │    │
│  │      msg := sprintf("Container %v must set runAsNonRoot", [name])        │    │
│  │  }                                                                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  DECISION FLOW:                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │                    Pod Admission Request                                 │    │
│  │                           │                                              │    │
│  │                           ▼                                              │    │
│  │              ┌────────────────────────┐                                  │    │
│  │              │  Check each container  │                                  │    │
│  │              └────────────┬───────────┘                                  │    │
│  │                           │                                              │    │
│  │                           ▼                                              │    │
│  │              ┌────────────────────────┐                                  │    │
│  │              │  securityContext       │                                  │    │
│  │              │  .runAsNonRoot = true? │                                  │    │
│  │              └────────────┬───────────┘                                  │    │
│  │                     ╱           ╲                                        │    │
│  │                   YES            NO                                      │    │
│  │                   ╱               ╲                                      │    │
│  │               ┌──────┐        ┌────────┐                                 │    │
│  │               │ PASS │        │ DENY   │                                 │    │
│  │               │      │        │ with   │                                 │    │
│  │               │      │        │ message│                                 │    │
│  │               └──────┘        └────────┘                                 │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  COMPLIANT EXAMPLE:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  apiVersion: v1                                                          │    │
│  │  kind: Pod                                                               │    │
│  │  spec:                                                                   │    │
│  │    containers:                                                           │    │
│  │    - name: app                                                           │    │
│  │      image: myapp:v1.2.3                                                 │    │
│  │      securityContext:                     ◄─── Required                  │    │
│  │        runAsNonRoot: true                 ◄─── Must be true              │    │
│  │        runAsUser: 1000                    ◄─── Non-zero UID              │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy 2: Require Resource Limits

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      K8sRequireResourceLimits POLICY                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PURPOSE: Ensure all containers specify CPU and memory limits                    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         SECURITY RATIONALE                               │    │
│  │                                                                          │    │
│  │  Without resource limits, containers can:                                │    │
│  │                                                                          │    │
│  │  1. DENIAL OF SERVICE: Consume all node resources                        │    │
│  │  2. NOISY NEIGHBOR: Starve other workloads                               │    │
│  │  3. CRYPTO MINING: Attackers exploit unlimited CPU                       │    │
│  │  4. MEMORY EXHAUSTION: OOM kills affecting other pods                    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  RESOURCE LIMIT ENFORCEMENT:                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  ┌─────────────────┐                  ┌─────────────────┐                │    │
│  │  │   WITHOUT       │                  │    WITH         │                │    │
│  │  │   LIMITS        │                  │    LIMITS       │                │    │
│  │  └────────┬────────┘                  └────────┬────────┘                │    │
│  │           │                                    │                         │    │
│  │           ▼                                    ▼                         │    │
│  │  ┌─────────────────┐                  ┌─────────────────┐                │    │
│  │  │ Container can   │                  │ Container is    │                │    │
│  │  │ consume ALL     │                  │ bounded to:     │                │    │
│  │  │ available       │                  │                 │                │    │
│  │  │ resources       │                  │ CPU: 500m max   │                │    │
│  │  │                 │                  │ Memory: 512Mi   │                │    │
│  │  └────────┬────────┘                  └────────┬────────┘                │    │
│  │           │                                    │                         │    │
│  │           ▼                                    ▼                         │    │
│  │  ┌─────────────────┐                  ┌─────────────────┐                │    │
│  │  │ Node resource   │                  │ Fair resource   │                │    │
│  │  │ exhaustion      │                  │ sharing across  │                │    │
│  │  │                 │                  │ all workloads   │                │    │
│  │  │ ██████████████  │                  │ ████░░░░░░░░░░  │                │    │
│  │  │ 100% consumed   │                  │ ~40% allocated  │                │    │
│  │  └─────────────────┘                  └─────────────────┘                │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  COMPLIANT EXAMPLE:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  spec:                                                                   │    │
│  │    containers:                                                           │    │
│  │    - name: app                                                           │    │
│  │      resources:                           ◄─── Required section          │    │
│  │        limits:                            ◄─── Must specify limits       │    │
│  │          cpu: "500m"                      ◄─── CPU limit required        │    │
│  │          memory: "512Mi"                  ◄─── Memory limit required     │    │
│  │        requests:                                                         │    │
│  │          cpu: "250m"                                                     │    │
│  │          memory: "256Mi"                                                 │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy 3: Block Privileged Containers

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       K8sBlockPrivileged POLICY                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PURPOSE: Prevent containers from running in privileged mode                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     PRIVILEGED MODE DANGER                               │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                    PRIVILEGED CONTAINER                            │  │    │
│  │  │                                                                    │  │    │
│  │  │  privileged: true                                                  │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ├──▶ Full access to host devices (/dev/*)                    │  │    │
│  │  │       ├──▶ Can load kernel modules                                 │  │    │
│  │  │       ├──▶ Access to host network stack                            │  │    │
│  │  │       ├──▶ Can modify host iptables                                │  │    │
│  │  │       ├──▶ Access to all host capabilities                         │  │    │
│  │  │       └──▶ Effectively SAME AS ROOT ON HOST                        │  │    │
│  │  │                                                                    │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                   UNPRIVILEGED CONTAINER                           │  │    │
│  │  │                                                                    │  │    │
│  │  │  privileged: false (default)                                       │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ├──▶ Limited device access                                   │  │    │
│  │  │       ├──▶ Cannot load kernel modules                              │  │    │
│  │  │       ├──▶ Isolated network namespace                              │  │    │
│  │  │       ├──▶ Restricted capabilities                                 │  │    │
│  │  │       └──▶ PROPER CONTAINER ISOLATION                              │  │    │
│  │  │                                                                    │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ATTACK SCENARIO BLOCKED:                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  ATTACKER                                                                │    │
│  │     │                                                                    │    │
│  │     ▼                                                                    │    │
│  │  ┌─────────────────────────────────────────┐                            │    │
│  │  │  Deploy malicious pod with:             │                            │    │
│  │  │  securityContext:                       │                            │    │
│  │  │    privileged: true                     │                            │    │
│  │  └────────────────────┬────────────────────┘                            │    │
│  │                       │                                                  │    │
│  │                       ▼                                                  │    │
│  │  ┌─────────────────────────────────────────┐                            │    │
│  │  │          GATEKEEPER                     │                            │    │
│  │  │                                         │                            │    │
│  │  │  ╔═══════════════════════════════════╗  │                            │    │
│  │  │  ║         ACCESS DENIED             ║  │                            │    │
│  │  │  ║                                   ║  │                            │    │
│  │  │  ║  Privileged containers are        ║  │                            │    │
│  │  │  ║  not allowed: malicious-container ║  │                            │    │
│  │  │  ╚═══════════════════════════════════╝  │                            │    │
│  │  └─────────────────────────────────────────┘                            │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy 4: Block Latest Image Tag

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       K8sBlockLatestImage POLICY                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PURPOSE: Require explicit version tags for container images                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         WHY BLOCK :latest                                │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                                                                  │    │    │
│  │  │   "latest" Tag Problems:                                         │    │    │
│  │  │                                                                  │    │    │
│  │  │   1. NON-REPRODUCIBLE                                            │    │    │
│  │  │      └─ Same manifest = different image over time                │    │    │
│  │  │                                                                  │    │    │
│  │  │   2. UNTRACEABLE                                                 │    │    │
│  │  │      └─ Cannot audit what version is running                     │    │    │
│  │  │                                                                  │    │    │
│  │  │   3. SUPPLY CHAIN RISK                                           │    │    │
│  │  │      └─ Attackers can poison :latest in registries               │    │    │
│  │  │                                                                  │    │    │
│  │  │   4. ROLLBACK IMPOSSIBLE                                         │    │    │
│  │  │      └─ Cannot restore "previous latest"                         │    │    │
│  │  │                                                                  │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  POLICY ENFORCEMENT:                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │   ┌──────────────────────────┐    ┌──────────────────────────┐          │    │
│  │   │ image: nginx:latest      │    │ image: nginx             │          │    │
│  │   │                          │    │ (no tag = implicit       │          │    │
│  │   │ Explicit :latest tag     │    │  :latest)                │          │    │
│  │   └────────────┬─────────────┘    └────────────┬─────────────┘          │    │
│  │                │                               │                         │    │
│  │                ▼                               ▼                         │    │
│  │        ┌──────────────┐                ┌──────────────┐                  │    │
│  │        │    DENIED    │                │    DENIED    │                  │    │
│  │        │              │                │              │                  │    │
│  │        │  ":latest    │                │  "must       │                  │    │
│  │        │  not allowed"│                │  specify     │                  │    │
│  │        │              │                │  image tag"  │                  │    │
│  │        └──────────────┘                └──────────────┘                  │    │
│  │                                                                          │    │
│  │   ┌──────────────────────────┐                                          │    │
│  │   │ image: nginx:1.25.3      │                                          │    │
│  │   │                          │                                          │    │
│  │   │ Explicit version tag     │                                          │    │
│  │   └────────────┬─────────────┘                                          │    │
│  │                │                                                         │    │
│  │                ▼                                                         │    │
│  │        ┌──────────────┐                                                  │    │
│  │        │   ALLOWED    │                                                  │    │
│  │        │              │                                                  │    │
│  │        │  Reproducible│                                                  │    │
│  │        │  Auditable   │                                                  │    │
│  │        │  Rollbackable│                                                  │    │
│  │        └──────────────┘                                                  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy 5: Block Host Namespaces

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       K8sBlockHostNamespace POLICY                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PURPOSE: Prevent pods from accessing host network, PID, and IPC namespaces      │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    HOST NAMESPACE ISOLATION                              │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │                         HOST SYSTEM                              │    │    │
│  │  │                                                                  │    │    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │    │    │
│  │  │  │ Host Network │  │  Host PID    │  │  Host IPC    │           │    │    │
│  │  │  │ Namespace    │  │  Namespace   │  │  Namespace   │           │    │    │
│  │  │  │              │  │              │  │              │           │    │    │
│  │  │  │ • eth0       │  │ • PID 1      │  │ • Shared Mem │           │    │    │
│  │  │  │ • All ports  │  │ • All procs  │  │ • Semaphores │           │    │    │
│  │  │  │ • iptables   │  │ • /proc      │  │ • Msg queues │           │    │    │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘           │    │    │
│  │  │         ▲                  ▲                  ▲                  │    │    │
│  │  │         │                  │                  │                  │    │    │
│  │  │    ┌────┴────┐        ┌────┴────┐        ┌────┴────┐            │    │    │
│  │  │    │ BLOCKED │        │ BLOCKED │        │ BLOCKED │            │    │    │
│  │  │    │   BY    │        │   BY    │        │   BY    │            │    │    │
│  │  │    │ POLICY  │        │ POLICY  │        │ POLICY  │            │    │    │
│  │  │    └────┬────┘        └────┬────┘        └────┬────┘            │    │    │
│  │  │         │                  │                  │                  │    │    │
│  │  └─────────┼──────────────────┼──────────────────┼──────────────────┘    │    │
│  │            │                  │                  │                       │    │
│  │  ┌─────────┴──────────────────┴──────────────────┴──────────────────┐    │    │
│  │  │                    CONTAINER (ISOLATED)                           │    │    │
│  │  │                                                                   │    │    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │    │    │
│  │  │  │ Container    │  │ Container    │  │ Container    │            │    │    │
│  │  │  │ Network NS   │  │ PID NS       │  │ IPC NS       │            │    │    │
│  │  │  │              │  │              │  │              │            │    │    │
│  │  │  │ • veth pair  │  │ • PID 1=app  │  │ • Isolated   │            │    │    │
│  │  │  │ • Own IP     │  │ • Own /proc  │  │ • Private    │            │    │    │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘            │    │    │
│  │  │                                                                   │    │    │
│  │  └───────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  BLOCKED CONFIGURATIONS:                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  spec:                    │  spec:                │  spec:               │    │
│  │    hostNetwork: true  ✗   │    hostPID: true  ✗   │    hostIPC: true ✗   │    │
│  │                           │                       │                      │    │
│  │  "Using hostNetwork       │  "Using hostPID       │  "Using hostIPC      │    │
│  │   is not allowed"         │   is not allowed"     │   is not allowed"    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy Audit and Compliance

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        GATEKEEPER AUDIT PROCESS                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     CONTINUOUS COMPLIANCE MONITORING                     │    │
│  │                                                                          │    │
│  │    ┌─────────────┐                                                       │    │
│  │    │  GATEKEEPER │                                                       │    │
│  │    │   AUDIT     │◄────────────────────────────────┐                     │    │
│  │    │  CONTROLLER │                                 │                     │    │
│  │    └──────┬──────┘                                 │                     │    │
│  │           │                                        │                     │    │
│  │           │  Every 60 seconds                      │                     │    │
│  │           │                                        │                     │    │
│  │           ▼                                        │                     │    │
│  │    ┌─────────────────────────────────────────┐    │                     │    │
│  │    │         SCAN ALL RESOURCES              │    │                     │    │
│  │    │                                         │    │                     │    │
│  │    │  • All Pods in all namespaces           │    │ Loop                │    │
│  │    │  • All Deployments                      │    │                     │    │
│  │    │  • All StatefulSets                     │    │                     │    │
│  │    │  • All DaemonSets                       │    │                     │    │
│  │    │  • All other targeted resources         │    │                     │    │
│  │    └──────────────┬──────────────────────────┘    │                     │    │
│  │                   │                               │                     │    │
│  │                   ▼                               │                     │    │
│  │    ┌─────────────────────────────────────────┐    │                     │    │
│  │    │    EVALUATE AGAINST ALL CONSTRAINTS     │    │                     │    │
│  │    │                                         │    │                     │    │
│  │    │  For each resource:                     │    │                     │    │
│  │    │  ├─ Check K8sRequireNonRoot             │    │                     │    │
│  │    │  ├─ Check K8sRequireResourceLimits      │    │                     │    │
│  │    │  ├─ Check K8sBlockPrivileged            │    │                     │    │
│  │    │  ├─ Check K8sBlockLatestImage           │    │                     │    │
│  │    │  └─ Check K8sBlockHostNamespace         │    │                     │    │
│  │    └──────────────┬──────────────────────────┘    │                     │    │
│  │                   │                               │                     │    │
│  │                   ▼                               │                     │    │
│  │    ┌─────────────────────────────────────────┐    │                     │    │
│  │    │         RECORD VIOLATIONS               │────┘                     │    │
│  │    │                                         │                          │    │
│  │    │  Violations stored in:                  │                          │    │
│  │    │  constraint.status.violations[]         │                          │    │
│  │    │                                         │                          │    │
│  │    │  Max: 100 violations per constraint     │                          │    │
│  │    └─────────────────────────────────────────┘                          │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  VIEWING AUDIT RESULTS:                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  $ kubectl get constraints                                               │    │
│  │  NAME                     ENFORCEMENT-ACTION   TOTAL-VIOLATIONS          │    │
│  │  require-non-root         deny                 3                         │    │
│  │  require-resource-limits  deny                 12                        │    │
│  │  block-privileged         deny                 0                         │    │
│  │  block-latest-image       deny                 5                         │    │
│  │  block-host-namespace     deny                 0                         │    │
│  │                                                                          │    │
│  │  $ kubectl describe constraint require-non-root                          │    │
│  │  Status:                                                                 │    │
│  │    Violations:                                                           │    │
│  │    - enforcement_action: deny                                            │    │
│  │      kind: Pod                                                           │    │
│  │      name: legacy-app-pod                                                │    │
│  │      namespace: default                                                  │    │
│  │      message: Container nginx must set runAsNonRoot to true              │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Policy Exemption System

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        NAMESPACE EXEMPTIONS                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  Some system namespaces require exemptions for proper operation:                 │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  NAMESPACE            │ EXEMPTED FROM           │ REASON                 │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  kube-system          │ All policies            │ Core K8s components    │    │
│  │                       │                         │ require elevated       │    │
│  │                       │                         │ privileges             │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  istio-system         │ Non-root, Host NS       │ Istio needs host       │    │
│  │                       │                         │ network for ingress    │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  cert-manager         │ Non-root                │ Cert management        │    │
│  │                       │                         │ requires root          │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  gatekeeper-system    │ Non-root                │ Self-exemption for     │    │
│  │                       │                         │ bootstrap              │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  trivy-system         │ Non-root                │ Scanner requires       │    │
│  │                       │                         │ elevated access        │    │
│  │  ─────────────────────┼─────────────────────────┼─────────────────────── │    │
│  │  local-path-storage   │ Latest image            │ Uses dynamic image     │    │
│  │                       │                         │ provisioning           │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  CONSTRAINT EXEMPTION CONFIGURATION:                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  apiVersion: constraints.gatekeeper.sh/v1beta1                           │    │
│  │  kind: K8sRequireNonRoot                                                 │    │
│  │  metadata:                                                               │    │
│  │    name: require-non-root                                                │    │
│  │  spec:                                                                   │    │
│  │    match:                                                                │    │
│  │      kinds:                                                              │    │
│  │        - apiGroups: [""]                                                 │    │
│  │          kinds: ["Pod"]                                                  │    │
│  │      excludedNamespaces:              ◄─── Exempted namespaces           │    │
│  │        - kube-system                                                     │    │
│  │        - istio-system                                                    │    │
│  │        - cert-manager                                                    │    │
│  │        - gatekeeper-system                                               │    │
│  │        - trivy-system                                                    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Integration with SIAB Security Stack

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                  GATEKEEPER IN SIAB SECURITY ECOSYSTEM                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │                      DEPLOYMENT PIPELINE                                 │    │
│  │                                                                          │    │
│  │   ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐           │    │
│  │   │  CI/CD  │────▶│  TRIVY  │────▶│GATEKEEPER│────▶│ RUNNING │           │    │
│  │   │ Build   │     │  Scan   │     │ Admit   │     │  POD    │           │    │
│  │   └─────────┘     └─────────┘     └─────────┘     └─────────┘           │    │
│  │        │              │               │               │                  │    │
│  │        │              │               │               │                  │    │
│  │        ▼              ▼               ▼               ▼                  │    │
│  │   Build image    Check for CVEs   Validate spec   Protected by          │    │
│  │   Push to        Block CRITICAL   Enforce policy  Istio mTLS            │    │
│  │   registry       vulnerabilities  Block violations                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  COMPLEMENTARY SECURITY LAYERS:                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  ┌───────────────────────┐                                              │    │
│  │  │      GATEKEEPER       │  Admission Control (Pre-deployment)          │    │
│  │  │                       │                                              │    │
│  │  │  • Blocks non-compliant pods before creation                         │    │
│  │  │  • Validates resource specifications                                 │    │
│  │  │  • Enforces security contexts                                        │    │
│  │  └───────────────────────┘                                              │    │
│  │            │                                                             │    │
│  │            │ Works with                                                  │    │
│  │            ▼                                                             │    │
│  │  ┌───────────────────────┐                                              │    │
│  │  │        TRIVY          │  Vulnerability Scanning (Pre-deployment)     │    │
│  │  │                       │                                              │    │
│  │  │  • Scans images for CVEs                                             │    │
│  │  │  • Generates SBOMs                                                   │    │
│  │  │  • Blocks images with critical vulnerabilities                       │    │
│  │  └───────────────────────┘                                              │    │
│  │            │                                                             │    │
│  │            │ Works with                                                  │    │
│  │            ▼                                                             │    │
│  │  ┌───────────────────────┐                                              │    │
│  │  │        ISTIO          │  Network Security (Runtime)                  │    │
│  │  │                       │                                              │    │
│  │  │  • mTLS between all services                                         │    │
│  │  │  • Authorization policies                                            │    │
│  │  │  • Traffic encryption                                                │    │
│  │  └───────────────────────┘                                              │    │
│  │            │                                                             │    │
│  │            │ Works with                                                  │    │
│  │            ▼                                                             │    │
│  │  ┌───────────────────────┐                                              │    │
│  │  │      KEYCLOAK         │  Identity & Access (Runtime)                 │    │
│  │  │                       │                                              │    │
│  │  │  • SSO authentication                                                │    │
│  │  │  • RBAC authorization                                                │    │
│  │  │  • Session management                                                │    │
│  │  └───────────────────────┘                                              │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Operational Commands

### View Constraint Status
```bash
# List all constraints
kubectl get constraints

# View constraint details with violations
kubectl describe constraint <constraint-name>

# Check Gatekeeper controller status
kubectl get pods -n gatekeeper-system
```

### View Audit Results
```bash
# View all violations for a specific constraint
kubectl get constraint require-non-root -o yaml | grep -A 100 violations

# Count total violations
kubectl get constraints -o json | jq '.items[].status.totalViolations'
```

### Test Policy Compliance
```bash
# Dry-run a deployment to check if it would be admitted
kubectl apply -f deployment.yaml --dry-run=server

# View webhook logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager
```

---

## Related Documentation

- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Trivy Vulnerability Scanning](./SIAB-Trivy-Security-Scanning.md)
- [Network Security & Istio](./SIAB-Network-Security.md)
- [Compliance & Audit](./SIAB-Compliance-Audit.md)
