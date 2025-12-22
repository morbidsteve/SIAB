# SIAB Task Tracker

This file tracks ongoing work across Claude Code sessions. Read this at session start.

## Current Session
**Last Updated:** 2025-12-22 01:50
**Status:** App Deployer improvements completed - git repo scanning, docker-compose, auth flow

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
- [ ] Add option to bypass OAuth2 authentication for specific deployed apps

---

## Completed
<!-- Recently completed tasks (keep last 10-15) -->

- [x] App Deployer improvements (2025-12-22)
  - **Git repo scanning**: Uses GitHub API to find Dockerfiles/compose files in ANY directory
  - **Docker-compose handling**: Proper multi-service parsing with VirtualServices for all web services
  - **Dockerfile FROM extraction**: Can deploy from simple Dockerfiles (nginx, redis, etc.) without building
  - **VirtualService routing**: All deployed apps use user-gateway with OAuth2 authentication
  - **Fixed**: Linuxserver repo detection with pre-built images
  - **Fixed**: Frontend uses backend detection for better type recognition

- [x] Repository cleanup and v0.0.10 release (2025-12-22)
  - Deleted deprecated root install.sh/uninstall.sh
  - Removed unused directories: lib/, maas/, operator/, gui/, catalog/
  - Removed old dashboard files: dashboard/src/, dashboard/backend/
  - Updated README.md with correct script paths and service URLs
  - Updated CLAUDE.md with current directory structure and gateway info

- [x] Fix dashboard/deployer connectivity (2025-12-22)
  - Updated user-gateway to accept `*.siab.local` in addition to `*.apps.siab.local`
  - Added missing `/etc/hosts` entries for dashboard.siab.local
  - Fixed network.sh to place dashboard.siab.local on user gateway

- [x] Fix all manifest configs for reliable installs (2025-12-22)
  - Fixed install.sh SIAB_REPO_DIR handling
  - Fixed VirtualService routing for deployer /api/* to backend
  - Fixed istio.sh gateway configurations

- [x] Fix SSH disconnect during uninstall (2025-12-21)
  - SSH-safe uninstall function in rke2.sh
  - Removed dangerous fuser -km from cleanup.sh
  - Added SSH connectivity checks

---

## App Deployer Capabilities

### Supported Deployment Methods:
1. **Git Repository URL** - Scans entire repo for Dockerfiles/compose files
2. **Docker Compose** - Converts to K8s Deployments/Services with VirtualServices
3. **Dockerfile** - Uses FROM image directly (for common images like nginx, redis, etc.)
4. **Kubernetes Manifest** - Direct kubectl apply
5. **Quick Deploy** - Direct image deployment

### Integration Features:
- **HTTPS Ingress**: VirtualService through user-gateway
- **OAuth2 Authentication**: Automatic via EnvoyFilter on user-gateway
- **Istio Service Mesh**: mTLS, traffic management
- **Persistent Storage**: Longhorn PVCs (optional)
- **MinIO Object Storage**: S3 bucket + credentials (optional)
- **Keycloak SSO**: OIDC client creation for supported apps (optional)

### Authentication Flow:
1. User accesses `https://myapp.siab.local`
2. Request hits user-gateway (10.10.30.242)
3. EnvoyFilter sends to OAuth2 Proxy for auth check
4. If no valid cookie, redirects to Keycloak login
5. After auth, request proceeds to app

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
| App Deployer | OK | https://deployer.siab.local |
| nginx-test | OK | https://nginx-test.siab.local (requires auth) |

### App Deployer Tests:
- [x] Git repo scanning: Found 74 files in docker/awesome-compose
- [x] Linuxserver repo: Auto-detected pre-built image
- [x] Simple Dockerfile: nginx:alpine deployed successfully
- [x] VirtualService: Uses user-gateway correctly
- [x] OAuth2: Returns 403 for unauthenticated requests

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v0.0.11 | 2025-12-22 | App deployer improvements - git scanning, compose, dockerfile support |
| v0.0.10 | 2025-12-22 | Repository cleanup and documentation updates |
| v0.0.9 | 2025-12-22 | Fix dashboard/deployer DNS entries for user gateway |
| v0.0.7 | 2025-12-21 | Modular installer with SSH-safe uninstall |

---

## Notes for Next Session
<!-- Context, gotchas, or reminders for continuity -->

- **All services verified working** (2025-12-22)
- **App Deployer fully functional** with git scanning, compose, dockerfile support
- **Authentication required** for all apps on user-gateway (by design)
- To access deployed apps, user must first authenticate via Keycloak
- **Test app deployed**: nginx-test.siab.local (demonstrates full flow)
- Credentials at `/etc/siab/credentials.env`

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
# Admin gateway (no auth required)
curl -sk --resolve keycloak.siab.local:443:10.10.30.240 https://keycloak.siab.local/realms/master

# User gateway (requires auth - expect 403)
curl -sk --resolve deployer.siab.local:443:10.10.30.242 https://deployer.siab.local/
```

**Credentials:** `/etc/siab/credentials.env`
**Logs:** `/var/log/siab/install-latest.log`
