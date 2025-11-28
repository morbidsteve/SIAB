# SIAB Getting Started Guide

This guide walks you through accessing and configuring your SIAB platform after installation.

## Quick Reference

| Service | URL | Default Username |
|---------|-----|------------------|
| Keycloak | https://keycloak.siab.local | admin |
| MinIO | https://minio.siab.local | admin |
| Grafana | https://grafana.siab.local | admin |
| Longhorn | https://longhorn.siab.local | (no auth) |
| K8s Dashboard | https://k8s-dashboard.siab.local | (token) |

**View all credentials:** `sudo cat /etc/siab/credentials.env`

**Quick status:** `siab-status` or `siab-info`

---

## Step 1: Configure Client Access

Before accessing SIAB services from your workstation, add DNS entries.

### Get Your Gateway IPs

On the SIAB server, run:
```bash
siab-info
```

This shows your Admin Gateway IP (e.g., `10.10.30.240`) and User Gateway IP (e.g., `10.10.30.242`).

### Add to /etc/hosts

On your **client machine** (laptop/workstation), add:

**Linux/Mac:** Edit `/etc/hosts`
```bash
sudo nano /etc/hosts
```

**Windows:** Edit `C:\Windows\System32\drivers\etc\hosts` (as Administrator)

Add these lines (replace IPs with your actual gateway IPs):
```
# SIAB Admin Plane
10.10.30.240 keycloak.siab.local minio.siab.local grafana.siab.local longhorn.siab.local k8s-dashboard.siab.local

# SIAB User Plane
10.10.30.242 siab.local dashboard.siab.local catalog.siab.local deployer.siab.local
```

### Accept Self-Signed Certificates

SIAB uses self-signed certificates by default. When you first visit each service:
1. You'll see a security warning
2. Click "Advanced" or "Show Details"
3. Click "Proceed" or "Accept the Risk"

For production, see [HTTPS Configuration](./HTTPS-CONFIGURATION.md) to set up Let's Encrypt certificates.

---

## Step 2: Get Your Credentials

### View All Credentials

On the SIAB server:
```bash
sudo cat /etc/siab/credentials.env
```

Output:
```
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=<random-password>

MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=<random-password>

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<random-password>
```

### Kubernetes Dashboard Token

For the K8s Dashboard, you need a token:
```bash
kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

Or simply run `siab-info` which displays the token.

---

## Step 3: Initial Service Configuration

### Keycloak (Identity & Access Management)

Keycloak manages users, authentication, and SSO for your applications.

**Access:** https://keycloak.siab.local

**Login:** Use credentials from `/etc/siab/credentials.env`

#### First-Time Setup

1. **Log in** to the Keycloak admin console
2. **Create a new realm** for your applications:
   - Click "Create Realm" (dropdown next to "master")
   - Name it (e.g., "siab" or "mycompany")
   - Click "Create"

3. **Create users:**
   - Go to Users > Add User
   - Fill in username, email, etc.
   - Click "Create"
   - Go to Credentials tab > Set Password
   - Turn off "Temporary" for permanent password

4. **Create a client** (for each app that needs auth):
   - Go to Clients > Create Client
   - Client ID: your-app-name
   - Client Protocol: openid-connect
   - Root URL: https://your-app.siab.local
   - Configure redirect URIs

#### Integrate Applications with Keycloak

For apps to use Keycloak authentication:
```yaml
# Example: OIDC configuration
issuer: https://keycloak.siab.local/realms/siab
client_id: your-app
client_secret: <from-keycloak-client-credentials>
```

---

### MinIO (S3-Compatible Object Storage)

MinIO provides S3-compatible storage for your applications.

**Access:** https://minio.siab.local

**Login:** Use credentials from `/etc/siab/credentials.env`

#### First-Time Setup

1. **Log in** to the MinIO Console

2. **Create buckets:**
   - Click "Buckets" > "Create Bucket"
   - Name your bucket (e.g., "app-data", "backups")
   - Configure versioning/retention as needed

3. **Create access keys** for applications:
   - Go to Access Keys > Create Access Key
   - Save the Access Key and Secret Key
   - Use these in your application's S3 configuration

4. **Set bucket policies** (optional):
   - Click on a bucket > Access Rules
   - Add policies for read/write access

#### Using MinIO from Applications

```bash
# AWS CLI configuration
aws configure
# Access Key: <from MinIO>
# Secret Key: <from MinIO>
# Region: us-east-1 (or any)

# Use with endpoint
aws --endpoint-url https://minio.siab.local s3 ls
aws --endpoint-url https://minio.siab.local s3 cp file.txt s3://my-bucket/
```

**S3 SDK Configuration:**
```python
import boto3

s3 = boto3.client('s3',
    endpoint_url='https://minio.siab.local',
    aws_access_key_id='YOUR_ACCESS_KEY',
    aws_secret_access_key='YOUR_SECRET_KEY',
    verify=False  # For self-signed certs
)
```

---

### Grafana (Monitoring & Dashboards)

Grafana provides visualization for your cluster metrics.

**Access:** https://grafana.siab.local

**Login:** Use credentials from `/etc/siab/credentials.env`

#### Pre-Configured Dashboards

SIAB includes several pre-configured dashboards:
- **Kubernetes / Compute Resources / Cluster** - Overall cluster health
- **Kubernetes / Compute Resources / Namespace** - Per-namespace metrics
- **Node Exporter** - Host-level metrics (CPU, memory, disk)
- **Istio Service Mesh** - Service mesh traffic and latency

To find dashboards: Click the hamburger menu > Dashboards > Browse

#### Adding Custom Dashboards

1. Click + (plus icon) > Import
2. Enter a dashboard ID from [Grafana.com](https://grafana.com/grafana/dashboards/)
3. Or paste JSON from a dashboard export

#### Setting Up Alerts

1. Go to Alerting > Alert Rules
2. Create new rule with PromQL query
3. Configure notification channels (email, Slack, etc.)

---

### Longhorn (Distributed Block Storage)

Longhorn provides persistent storage for your Kubernetes workloads.

**Access:** https://longhorn.siab.local

**No authentication required** (access via trusted network only)

#### Viewing Storage

- **Dashboard:** Overview of storage capacity and health
- **Volume:** List of persistent volumes and their status
- **Node:** Storage capacity per node

#### Creating Storage Classes

SIAB creates a default `longhorn` storage class. For additional classes:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fsType: ext4
```

#### Backup Configuration

1. Go to Settings > Backup Target
2. Configure S3 backup (can use your MinIO!):
   - Backup Target: `s3://backups@us-east-1/`
   - Backup Target Credential Secret: Create secret with MinIO creds

---

### Kubernetes Dashboard

Web UI for managing Kubernetes resources.

**Access:** https://k8s-dashboard.siab.local

**Login:** Use the token from `siab-info`

#### Getting the Token

```bash
kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

#### Features

- View and manage pods, deployments, services
- View logs and exec into containers
- Create resources from YAML

---

## Step 4: Deploy Your First Application

### Using the App Catalog

SIAB includes a catalog of pre-configured applications.

**Access:** https://catalog.siab.local

Available applications:
- PostgreSQL
- Redis
- NGINX
- And more...

### Using the Application Deployer

**Access:** https://deployer.siab.local

Deploy custom applications with:
- Git repository URL
- Docker image
- Helm chart

### Manual Deployment

```bash
# Create a simple deployment
kubectl create deployment nginx --image=nginx

# Expose it
kubectl expose deployment nginx --port=80 --type=ClusterIP

# Create Istio VirtualService for external access
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: nginx
  namespace: istio-system
spec:
  hosts:
    - "nginx.siab.local"
  gateways:
    - user-gateway
  http:
    - route:
        - destination:
            host: nginx.default.svc.cluster.local
            port:
              number: 80
EOF
```

Don't forget to add `nginx.siab.local` to your `/etc/hosts`!

---

## Step 5: Security Best Practices

### Change Default Passwords

After initial setup, change all default passwords:

1. **Keycloak:** Admin Console > Users > admin > Credentials
2. **MinIO:** Console > Identity > Users > admin
3. **Grafana:** Profile > Change Password

### Enable MFA

For Keycloak users:
1. Realm Settings > Authentication > Required Actions
2. Enable "Configure OTP"
3. Users will be prompted to set up 2FA on next login

### Review Network Policies

SIAB includes default network policies. Review and customize:
```bash
kubectl get networkpolicies -A
```

### Monitor Security Alerts

- **Trivy:** Scans container images for vulnerabilities
  ```bash
  kubectl get vulnerabilityreports -A
  ```

- **OPA Gatekeeper:** Enforces security policies
  ```bash
  kubectl get constraints
  ```

---

## Common Tasks

### View Cluster Status
```bash
siab-status
```

### View Access Information
```bash
siab-info
```

### Check All Pods
```bash
kubectl get pods -A
```

### Interactive Cluster Management
```bash
k9s
```

### View Logs
```bash
# Specific pod
kubectl logs -n <namespace> <pod-name>

# Istio ingress
kubectl logs -n istio-system -l istio=ingress-admin --tail=100
```

### Restart a Deployment
```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

---

## Troubleshooting

### Can't Access Services

1. **Check pods are running:**
   ```bash
   kubectl get pods -A | grep -v Running
   ```

2. **Check Istio gateways:**
   ```bash
   kubectl get gateway -n istio-system
   kubectl get virtualservice -n istio-system
   ```

3. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-all
   ```

4. **Run diagnostics:**
   ```bash
   ./siab-diagnose.sh
   ```

### Service Returns 503/502

Usually indicates the backend pod isn't healthy:
```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Storage Issues

Check Longhorn:
```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get pods -n longhorn-system
```

Ensure iscsid is running:
```bash
sudo systemctl status iscsid
sudo systemctl restart iscsid
```

---

## Next Steps

- [Application Deployment Guide](./APPLICATION-DEPLOYMENT-GUIDE.md) - Deploy custom applications
- [Security Guide](./SECURITY-GUIDE.md) - Harden your deployment
- [Advanced Configuration](./ADVANCED-CONFIGURATION.md) - Customize SIAB
- [Troubleshooting Guide](./TROUBLESHOOTING.md) - Solve common issues

---

## Quick Commands Reference

| Command | Description |
|---------|-------------|
| `siab-status` | Platform health overview |
| `siab-info` | URLs, credentials, access info |
| `siab-diagnose` | Run diagnostic checks |
| `k9s` | Interactive cluster UI |
| `kubectl get pods -A` | List all pods |
| `kubectl logs -f <pod>` | Follow pod logs |
| `helm list -A` | List Helm releases |
