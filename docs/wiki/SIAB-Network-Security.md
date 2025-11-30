# SIAB - Network Security & Istio Service Mesh

## Overview

SIAB implements a defense-in-depth network security architecture with multiple layers of protection. The network security stack includes host-level firewall protection (firewalld), Kubernetes-native network policies (Canal CNI), and service mesh encryption (Istio mTLS). Together, these layers ensure that all traffic is authenticated, encrypted, and authorized.

---

## Network Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       SIAB NETWORK SECURITY LAYERS                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         EXTERNAL TRAFFIC                                 │    │
│  │                                                                          │    │
│  │                    Internet / Corporate Network                          │    │
│  │                              │                                           │    │
│  │                              ▼                                           │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                 │                                                │
│                                 ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  LAYER 1: HOST FIREWALL (firewalld)                                     │    │
│  │  ──────────────────────────────────────────────────────────────────────  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                     PUBLIC ZONE                                    │  │    │
│  │  │                                                                    │  │    │
│  │  │  ALLOWED PORTS:                                                    │  │    │
│  │  │  ├─ 80/tcp, 443/tcp      ─── Web traffic (redirects to HTTPS)     │  │    │
│  │  │  ├─ 6443/tcp             ─── Kubernetes API                        │  │    │
│  │  │  ├─ 9345/tcp             ─── RKE2 Supervisor                       │  │    │
│  │  │  └─ 30000-32767/tcp      ─── NodePort services                     │  │    │
│  │  │                                                                    │  │    │
│  │  │  ALL OTHER TRAFFIC DROPPED                                         │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                    TRUSTED ZONE                                    │  │    │
│  │  │                                                                    │  │    │
│  │  │  TRUSTED SOURCES:                                                  │  │    │
│  │  │  ├─ 10.42.0.0/16         ─── Pod CIDR (internal pod traffic)       │  │    │
│  │  │  └─ 10.43.0.0/16         ─── Service CIDR (K8s services)           │  │    │
│  │  │                                                                    │  │    │
│  │  │  TRUSTED INTERFACES:                                               │  │    │
│  │  │  ├─ cni0                 ─── Container Network Interface           │  │    │
│  │  │  ├─ flannel.1            ─── Flannel VXLAN overlay                 │  │    │
│  │  │  └─ tunl0                ─── Calico IP-in-IP tunnel                │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                 │                                                │
│                                 ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  LAYER 2: ISTIO INGRESS GATEWAYS                                        │    │
│  │  ──────────────────────────────────────────────────────────────────────  │    │
│  │                                                                          │    │
│  │  ┌──────────────────────────┐    ┌──────────────────────────┐           │    │
│  │  │    ADMIN GATEWAY         │    │     USER GATEWAY         │           │    │
│  │  │    (istio-ingress-admin) │    │    (istio-ingress-user)  │           │    │
│  │  │                          │    │                          │           │    │
│  │  │  • TLS Termination       │    │  • TLS Termination       │           │    │
│  │  │  • HTTP→HTTPS Redirect   │    │  • HTTP→HTTPS Redirect   │           │    │
│  │  │  • JWT Validation        │    │  • JWT Validation        │           │    │
│  │  │  • External Auth         │    │  • OAuth2 Proxy Auth     │           │    │
│  │  │                          │    │                          │           │    │
│  │  │  Serves:                 │    │  Serves:                 │           │    │
│  │  │  • grafana.siab.local    │    │  • siab.local            │           │    │
│  │  │  • keycloak.siab.local   │    │  • dashboard.siab.local  │           │    │
│  │  │  • k8s-dashboard.siab    │    │  • deployer.siab.local   │           │    │
│  │  │  • minio.siab.local      │    │  • *.apps.siab.local     │           │    │
│  │  │  • longhorn.siab.local   │    │  • auth.siab.local       │           │    │
│  │  └──────────────────────────┘    └──────────────────────────┘           │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                 │                                                │
│                                 ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  LAYER 3: ISTIO SERVICE MESH (mTLS)                                     │    │
│  │  ──────────────────────────────────────────────────────────────────────  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                    ALL POD-TO-POD TRAFFIC                          │  │    │
│  │  │                                                                    │  │    │
│  │  │       ┌─────────┐           mTLS              ┌─────────┐         │  │    │
│  │  │       │  Pod A  │◄─────────────────────────►│  Pod B  │          │  │    │
│  │  │       │┌───────┐│   Encrypted + Verified     │┌───────┐│         │  │    │
│  │  │       ││Envoy  ││◄─────────────────────────►►││Envoy  ││         │  │    │
│  │  │       ││Sidecar││                            ││Sidecar││         │  │    │
│  │  │       │└───────┘│                            │└───────┘│         │  │    │
│  │  │       └─────────┘                            └─────────┘         │  │    │
│  │  │                                                                    │  │    │
│  │  │  • Automatic certificate issuance and rotation                     │  │    │
│  │  │  • Identity-based authentication (SPIFFE)                          │  │    │
│  │  │  • Zero-trust network model                                        │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                 │                                                │
│                                 ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  LAYER 4: KUBERNETES NETWORK POLICIES (Canal CNI)                       │    │
│  │  ──────────────────────────────────────────────────────────────────────  │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                   NAMESPACE ISOLATION                              │  │    │
│  │  │                                                                    │  │    │
│  │  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐         │  │    │
│  │  │  │   default    │    │  production  │    │  development │         │  │    │
│  │  │  │              │    │              │    │              │         │  │    │
│  │  │  │  Deny all    │    │  Deny all    │    │  Deny all    │         │  │    │
│  │  │  │  by default  │    │  by default  │    │  by default  │         │  │    │
│  │  │  │              │    │              │    │              │         │  │    │
│  │  │  │  Explicit    │    │  Explicit    │    │  Explicit    │         │  │    │
│  │  │  │  allow rules │    │  allow rules │    │  allow rules │         │  │    │
│  │  │  └──────────────┘    └──────────────┘    └──────────────┘         │  │    │
│  │  │                                                                    │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Traffic Flow with Security Enforcement

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       SECURE TRAFFIC FLOW DIAGRAM                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  USER REQUEST: https://dashboard.siab.local                                      │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 1: DNS Resolution                                                  │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    User Browser                                                          │    │
│  │         │                                                                │    │
│  │         │  DNS Query: dashboard.siab.local                               │    │
│  │         ▼                                                                │    │
│  │    DNS Server ─────────► Returns: LoadBalancer IP (MetalLB)              │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                          │                                                       │
│                          ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 2: Firewall Check                                                  │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    firewalld                                                             │    │
│  │         │                                                                │    │
│  │         ├── Port 443/tcp? ──────────────► ALLOWED                        │    │
│  │         │                                                                │    │
│  │         └── Other ports? ───────────────► DROPPED                        │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                          │                                                       │
│                          ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 3: TLS Termination at Istio Gateway                                │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    Istio User Gateway (LoadBalancer)                                     │    │
│  │         │                                                                │    │
│  │         ├── TLS handshake (TLS 1.2+)                                     │    │
│  │         │   └── Certificate: siab-gateway-cert                           │    │
│  │         │                                                                │    │
│  │         ├── Decrypt HTTPS ───────────► HTTP internally                   │    │
│  │         │                                                                │    │
│  │         └── Match VirtualService                                         │    │
│  │             └── Host: dashboard.siab.local                               │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                          │                                                       │
│                          ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 4: Authentication Check                                            │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    RequestAuthentication (JWT Validation)                                │    │
│  │         │                                                                │    │
│  │         ├── JWT Token Present?                                           │    │
│  │         │        │                                                       │    │
│  │         │        ├── YES ──► Validate against Keycloak JWKS              │    │
│  │         │        │           └── Valid? ──► Continue                     │    │
│  │         │        │           └── Invalid? ──► 401 Unauthorized           │    │
│  │         │        │                                                       │    │
│  │         │        └── NO ───► Check AuthorizationPolicy                   │    │
│  │         │                    └── Unauthenticated allowed? ──► Continue   │    │
│  │         │                    └── Required? ──► Redirect to Keycloak      │    │
│  │         │                                                                │    │
│  │         └── OAuth2 Proxy Ext Auth                                        │    │
│  │             └── /oauth2/auth ───► Validate session cookie                │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                          │                                                       │
│                          ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 5: mTLS to Backend Service                                         │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    Gateway ──────mTLS──────► Dashboard Service                           │    │
│  │                                                                          │    │
│  │    Certificate Chain:                                                    │    │
│  │    ┌────────────────────────────────────────────────────────────────┐   │    │
│  │    │  Istio CA (Root)                                                │   │    │
│  │    │       │                                                         │   │    │
│  │    │       └──► Workload Certificate                                 │   │    │
│  │    │            Subject: spiffe://cluster.local/ns/dashboard/sa/     │   │    │
│  │    │            Validity: 24 hours (auto-rotated)                    │   │    │
│  │    └────────────────────────────────────────────────────────────────┘   │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                          │                                                       │
│                          ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  STEP 6: Response Path                                                   │    │
│  │  ─────────────────────────────────────────────────────────────────────── │    │
│  │                                                                          │    │
│  │    Dashboard Pod ──mTLS──► Gateway ──TLS──► User Browser                 │    │
│  │                                                                          │    │
│  │    Response Headers Added:                                               │    │
│  │    ├── X-Auth-Request-User: john@company.com                             │    │
│  │    ├── X-Auth-Request-Groups: siab-admin,siab-operator                   │    │
│  │    └── Strict-Transport-Security: max-age=31536000                       │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Istio mTLS Configuration

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          ISTIO mTLS MODES                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     PeerAuthentication Policies                          │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │  MESH-WIDE DEFAULT (istio-system/default)                        │    │    │
│  │  │                                                                  │    │    │
│  │  │  apiVersion: security.istio.io/v1beta1                           │    │    │
│  │  │  kind: PeerAuthentication                                        │    │    │
│  │  │  metadata:                                                       │    │    │
│  │  │    name: default                                                 │    │    │
│  │  │    namespace: istio-system                                       │    │    │
│  │  │  spec:                                                           │    │    │
│  │  │    mtls:                                                         │    │    │
│  │  │      mode: STRICT    ◄─── All mesh traffic MUST use mTLS         │    │    │
│  │  │                                                                  │    │    │
│  │  │  IMPACT: Every service-to-service call is encrypted              │    │    │
│  │  │          and mutually authenticated                              │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │    │
│  │  │  INGRESS GATEWAY EXCEPTION                                       │    │    │
│  │  │                                                                  │    │    │
│  │  │  apiVersion: security.istio.io/v1beta1                           │    │    │
│  │  │  kind: PeerAuthentication                                        │    │    │
│  │  │  metadata:                                                       │    │    │
│  │  │    name: ingress-user-mtls                                       │    │    │
│  │  │  spec:                                                           │    │    │
│  │  │    selector:                                                     │    │    │
│  │  │      matchLabels:                                                │    │    │
│  │  │        istio: ingress-user                                       │    │    │
│  │  │    mtls:                                                         │    │    │
│  │  │      mode: PERMISSIVE   ◄─── Accept both mTLS and plain TLS      │    │    │
│  │  │                                                                  │    │    │
│  │  │  WHY: External clients don't have Istio certificates             │    │    │
│  │  │       Gateway terminates TLS, then uses mTLS internally          │    │    │
│  │  └─────────────────────────────────────────────────────────────────┘    │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  mTLS MODE COMPARISON:                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │  MODE        │ BEHAVIOR                                                  │    │
│  │  ────────────┼───────────────────────────────────────────────────────── │    │
│  │  STRICT      │ Only accept mTLS connections                              │    │
│  │              │ Reject plain-text traffic                                 │    │
│  │              │ Highest security (default for mesh)                       │    │
│  │  ────────────┼───────────────────────────────────────────────────────── │    │
│  │  PERMISSIVE  │ Accept both mTLS and plain-text                           │    │
│  │              │ Used for ingress gateways                                 │    │
│  │              │ Allows external traffic                                   │    │
│  │  ────────────┼───────────────────────────────────────────────────────── │    │
│  │  DISABLE     │ Only accept plain-text (NOT USED IN SIAB)                 │    │
│  │              │ No encryption or authentication                           │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Gateway Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ISTIO DUAL GATEWAY ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│                              EXTERNAL TRAFFIC                                    │
│                                    │                                             │
│                    ┌───────────────┴───────────────┐                            │
│                    │                               │                             │
│                    ▼                               ▼                             │
│  ┌─────────────────────────────────┐ ┌─────────────────────────────────┐        │
│  │      ADMIN GATEWAY              │ │      USER GATEWAY               │        │
│  │      (LoadBalancer)             │ │      (LoadBalancer)             │        │
│  │                                 │ │                                 │        │
│  │  Selector:                      │ │  Selector:                      │        │
│  │    istio: ingress-admin         │ │    istio: ingress-user          │        │
│  │                                 │ │                                 │        │
│  │  TLS:                           │ │  TLS:                           │        │
│  │    credentialName:              │ │    credentialName:              │        │
│  │      siab-gateway-cert          │ │      siab-gateway-cert          │        │
│  │    mode: SIMPLE                 │ │    mode: SIMPLE                 │        │
│  │                                 │ │                                 │        │
│  │  HTTP Redirect: YES             │ │  HTTP Redirect: YES             │        │
│  │                                 │ │                                 │        │
│  │  ┌───────────────────────────┐  │ │  ┌───────────────────────────┐  │        │
│  │  │   ADMIN SERVICES          │  │ │  │   USER SERVICES           │  │        │
│  │  │                           │  │ │  │                           │  │        │
│  │  │  • grafana.siab.local     │  │ │  │  • siab.local             │  │        │
│  │  │  • keycloak.siab.local    │  │ │  │  • dashboard.siab.local   │  │        │
│  │  │  • k8s-dashboard.siab     │  │ │  │  • deployer.siab.local    │  │        │
│  │  │  • minio.siab.local       │  │ │  │  • catalog.siab.local     │  │        │
│  │  │  • longhorn.siab.local    │  │ │  │  • auth.siab.local        │  │        │
│  │  │  • *.admin.siab.local     │  │ │  │  • *.apps.siab.local      │  │        │
│  │  │                           │  │ │  │                           │  │        │
│  │  └───────────────────────────┘  │ │  └───────────────────────────┘  │        │
│  │                                 │ │                                 │        │
│  │  SECURITY:                      │ │  SECURITY:                      │        │
│  │  • JWT validation               │ │  • JWT validation               │        │
│  │  • Services have own auth       │ │  • OAuth2 Proxy ext_authz       │        │
│  │                                 │ │  • Keycloak SSO enforced        │        │
│  │                                 │ │                                 │        │
│  └─────────────────────────────────┘ └─────────────────────────────────┘        │
│                    │                               │                             │
│                    └───────────────┬───────────────┘                            │
│                                    │                                             │
│                                    ▼                                             │
│                             mTLS TO BACKENDS                                     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Firewall Port Configuration

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     FIREWALLD PORT CONFIGURATION                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    EXTERNAL ACCESS PORTS                                 │    │
│  │                                                                          │    │
│  │  PORT        │ PROTOCOL │ SERVICE                    │ NOTES            │    │
│  │  ────────────┼──────────┼────────────────────────────┼──────────────── │    │
│  │  80/tcp      │ HTTP     │ Web Traffic                │ Redirects to 443│    │
│  │  443/tcp     │ HTTPS    │ Web Traffic                │ TLS terminated  │    │
│  │  6443/tcp    │ HTTPS    │ Kubernetes API             │ kubectl access  │    │
│  │  9345/tcp    │ HTTPS    │ RKE2 Supervisor            │ Node join       │    │
│  │  30000-32767 │ TCP      │ NodePort Services          │ K8s NodePorts   │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    INTERNAL CLUSTER PORTS                                │    │
│  │                                                                          │    │
│  │  PORT        │ PROTOCOL │ SERVICE                    │ NOTES            │    │
│  │  ────────────┼──────────┼────────────────────────────┼──────────────── │    │
│  │  10250/tcp   │ TCP      │ Kubelet API                │ Metrics/logs    │    │
│  │  2379-2380   │ TCP      │ etcd                       │ Cluster state   │    │
│  │  8472/udp    │ UDP      │ Flannel VXLAN              │ Pod overlay     │    │
│  │  4789/udp    │ UDP      │ VXLAN fallback             │ CNI networking  │    │
│  │  51820-51821 │ UDP      │ Wireguard (if enabled)     │ Encrypted CNI   │    │
│  │  179/tcp     │ TCP      │ Calico BGP                 │ Route sharing   │    │
│  │  5473/tcp    │ TCP      │ Calico Typha               │ Policy sync     │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    ISTIO CONTROL PLANE PORTS                             │    │
│  │                                                                          │    │
│  │  PORT        │ PROTOCOL │ SERVICE                    │ NOTES            │    │
│  │  ────────────┼──────────┼────────────────────────────┼──────────────── │    │
│  │  15010/tcp   │ gRPC     │ Istiod xDS                 │ Config push     │    │
│  │  15012/tcp   │ gRPC     │ Istiod xDS (mTLS)          │ Secure config   │    │
│  │  15014/tcp   │ HTTP     │ Istiod control plane       │ Debug/status    │    │
│  │  15017/tcp   │ HTTPS    │ Webhook server             │ Injection       │    │
│  │  15021/tcp   │ HTTP     │ Health check               │ Readiness       │    │
│  │  15090/tcp   │ HTTP     │ Envoy Prometheus           │ Metrics         │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Network Zones and Segmentation

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      NETWORK ZONE ARCHITECTURE                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │                        UNTRUSTED ZONE                                    │    │
│  │                       (Internet/External)                                │    │
│  │                                                                          │    │
│  │                              │                                           │    │
│  │                              │ Only 80/443 allowed                       │    │
│  │                              ▼                                           │    │
│  └──────────────────────────────┼───────────────────────────────────────────┘    │
│                                 │                                                │
│  ┌──────────────────────────────┼───────────────────────────────────────────┐    │
│  │                              │                                            │    │
│  │                       DMZ ZONE                                            │    │
│  │                    (Ingress Gateways)                                     │    │
│  │                                                                           │    │
│  │    ┌─────────────────┐          ┌─────────────────┐                      │    │
│  │    │  Admin Gateway  │          │  User Gateway   │                      │    │
│  │    │                 │          │                 │                      │    │
│  │    │  TLS Termination│          │  TLS Termination│                      │    │
│  │    │  Auth Validation│          │  OAuth2 Proxy   │                      │    │
│  │    └────────┬────────┘          └────────┬────────┘                      │    │
│  │             │                            │                                │    │
│  └─────────────┼────────────────────────────┼────────────────────────────────┘    │
│                │                            │                                     │
│                │ mTLS Only                  │ mTLS Only                           │
│                ▼                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                                                                          │    │
│  │                      TRUSTED ZONE                                        │    │
│  │               (Internal Kubernetes Services)                             │    │
│  │                                                                          │    │
│  │    ┌──────────────────────────────────────────────────────────────┐     │    │
│  │    │                    SYSTEM NAMESPACES                          │     │    │
│  │    │                                                               │     │    │
│  │    │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │     │    │
│  │    │  │ kube-system │ │ istio-system│ │  keycloak   │             │     │    │
│  │    │  │             │ │             │ │             │             │     │    │
│  │    │  │ K8s Core    │ │ Istio       │ │ Identity    │             │     │    │
│  │    │  │ Components  │ │ Control     │ │ Provider    │             │     │    │
│  │    │  └─────────────┘ └─────────────┘ └─────────────┘             │     │    │
│  │    │                                                               │     │    │
│  │    │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │     │    │
│  │    │  │ monitoring  │ │trivy-system │ │ gatekeeper  │             │     │    │
│  │    │  │             │ │             │ │   -system   │             │     │    │
│  │    │  │ Grafana     │ │ Security    │ │ Policy      │             │     │    │
│  │    │  │ Prometheus  │ │ Scanner     │ │ Engine      │             │     │    │
│  │    │  └─────────────┘ └─────────────┘ └─────────────┘             │     │    │
│  │    │                                                               │     │    │
│  │    └──────────────────────────────────────────────────────────────┘     │    │
│  │                                                                          │    │
│  │    ┌──────────────────────────────────────────────────────────────┐     │    │
│  │    │                    USER NAMESPACES                            │     │    │
│  │    │                                                               │     │    │
│  │    │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │     │    │
│  │    │  │  dashboard  │ │  deployer   │ │  user-apps  │             │     │    │
│  │    │  │             │ │             │ │             │             │     │    │
│  │    │  │ SIAB UI     │ │ App Deploy  │ │ Custom      │             │     │    │
│  │    │  │             │ │ Service     │ │ Applications│             │     │    │
│  │    │  └─────────────┘ └─────────────┘ └─────────────┘             │     │    │
│  │    │                                                               │     │    │
│  │    └──────────────────────────────────────────────────────────────┘     │    │
│  │                                                                          │    │
│  │  Pod CIDR: 10.42.0.0/16                                                  │    │
│  │  Service CIDR: 10.43.0.0/16                                              │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## TLS Certificate Management

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       TLS CERTIFICATE ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     EXTERNAL TLS (HTTPS)                                 │    │
│  │                                                                          │    │
│  │  CERTIFICATE: siab-gateway-cert                                          │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                                                                    │  │    │
│  │  │  cert-manager (Issuer)                                             │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  Self-signed CA or ACME (Let's Encrypt)                    │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ▼                                                            │  │    │
│  │  │  Certificate Resource                                              │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  SANs:                                                     │  │    │
│  │  │       │  ├─ *.siab.local                                           │  │    │
│  │  │       │  ├─ siab.local                                             │  │    │
│  │  │       │  ├─ *.apps.siab.local                                      │  │    │
│  │  │       │  └─ *.admin.siab.local                                     │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ▼                                                            │  │    │
│  │  │  Kubernetes Secret (siab-gateway-cert)                             │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  tls.crt: [Certificate PEM]                                │  │    │
│  │  │       │  tls.key: [Private Key PEM]                                │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ▼                                                            │  │    │
│  │  │  Istio Gateway (credentialName: siab-gateway-cert)                 │  │    │
│  │  │                                                                    │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     INTERNAL mTLS (Service Mesh)                         │    │
│  │                                                                          │    │
│  │  CERTIFICATES: Automatically managed by Istio                            │    │
│  │                                                                          │    │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │    │
│  │  │                                                                    │  │    │
│  │  │  Istiod (Certificate Authority)                                    │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  Root CA Certificate                                       │  │    │
│  │  │       │  (cluster-scoped, long-lived)                              │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ▼                                                            │  │    │
│  │  │  Workload Certificates (per-pod)                                   │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  Identity: spiffe://cluster.local/ns/X/sa/Y                │  │    │
│  │  │       │  Validity: 24 hours                                        │  │    │
│  │  │       │  Rotation: Automatic (before expiry)                       │  │    │
│  │  │       │                                                            │  │    │
│  │  │       ▼                                                            │  │    │
│  │  │  Envoy Sidecar                                                     │  │    │
│  │  │       │                                                            │  │    │
│  │  │       │  Presents certificate to peers                             │  │    │
│  │  │       │  Validates peer certificates                               │  │    │
│  │  │       │  All traffic encrypted                                     │  │    │
│  │  │                                                                    │  │    │
│  │  └───────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Headers and Policies

### HTTPS Enforcement
All HTTP traffic is automatically redirected to HTTPS:
```yaml
servers:
- port:
    name: http
    number: 80
    protocol: HTTP
  tls:
    httpsRedirect: true    # Forces HTTPS
```

### TLS Configuration
- **Minimum Version**: TLS 1.2
- **Mode**: SIMPLE (server-side TLS)
- **Certificate Source**: Kubernetes Secret via cert-manager

---

## Operational Commands

### Verify mTLS Status
```bash
# Check mesh-wide mTLS mode
kubectl get peerauthentication -n istio-system

# Verify a specific service uses mTLS
istioctl x describe pod <pod-name> -n <namespace>

# Check certificate status
istioctl proxy-config secret <pod-name> -n <namespace>
```

### Check Gateway Configuration
```bash
# List all gateways
kubectl get gateway -A

# View gateway details
kubectl describe gateway admin-gateway -n istio-system

# Check VirtualServices routing
kubectl get virtualservice -A
```

### Verify Firewall Configuration
```bash
# List open ports
sudo firewall-cmd --list-all

# Check trusted zone
sudo firewall-cmd --zone=trusted --list-all

# Verify masquerading
sudo firewall-cmd --query-masquerade
```

---

## Related Documentation

- [Architecture Overview](./SIAB-Architecture-Overview.md)
- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Keycloak SSO Configuration](./SIAB-Keycloak-SSO.md)
- [Compliance & Audit](./SIAB-Compliance-Audit.md)
