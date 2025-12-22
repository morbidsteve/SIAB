# SIAB Task Tracker

This file tracks ongoing work across Claude Code sessions. Read this at session start.

## Current Session
**Last Updated:** 2025-12-22 01:20
**Status:** Repository cleanup and v0.0.9 release completed

---

## In Progress
<!-- Tasks currently being worked on -->

_None_

---

## Pending
<!-- Tasks queued but not started -->

- [ ] Fix Trivy scanner job (non-critical, scan job fails but doesn't affect functionality)
- [ ] Test uninstall with SSH-safe fixes on fresh system
- [ ] Consider updating pinned component versions to latest stable releases

---

## Completed
<!-- Recently completed tasks (keep last 10-15) -->

- [x] Repository cleanup and v0.0.9 release (2025-12-22)
  - Deleted deprecated root install.sh/uninstall.sh
  - Removed unused directories: lib/, maas/, operator/, gui/, catalog/
  - Removed old dashboard files: dashboard/src/, dashboard/backend/
  - Removed archived directories: docs/archived/, scripts/archived/
  - Removed redundant scripts at root level
  - Updated README.md with correct script paths and service URLs
  - Updated CLAUDE.md with current directory structure and gateway info
  - Fixed network.sh to place dashboard.siab.local on user gateway

- [x] Fix dashboard/deployer connectivity (2025-12-22)
  - **Root cause**: user-gateway only accepted `*.apps.siab.local`, not `*.siab.local`
  - **Fixed**: Updated user-gateway to accept both patterns
  - **Fixed**: Added missing `/etc/hosts` entries for dashboard.siab.local
  - All services verified working via HTTPS

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

---

## Test Results (2025-12-22)

### Pod Status
All pods Running/Completed except:
- `trivy-system/scan-vulnerabilityreport-*` - Error (non-critical scan job)

### Admin Gateway (10.10.30.240)
| Service | Status | URL |
|---------|--------|-----|
| Keycloak | OK | https://keycloak.siab.local |
| Grafana | OK | https://grafana.siab.local |
| MinIO | OK | https://minio.siab.local |
| K8s Dashboard | OK | https://k8s-dashboard.siab.local |

### User Gateway (10.10.30.242)
| Service | Status | URL |
|---------|--------|-----|
| SIAB Dashboard | OK | https://dashboard.siab.local |
| Deployer | OK | https://deployer.siab.local |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v0.0.9 | 2025-12-22 | Fix dashboard/deployer DNS entries for user gateway |
| v0.0.7 | 2025-12-21 | Modular installer with SSH-safe uninstall |

---

## Notes for Next Session
<!-- Context, gotchas, or reminders for continuity -->

- **All services verified working** (2025-12-22)
- **Repository cleaned up** - removed all deprecated/unused files
- **Uninstall is SSH-safe** - preserves network connectivity
- **Install script fixed** - SIAB_REPO_DIR correctly points to source directory
- Longhorn storage is skipped in current config (Prometheus uses emptyDir)
- Credentials at `/etc/siab/credentials.env`
- The `safe-cleanup.sh` script is useful for quick K8s-only cleanup without removing RKE2

---

## Quick Reference

**Install:**
```bash
sudo ./scripts/install.sh
```

**Uninstall:**
```bash
sudo SIAB_UNINSTALL_CONFIRM=yes ./scripts/uninstall.sh
```

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
