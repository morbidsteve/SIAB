# External VM Access Guide

This guide explains how to access SIAB services from another VM (e.g., a VM on your laptop).

## Architecture Overview

SIAB uses a **dual-gateway architecture** with MetalLB LoadBalancer:

```
┌─────────────────────────────────────────────────────┐
│  External VM (your laptop)                          │
│  - Add /etc/hosts entries                           │
│  - Network must reach SIAB server L2                │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ HTTPS (443), HTTP (80)
                  │
┌─────────────────┴───────────────────────────────────┐
│  SIAB Host (Rocky Linux VM)                         │
│                                                      │
│  MetalLB LoadBalancer:                              │
│  ├─ Admin Gateway IP: X.X.X.240                     │
│  │  └─ keycloak.siab.local                          │
│  │  └─ minio.siab.local                             │
│  │  └─ grafana.siab.local                           │
│  │  └─ k8s-dashboard.siab.local                     │
│  │                                                   │
│  └─ User Gateway IP: X.X.X.242                      │
│     └─ siab.local / dashboard.siab.local            │
│     └─ catalog.siab.local                           │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

### Network Requirements

**CRITICAL:** Your external VM must be on the **same Layer 2 network** as the SIAB host.

MetalLB uses L2Advertisement (ARP-based), which means:
- ✅ Same subnet (e.g., both on 192.168.1.0/24)
- ✅ Same VLAN
- ✅ No router between VMs
- ❌ Different subnets (e.g., 192.168.1.0 vs 192.168.2.0) won't work
- ❌ VMs on different networks separated by a router won't work

**To check:** Ping the SIAB host from your laptop VM. If ping works, L2 connectivity is likely OK.

### Firewall Requirements

The SIAB host must allow these ports (automatically configured during install):
- **443/tcp** - HTTPS ingress
- **80/tcp** - HTTP (redirects to HTTPS)
- **6443/tcp** - Kubernetes API (if you want kubectl access)

## Step-by-Step Access Setup

### Step 1: Get Gateway IP Addresses

On the SIAB host, run:

```bash
sudo siab-info
```

This will show you:
```
Admin Gateway IP:  192.168.1.240 (administrative services)
User Gateway IP:   192.168.1.242 (user-facing applications)
```

Or get them manually:
```bash
# Admin gateway IP
kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# User gateway IP
kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Step 2: Add Hosts Entries on Your Laptop VM

#### On Linux/macOS

Edit `/etc/hosts`:
```bash
sudo nano /etc/hosts
```

Add these lines (replace IPs with your actual gateway IPs):
```
# SIAB Admin Plane
192.168.1.240 keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local

# SIAB User Plane
192.168.1.242 siab.local dashboard.siab.local catalog.siab.local
```

#### On Windows

Edit `C:\Windows\System32\drivers\etc\hosts` (as Administrator):
```
# SIAB Admin Plane
192.168.1.240 keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local

# SIAB User Plane
192.168.1.242 siab.local dashboard.siab.local catalog.siab.local
```

### Step 3: Access Services from Your Browser

Open your browser on the laptop VM and access:

#### User Services
- **SIAB Dashboard**: https://dashboard.siab.local or https://siab.local
- **Application Catalog**: https://catalog.siab.local

#### Admin Services
- **Keycloak (IAM)**: https://keycloak.siab.local
- **MinIO (Storage)**: https://minio.siab.local
- **Grafana (Monitoring)**: https://grafana.siab.local
- **Kubernetes Dashboard**: https://k8s-dashboard.siab.local
- **Longhorn (Storage)**: https://longhorn.siab.local

### Step 4: Accept Self-Signed Certificates

SIAB uses self-signed TLS certificates by default. You'll see browser warnings:
- **Chrome/Edge**: Click "Advanced" → "Proceed to ... (unsafe)"
- **Firefox**: Click "Advanced" → "Accept the Risk and Continue"
- **Safari**: Click "Show Details" → "visit this website"

**For production**, you should configure Let's Encrypt or your own CA certificates.

## Troubleshooting

### Issue: Cannot Reach Services

**Check L2 connectivity:**
```bash
# From your laptop VM, ping the gateway IPs
ping 192.168.1.240
ping 192.168.1.242

# From your laptop VM, test HTTPS connectivity
curl -k https://192.168.1.242
```

If ping fails:
- ❌ VMs are on different networks/subnets
- ❌ Firewall blocking ICMP
- ❌ MetalLB not working properly

**Verify MetalLB IP assignment:**
```bash
# On SIAB host
kubectl get svc -n istio-system
# Look for EXTERNAL-IP on istio-ingress-admin and istio-ingress-user
```

If EXTERNAL-IP shows `<pending>`:
```bash
# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb

# Check IP address pools
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Issue: DNS Not Resolving

**Verify /etc/hosts entries:**
```bash
# On your laptop VM
cat /etc/hosts | grep siab
```

**Test with direct IP access:**
```bash
# Try accessing via IP instead of hostname
curl -k -H "Host: dashboard.siab.local" https://192.168.1.242
```

If this works, the issue is with hostname resolution (check /etc/hosts).

### Issue: Connection Refused or Timeout

**Check firewall on SIAB host:**
```bash
# Rocky Linux (firewalld)
sudo firewall-cmd --list-all

# Should show ports: 80/tcp, 443/tcp, 15021/tcp

# Ubuntu (ufw)
sudo ufw status
```

**Verify Istio gateways are running:**
```bash
kubectl get pods -n istio-system | grep ingress
# Both istio-ingress-admin and istio-ingress-user should be Running
```

**Check gateway service status:**
```bash
kubectl get svc -n istio-system istio-ingress-admin
kubectl get svc -n istio-system istio-ingress-user
```

### Issue: 503 Service Unavailable

The gateway is reachable, but backend services aren't ready.

**Check if pods are running:**
```bash
kubectl get pods -n siab-system
kubectl get pods -n keycloak
kubectl get pods -n minio
kubectl get pods -n monitoring
```

**Check VirtualServices:**
```bash
kubectl get virtualservice -n istio-system
```

**Run diagnostics:**
```bash
sudo siab-diagnose
```

## Alternative Access Method: Port Forwarding

If MetalLB L2 doesn't work due to network constraints, use port-forward as a workaround:

```bash
# On SIAB host, forward the user gateway
kubectl port-forward -n istio-system svc/istio-ingress-user 8443:443 --address 0.0.0.0

# Then access from laptop VM using SIAB host IP
https://<siab-host-ip>:8443
```

This bypasses MetalLB but requires the port-forward to keep running.

## Network Architecture Details

### MetalLB Configuration

SIAB uses MetalLB in **L2 mode** with two IP address pools:

```yaml
Admin Pool:
  - Range: <network>.240-<network>.241
  - Services: Admin gateway

User Pool:
  - Range: <network>.242-<network>.243
  - Services: User gateway
```

The network prefix is auto-detected from the SIAB host's IP address during installation.

### Why Two Gateways?

The dual-gateway architecture separates:
- **Admin Gateway** (restricted): For platform administration (Keycloak, MinIO console, Grafana)
- **User Gateway** (public): For user-facing applications and catalog

This allows for:
- Different network policies
- Separate rate limiting
- Independent scaling
- Security segregation

## Credentials

After accessing the services, you'll need credentials. Run on SIAB host:

```bash
# View all credentials
sudo cat /etc/siab/credentials.env

# Or use siab-info for formatted output
sudo siab-info
```

Default credentials:
- **Grafana**: admin / (generated password)
- **Keycloak**: admin / (generated password)
- **MinIO**: admin / (generated password)
- **K8s Dashboard**: Use token from `kubectl get secret siab-admin-token -n kubernetes-dashboard`

## Production Considerations

For production deployments with external access:

1. **Use a proper DNS server** instead of /etc/hosts
2. **Configure Let's Encrypt** for valid TLS certificates
3. **Set up BGP mode** in MetalLB if crossing L2 boundaries
4. **Implement VPN** if accessing over untrusted networks
5. **Configure external authentication** via Keycloak OIDC
6. **Enable audit logging** for all admin access
7. **Use network policies** to restrict admin gateway access

## Advanced: Using BGP Instead of L2

If your VMs are on different subnets, use BGP mode:

```bash
# Edit MetalLB config to use BGP instead of L2Advertisement
kubectl edit configmap -n metallb-system metallb-config

# Add BGP peer configuration
# See: https://metallb.universe.tf/configuration/#bgp-configuration
```

This requires a BGP-capable router between your networks.

## Support

For issues:
1. Run: `sudo siab-diagnose`
2. Check logs: `kubectl logs -n istio-system -l app=istiod`
3. Review gateway status: `kubectl describe svc -n istio-system istio-ingress-admin`
4. Open an issue: https://github.com/morbidsteve/SIAB/issues
