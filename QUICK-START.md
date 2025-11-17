# SIAB Quick Start Guide

Get SIAB running in 10 minutes! This guide shows the **fastest path** based on what you have.

## I Have...

### ✅ A Linux Machine Already (Rocky/Ubuntu/Xubuntu)

**Fastest Method:** Direct installation (5 minutes)

```bash
# SSH to your Linux machine (Rocky, Ubuntu, or Xubuntu)
ssh user@your-linux-machine

# Run one command
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash

# Wait ~30 minutes for installation
# Access at: https://dashboard.siab.local
```

**Supported OS:** Rocky Linux 8.x/9.x, Ubuntu 20.04+, Xubuntu 20.04+

**Works from:** Windows, macOS, or Linux workstation

---

### ✅ Blank Servers / Bare Metal

**Fastest Method:** GUI Provisioner (10 minutes to setup)

**Step 1: On Your Laptop (Any OS)**
```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB/gui

# Windows:
SIAB-Provisioner.bat

# macOS/Linux:
./SIAB-Provisioner.sh
```

**Step 2: In the GUI**
1. Click "Setup" tab
2. Choose "PXE Boot Server"
3. Click "Setup Provisioning Server"
4. Click "Discover Hardware" tab
5. Click "Scan Network"
6. Click "Deploy Cluster" tab
7. Set nodes, click "Deploy"

**Total Time:** ~30-60 minutes (mostly automated)

**Works from:** Windows, macOS, or Linux laptop + one Linux server for PXE

---

### ✅ Nothing Yet (Want to Try First)

**Fastest Method:** VM Installation (15 minutes)

**Step 1: Create VM**
- Download an ISO:
  - Rocky Linux 9: https://rockylinux.org
  - Ubuntu 22.04 LTS: https://ubuntu.com/download/server
  - Xubuntu 22.04 LTS: https://xubuntu.org/download
- Create VM: 4 CPU, 16GB RAM, 100GB disk
- Install Linux (minimal/server installation)

**Step 2: Install SIAB**
```bash
# In the VM
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

**Step 3: Access from Your Browser**
```bash
# Get the NodePort
kubectl get svc -n istio-system istio-ingress

# Open browser to: https://<vm-ip>:<nodeport>
```

**Works from:** Windows, macOS, or Linux with VirtualBox/VMware

---

### ✅ Cloud Account (AWS/Azure/GCP)

**Fastest Method:** Cloud Instance (5 minutes)

**Step 1: Launch Instance**
- OS: Rocky Linux 9
- Size: 4 vCPU, 16GB RAM, 100GB disk
- Security Group: Allow 22, 80, 443, 6443
- Public IP: Yes

**Step 2: Install SIAB**
```bash
# SSH to instance
ssh rocky@<instance-ip>

# Install
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

**Step 3: Access**
```
https://<instance-ip>
```

**Works from:** Any OS with SSH client

---

## After Installation

### 1. Access the Platform

```bash
# Default credentials
cat /etc/siab/credentials.env

# Access points
https://dashboard.siab.local   # Main dashboard
https://keycloak.siab.local    # IAM
https://minio.siab.local       # Storage
https://catalog.siab.local     # App catalog
```

### 2. Deploy Your First App

**Option A: Using Web Catalog**
1. Open https://catalog.siab.local
2. Click on "PostgreSQL" or "Redis"
3. Click "Deploy"
4. Done!

**Option B: Using kubectl**
```bash
# Create a simple app
cat <<EOF | kubectl apply -f -
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: my-app
spec:
  image: nginx:1.25-alpine
  replicas: 3
  port: 80
  ingress:
    enabled: true
    hostname: myapp.siab.local
    tls: true
EOF

# Check status
kubectl get siabapplications
```

### 3. Add Users

```bash
# Access Keycloak
https://keycloak.siab.local

# Login with admin credentials from /etc/siab/credentials.env
# Create realm, users, roles
```

## Common Issues

### "I don't have a supported Linux OS"

**Solution 1:** Create a VM
- Download VirtualBox (free)
- Download Rocky Linux 9, Ubuntu 22.04, or Xubuntu 22.04 ISO
- Create VM: 4 CPU, 16GB RAM, 100GB disk
- Install, then run SIAB installer

**Solution 2:** Use cloud
- Launch Rocky Linux 9 or Ubuntu 22.04 instance on AWS/Azure/GCP
- SSH in, run installer

### "I have Ubuntu/Xubuntu"

Great! SIAB now supports Ubuntu and Xubuntu directly:
```bash
# Just run the installer on your Ubuntu/Xubuntu machine
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

**Supported versions:** Ubuntu 20.04+, Xubuntu 20.04+

### "I have Debian"

SIAB doesn't support Debian directly yet. Options:
1. Create an Ubuntu VM on your Debian machine
2. Use a cloud instance with Rocky Linux or Ubuntu
3. If you have bare metal, use our provisioning to install Rocky Linux or Ubuntu

### "I'm on Windows/macOS"

Perfect! You can:
1. Use our GUI provisioner (runs on Windows/Mac)
2. Create a VM with Rocky Linux
3. Use a cloud instance
4. Provision bare metal servers

See: [Where to Start Guide](./docs/where-to-start.md)

### "Installation failed"

Check logs:
```bash
cat /var/log/siab/install.log
journalctl -u rke2-server
```

Common fixes:
- Ensure 16GB RAM minimum
- Check internet connectivity
- Disable swap: `swapoff -a`
- Check firewall isn't blocking ports

### "Can't access dashboard"

```bash
# Check if RKE2 is running
systemctl status rke2-server

# Check pods
kubectl get pods -A

# Get NodePort
kubectl get svc -n istio-system istio-ingress

# Access via: https://<ip>:<nodeport>
```

## What OS Do I Need?

| Component | OS Required |
|-----------|-------------|
| **Your Laptop/Workstation** | Windows, macOS, or Linux |
| **SIAB Installation** | Rocky Linux 8.x/9.x, Ubuntu 20.04+, or Xubuntu 20.04+ |
| **PXE Provisioning Server** | Rocky Linux or Ubuntu |
| **MAAS Provisioning Server** | Ubuntu 22.04 |
| **GUI Provisioner** | Runs on Windows/macOS/Linux |
| **Application Catalog** | Access from any OS browser |

**Bottom line:** You can **control** SIAB from any OS, and it **runs on** Rocky Linux, Ubuntu, or Xubuntu.

## Next Steps

- [Full Documentation](./docs/getting-started.md)
- [Where to Start (OS Guide)](./docs/where-to-start.md)
- [GUI Provisioner Guide](./docs/gui-provisioner.md)
- [Application Catalog](./catalog/README.md)
- [Security Guide](./docs/security.md)

## Get Help

- Check logs: `/var/log/siab/install.log`
- Review docs: `./docs/`
- GitHub Issues: https://github.com/morbidsteve/SIAB/issues

## That's It!

Pick your scenario above and follow the steps. You'll have a production-ready Kubernetes platform running in under an hour!
