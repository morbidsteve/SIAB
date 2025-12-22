# SIAB - Secure Infrastructure as a Box

## Session Startup

**AT THE START OF EVERY SESSION:**
1. Read `TASKS.md` to see current progress and pending work
2. Update the "Last Updated" timestamp when starting work
3. Update task statuses as you complete them
4. Add notes for the next session before ending

## Claude Code Instructions

**CRITICAL: Autonomous Operation Mode**
- DO NOT ask for permission to run commands - execute them directly
- DO NOT ask for confirmation before testing - test automatically
- DO NOT wait for human validation - validate everything yourself
- Complete ALL tasks fully and autonomously
- When building/deploying, run comprehensive tests yourself
- When testing services, use curl/wget to verify endpoints work
- Fix any issues found during testing without asking

## Project Overview

SIAB is a one-command secure Kubernetes platform installer that deploys:
- RKE2 Kubernetes cluster
- Istio service mesh with dual-gateway architecture (admin + user planes)
- Keycloak for identity management
- OAuth2 Proxy for SSO enforcement
- MinIO for S3-compatible object storage
- Longhorn for block storage
- Prometheus + Grafana for monitoring
- OPA Gatekeeper for policy enforcement
- Trivy for security scanning
- Kubernetes Dashboard
- SIAB Dashboard and Application Deployer

## Directory Structure

```
/home/fscyber/soc/SIAB/
├── scripts/
│   ├── install.sh          # Main installer orchestrator
│   ├── uninstall.sh        # Main uninstaller orchestrator
│   ├── lib/                # Shared libraries
│   │   ├── common/         # colors, config, logging, os, utils
│   │   ├── kubernetes/     # kubectl, helm, cleanup helpers
│   │   ├── progress/       # Status dashboard
│   │   └── checks/         # Preflight checks
│   └── modules/            # Component modules
│       ├── core/           # rke2, helm, k9s
│       ├── infrastructure/ # cert-manager, metallb, longhorn, istio, firewall
│       ├── security/       # keycloak, oauth2-proxy, gatekeeper, trivy
│       ├── applications/   # minio, monitoring, dashboard, siab-apps
│       └── config/         # credentials, network, sso
├── manifests/              # Kubernetes manifests
├── crds/                   # Custom Resource Definitions
├── dashboard/              # SIAB landing page frontend
├── app-deployer/           # Application deployment interface
├── docs/                   # Documentation
├── examples/               # Example manifests
├── provisioning/           # Bare metal provisioning (PXE, MAAS, cloud-init)
├── siab-diagnose.sh        # Diagnostic tool
├── siab-status.sh          # Status checker
└── siab-info.sh            # Access information display
```

## Key Configuration

### Paths
- SIAB_DIR: `/opt/siab`
- SIAB_CONFIG_DIR: `/etc/siab`
- SIAB_LOG_DIR: `/var/log/siab`
- SIAB_BIN_DIR: `/usr/local/bin`

### Domain
- Default: `siab.local`
- Override: Set `SIAB_DOMAIN` environment variable

### Component Versions (pinned)
- RKE2: v1.28.4+rke2r1
- Helm: v3.13.3
- Istio: 1.20.1
- Keycloak: 23.0.3
- Longhorn: 1.5.3
- Prometheus Stack: 56.6.2

### Network
- Admin Gateway IP Pool: x.x.x.240-241
- User Gateway IP Pool: x.x.x.242-243
- Pod CIDR: 10.42.0.0/16
- Service CIDR: 10.43.0.0/16

## Testing Commands

### Verify Kubernetes
```bash
kubectl get nodes
kubectl get pods -A
```

### Verify Services
```bash
# Check all namespaces
kubectl get pods -A | grep -v Running | grep -v Completed

# Check Istio gateways
kubectl get svc -n istio-system

# Get gateway IPs
kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Test HTTP Access
```bash
# Get gateway IPs
ADMIN_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
USER_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test admin endpoints (use -k for self-signed certs)
curl -sk --resolve keycloak.siab.local:443:$ADMIN_IP https://keycloak.siab.local/
curl -sk --resolve grafana.siab.local:443:$ADMIN_IP https://grafana.siab.local/
curl -sk --resolve minio.siab.local:443:$ADMIN_IP https://minio.siab.local/

# Test user endpoints
curl -sk --resolve dashboard.siab.local:443:$USER_IP https://dashboard.siab.local/
curl -sk --resolve deployer.siab.local:443:$USER_IP https://deployer.siab.local/
```

### Check Credentials
```bash
cat /etc/siab/credentials.env
```

### Check Logs
```bash
tail -f /var/log/siab/install-latest.log
```

## Common Issues & Fixes

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n <namespace>
# Usually storage class or resource issues
```

### Namespace stuck in Terminating
```bash
# Force delete with finalizer removal
kubectl get namespace <ns> -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

### Istio mTLS issues
```bash
# Check if PeerAuthentication is set correctly
kubectl get peerauthentication -A

# For non-sidecar services, use PERMISSIVE or DISABLE mode
```

### RKE2 not starting
```bash
journalctl -u rke2-server -f
systemctl status rke2-server
```

## Script Usage

### Install
```bash
sudo ./scripts/install.sh
```

### Uninstall
```bash
sudo SIAB_UNINSTALL_CONFIRM=yes ./scripts/uninstall.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| SIAB_DOMAIN | siab.local | Base domain for services |
| SIAB_SKIP_MONITORING | false | Skip Prometheus/Grafana |
| SIAB_SKIP_STORAGE | false | Skip MinIO |
| SIAB_SKIP_LONGHORN | false | Skip Longhorn |
| SIAB_MINIO_SIZE | 20Gi | MinIO storage size |
| SIAB_SINGLE_NODE | true | Single-node deployment |

## Service URLs (after installation)

| Service | URL | Gateway |
|---------|-----|---------|
| Keycloak | https://keycloak.siab.local | Admin |
| Grafana | https://grafana.siab.local | Admin |
| MinIO Console | https://minio.siab.local | Admin |
| K8s Dashboard | https://k8s-dashboard.siab.local | Admin |
| SIAB Dashboard | https://dashboard.siab.local | User |
| App Deployer | https://deployer.siab.local | User |
| Auth (OAuth2) | https://auth.siab.local | User |

## When Making Changes

1. **Modifying a component**: Edit the specific module file in `scripts/modules/`
2. **Adding a new component**: Create new module file, add source line to orchestrator
3. **Changing shared logic**: Edit files in `scripts/lib/`
4. **Testing changes**: Run full install, verify all pods Running, test HTTP endpoints

## Validation Checklist

After installation, verify:
- [ ] All pods in Running or Completed state
- [ ] Both Istio gateways have LoadBalancer IPs
- [ ] Keycloak responds at /realms/master
- [ ] Grafana login page loads
- [ ] MinIO console loads
- [ ] SIAB Dashboard shows all services
- [ ] Credentials file exists at /etc/siab/credentials.env
