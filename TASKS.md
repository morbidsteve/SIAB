# SIAB Task Tracker

This file tracks ongoing work across Claude Code sessions. Read this at session start.

## Current Session
**Last Updated:** 2025-12-22 00:35
**Status:** Installation verified - all services operational

---

## In Progress
<!-- Tasks currently being worked on -->

_None_

---

## Pending
<!-- Tasks queued but not started -->

- [ ] Fix Trivy scanner job (non-critical, scan job fails but doesn't affect functionality)
- [ ] Test uninstall with SSH-safe fixes

---

## Completed
<!-- Recently completed tasks (keep last 10-15) -->

- [x] Fix all manifest configs for reliable installs (2025-12-22)
  - **install.sh** - Set SIAB_REPO_DIR to source directory before loading config
  - **config.sh** - Made SIAB_REPO_DIR overridable via environment
  - **deployer-deployment.yaml** - Fixed VirtualService to route /api/* to backend
  - **keycloak.sh** - Added VirtualService for Keycloak (port 8080)
  - **istio.sh** - Fixed user-gateway to accept *.siab.local hosts
  - **istio.sh** - Fixed admin-gateway to use correct TLS cert `siab-gateway-cert`

- [x] Fix SSH disconnect during uninstall (2025-12-21)
  - **Root cause**: `rke2-killall.sh` was rewriting iptables and deleting network interfaces
  - **Fixed in**: `scripts/modules/core/rke2.sh` - new SSH-safe `uninstall_rke2()` function
  - **Fixed in**: `scripts/lib/kubernetes/cleanup.sh` - removed dangerous `fuser -km`
  - **Fixed in**: `scripts/uninstall.sh` - added `ensure_ssh_connectivity()` function
  - Key changes:
    - Detect primary network interface before cleanup
    - Add SSH iptables rules before any network changes
    - Don't use rke2-killall.sh (too aggressive with iptables)
    - Re-ensure SSH connectivity after each critical step
    - Preserve established connections in iptables

- [x] Full end-to-end install testing (2025-12-21)
  - [x] Created safe-cleanup.sh for SSH-safe cleanup
  - [x] Fixed Keycloak port-forward bug (port 80 -> 8080)
  - [x] Fixed missing Keycloak VirtualService
  - [x] Fixed user-gateway hosts (added *.siab.local)
  - [x] Fixed deployer-frontend-html ConfigMap (placeholder -> real content)
  - [x] Fixed deployer-backend-code ConfigMap (placeholder -> real code)
  - [x] Patched Prometheus to work without Longhorn storage
  - All endpoints verified working via HTTPS

---

## Test Results (2025-12-21)

### Pod Status
All pods Running/Completed except:
- `trivy-system/scan-vulnerabilityreport-*` - Error (non-critical scan job)

### Admin Gateway (10.10.30.240)
| Service | Status | URL |
|---------|--------|-----|
| Keycloak | ✓ OK | https://keycloak.siab.local |
| Grafana | ✓ OK | https://grafana.siab.local |
| MinIO | ✓ OK | https://minio.siab.local |
| K8s Dashboard | ✓ OK | https://k8s-dashboard.siab.local |

### User Gateway (10.10.30.242)
| Service | Status | URL |
|---------|--------|-----|
| SIAB Dashboard | ✓ OK | https://dashboard.siab.local |
| Deployer | ✓ OK | https://deployer.siab.local |

---

## Bugs Fixed This Session

1. **Keycloak port-forward** - `scripts/configure-keycloak.sh:43` was using port 80, should be 8080
2. **Missing Keycloak VirtualService** - No VirtualService was created for Keycloak routing
3. **User Gateway hosts** - Was configured for `*.apps.siab.local` but VirtualServices use `*.siab.local`
4. **Deployer ConfigMaps** - Both frontend and backend ConfigMaps had placeholder content

---

## Blocked / Needs Attention
<!-- Tasks that are stuck or need human input -->

_None_

---

## Notes for Next Session
<!-- Context, gotchas, or reminders for continuity -->

- **All services verified working** (2025-12-22):
  - Admin Gateway (10.10.30.240): Keycloak, Grafana, MinIO, K8s Dashboard
  - User Gateway (10.10.30.242): SIAB Dashboard, Deployer (frontend + API)
- **Uninstall is now SSH-safe** - the full uninstall script preserves SSH connectivity
- **Install script fixed** - SIAB_REPO_DIR now correctly points to source directory
- Longhorn storage is skipped in current config (Prometheus uses emptyDir)
- Credentials at `/etc/siab/credentials.env`
- The `safe-cleanup.sh` script is still useful for quick K8s-only cleanup without removing RKE2

---

## Quick Reference

**Check system state:**
```bash
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get svc -n istio-system
```

**Test endpoints:**
```bash
curl -sk --resolve keycloak.siab.local:443:10.10.30.240 https://keycloak.siab.local/realms/master
curl -sk --resolve dashboard.siab.local:443:10.10.30.242 https://dashboard.siab.local/
```

**Credentials:** `/etc/siab/credentials.env`
**Logs:** `/var/log/siab/install-latest.log`
