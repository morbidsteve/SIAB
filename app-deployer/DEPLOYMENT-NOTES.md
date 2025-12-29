# SIAB App Deployer - Deployment Notes

## Latest Fixes (Commit: b681438)

All critical fixes for GitHub auto-deployment are included in the repository and will be automatically applied during SIAB installation.

### Fixed Issues

1. **VirtualService Port Routing**
   - **Issue:** VirtualService was routing to container port instead of service port
   - **Fix:** VirtualService now routes to service port 80, which forwards to container targetPort
   - **Location:** `app-deployer/backend/app-deployer-api.py:1977`
   - **Code:** `create_ingress_route(namespace, name, 80, hostname=None, gateway=gateway)`

2. **LinuxServer Container Authentication**
   - **Issue:** CUSTOM_USER/PASSWORD env vars caused Basic Auth conflicts with OAuth2 Proxy
   - **Fix:** Removed CUSTOM_USER and PASSWORD env vars for LinuxServer containers
   - **Location:** `app-deployer/backend/app-deployer-api.py:1945-1953`
   - **Result:** OAuth2 Proxy handles all authentication, no double-auth conflicts

3. **Resource Limits for GUI Apps**
   - **Fix:** LinuxServer GUI apps get 2Gi memory limit (vs 1Gi for regular apps)
   - **Location:** `app-deployer/backend/app-deployer-api.py:1036-1037`

## Deployment Architecture

```
User Request
    ↓
VirtualService (port 80) ← Routes to service port
    ↓
Service (port 80 → targetPort 3000) ← Forwards to container
    ↓
Container (listening on port 3000)
```

## How It Works

When you install or upgrade SIAB:

1. **Installation Script** (`scripts/modules/applications/siab-apps.sh`)
   - Creates ConfigMap `deployer-backend-code` from source files
   - ConfigMap contains the fixed backend code
   - Line 92-94: `kubectl create configmap deployer-backend-code --from-file=...`

2. **Deployment** (`app-deployer/deploy/deployer-deployment.yaml`)
   - Backend deployment mounts ConfigMap as `/app`
   - Line 189: `name: deployer-backend-code`
   - Pods run the latest code automatically

3. **GitHub Auto-Deploy**
   - Detects LinuxServer repos and uses pre-built images
   - Creates services with port 80 → targetPort (container port)
   - Creates VirtualServices routing to port 80
   - No Basic Auth for LinuxServer apps (OAuth2 only)

## Verification

To verify fixes are applied:

```bash
# Check VirtualService port routing
kubectl get virtualservice <app-name> -n istio-system -o yaml | grep "number:"
# Should show: number: 80

# Check service port mapping
kubectl get svc <app-name> -n default -o yaml | grep -A 3 "ports:"
# Should show: port: 80, targetPort: <container-port>

# Check backend code version
kubectl exec -n siab-deployer deployment/app-deployer-backend -- \
    grep "VirtualService should route to service port" /app/app-deployer-api.py
# Should return the comment line
```

## Upgrading Existing Deployments

If you have apps deployed before this fix:

```bash
# Fix VirtualService port
kubectl patch virtualservice <app-name> -n istio-system --type=json \
    -p='[{"op": "replace", "path": "/spec/http/0/route/0/destination/port/number", "value": 80}]'

# For LinuxServer apps with auth issues, redeploy:
kubectl delete deployment,svc,virtualservice <app-name> -n default
# Then redeploy via the deployer interface
```

## Common Deployment Patterns

### LinuxServer Apps
- **Image:** `lscr.io/linuxserver/<app-name>:latest`
- **Port:** Usually 3000 (web GUI)
- **Env Vars:** PUID=1000, PGID=1000, TZ=UTC (no CUSTOM_USER/PASSWORD)
- **Resources:** 2Gi memory, 2 CPU
- **Auth:** OAuth2 Proxy only (no Basic Auth)

### Standard Apps
- **Service:** port 80 → targetPort (app port)
- **VirtualService:** Routes to port 80
- **Resources:** 1Gi memory, 1 CPU
- **Auth:** OAuth2 Proxy (if using user gateway)

## Troubleshooting

### "Unable to handle this request"
**Cause:** VirtualService routing to wrong port
**Fix:** Patch VirtualService to use port 80

### "WebSocket disconnected"
**Cause:** OAuth2 Proxy blocking WebSocket upgrades
**Fix:** EnvoyFilter to bypass auth for specific apps (see wireshark-bypass-ext-authz)

### "RBAC: access denied"
**Cause:** Hardcoded AuthorizationPolicy blocking access
**Fix:** Remove app from deny list or delete hardcoded policies

## GitHub Repository Structure

```
app-deployer/
├── backend/
│   ├── app-deployer-api.py    ← Main backend with all fixes
│   └── requirements.txt
├── frontend/
│   └── index.html              ← Enhanced UI with tooltips
├── deploy/
│   └── deployer-deployment.yaml ← Deployment manifest
└── DEPLOYMENT-NOTES.md         ← This file
```

All fixes are in the `app-deployer/backend/app-deployer-api.py` file, which is automatically deployed via the ConfigMap during installation.
