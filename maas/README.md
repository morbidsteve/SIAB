# SIAB MAAS Deployment Guide

Complete guide for deploying SIAB using MAAS (Metal as a Service) with Proxmox VMs and Rocky Linux.

## Overview

This guide enables **fully automated deployment**:
1. MAAS creates VM in Proxmox
2. Rocky Linux installs automatically
3. SIAB installs and configures automatically
4. Complete secure Kubernetes platform ready in ~20 minutes

## Architecture

```
┌─────────────────┐
│  MAAS Server    │
│  (Ubuntu)       │
└────────┬────────┘
         │
         │ Provisions
         ▼
┌─────────────────┐
│  Proxmox Host   │
│                 │
│  ┌───────────┐  │
│  │  Rocky    │  │ ← Cloud-init configures
│  │  Linux VM │  │ ← SIAB auto-installs
│  └───────────┘  │
└─────────────────┘
```

## Prerequisites

### MAAS Server
- Ubuntu 20.04/22.04 LTS
- Min 2 CPU, 4GB RAM, 20GB disk
- Network access to Proxmox

### Proxmox Host
- Proxmox VE 7.x or 8.x
- Min 8 CPU, 32GB RAM, 100GB disk
- Network connectivity

### Target VM Specs (for SIAB)
- **Minimum**: 4 CPU, 16GB RAM, 30GB disk
- **Recommended**: 8 CPU, 32GB RAM, 100GB disk

## Step 1: Install MAAS

### On Ubuntu Server

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install MAAS
sudo snap install --channel=3.3 maas

# Initialize MAAS
sudo maas init region+rack --database-uri maas-test-db:///

# Create admin user
sudo maas createadmin --username admin --email admin@example.com

# Get API key
sudo maas apikey --username admin
```

Access MAAS UI: `http://<maas-server>:5240/MAAS`

## Step 2: Configure MAAS for Proxmox

### Add Proxmox as a VM Host

1. In MAAS UI, go to **KVM** → **Add KVM host**
2. Select **Virsh (Proxmox)**
3. Enter Proxmox details:
   - **Address**: `qemu+ssh://root@<proxmox-ip>/system`
   - **Password**: Your Proxmox root password

Or via CLI:

```bash
# Get your MAAS API key
MAAS_API_KEY="<your-api-key>"
MAAS_URL="http://<maas-ip>:5240/MAAS"

# Add Proxmox as VM host
maas admin vm-hosts create \
  type=virsh \
  power_address="qemu+ssh://root@<proxmox-ip>/system" \
  power_pass="<proxmox-root-password>"
```

### Configure SSH Access

On MAAS server:

```bash
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Copy to Proxmox
ssh-copy-id root@<proxmox-ip>

# Test connection
ssh root@<proxmox-ip> "virsh list"
```

## Step 3: Import Rocky Linux Image

```bash
# Download Rocky Linux cloud image
wget https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2

# Convert to raw format (for better performance)
qemu-img convert -f qcow2 -O raw \
  Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 \
  rocky-9-cloud.img

# Import to MAAS
maas admin boot-resources create \
  name='rocky/9' \
  architecture='amd64/generic' \
  filetype='disk-image.gz' \
  content@=rocky-9-cloud.img.gz

# Or use MAAS UI: Images → Custom Images → Upload
```

## Step 4: Upload SIAB Cloud-Init Config

### Via MAAS UI

1. Go to **Machines** → Select machine → **Configuration**
2. Add **Cloud-init user-data**
3. Paste contents of `cloud-init-rocky-siab.yaml`

### Via CLI

```bash
# Upload cloud-init config
maas admin machine set-user-data <machine-id> \
  user-data@=/path/to/cloud-init-rocky-siab.yaml
```

## Step 5: Deploy SIAB

### Option A: Via MAAS UI

1. **Compose VM**:
   - Go to KVM → Select Proxmox host → **Compose**
   - Name: `siab-01`
   - Cores: 8
   - RAM: 32 GB
   - Storage: 100 GB
   - OS: Rocky Linux 9

2. **Commission** the machine (MAAS tests hardware)

3. **Deploy**:
   - Select Rocky Linux 9
   - Cloud-init: Use uploaded config
   - Click **Deploy**

### Option B: Automated via CLI

```bash
# Compose VM
VM_ID=$(maas admin vm-host compose <vm-host-id> \
  cores=8 \
  memory=32768 \
  storage=100G \
  hostname=siab-01 | jq -r '.system_id')

# Set cloud-init
maas admin machine set-user-data $VM_ID \
  user-data@=cloud-init-rocky-siab.yaml

# Deploy
maas admin machine deploy $VM_ID \
  distro_series=rocky9 \
  user_data@=cloud-init-rocky-siab.yaml
```

## Step 6: Monitor Installation

### Check MAAS Status

```bash
# Watch deployment status
watch maas admin machine read $VM_ID | jq -r '.status_name'
```

Status progression:
1. `Deploying` - OS installing
2. `Deployed` - OS installed, cloud-init running
3. `Ready` - Fully deployed

### SSH to Machine

Once deployed:

```bash
# Get IP address
IP=$(maas admin machine read $VM_ID | jq -r '.ip_addresses[0]')

# SSH in
ssh siab@$IP

# Monitor SIAB installation
tail -f /var/log/siab-install.log
```

### Check SIAB Installation Progress

```bash
ssh siab@$IP "tail -f /var/log/siab/install.log"
```

## Step 7: Access SIAB Services

### Get Gateway IPs

```bash
ssh siab@$IP "kubectl get svc -n istio-system | grep ingress"
```

### Update /etc/hosts

Add to your local machine:

```
<admin-gateway-ip>  keycloak.siab.local minio.siab.local grafana.siab.local longhorn.siab.local k8s-dashboard.siab.local
<user-gateway-ip>   dashboard.siab.local catalog.siab.local
```

### Access Services

- Keycloak: https://keycloak.siab.local
- MinIO: https://minio.siab.local
- Grafana: https://grafana.siab.local
- Dashboard: https://dashboard.siab.local

## Automation Script

Use the provided `deploy-siab-maas.sh` script for complete automation:

```bash
./deploy-siab-maas.sh --proxmox-host <proxmox-ip> --maas-url http://<maas-ip>:5240/MAAS
```

## Troubleshooting

### Cloud-Init Not Running

```bash
# Check cloud-init status
ssh siab@$IP "cloud-init status"

# View cloud-init logs
ssh siab@$IP "cat /var/log/cloud-init-output.log"
```

### SIAB Installation Failed

```bash
# Check installation log
ssh siab@$IP "tail -100 /var/log/siab-install.log"

# Check for errors
ssh siab@$IP "grep -i error /var/log/siab/install.log"
```

### Network Issues

```bash
# Verify firewall
ssh siab@$IP "sudo firewall-cmd --list-all"

# Check Kubernetes
ssh siab@$IP "sudo kubectl get nodes"
ssh siab@$IP "sudo kubectl get pods -A"
```

### Re-run SIAB Installation

```bash
ssh siab@$IP
sudo /opt/SIAB/uninstall.sh
sudo /opt/SIAB/install.sh
```

## Production Considerations

1. **Change default password** in cloud-init config
2. **Add your SSH keys** to cloud-init config
3. **Use proper domain names** instead of .local
4. **Configure TLS certificates** (Let's Encrypt)
5. **Set up backup** for persistent data
6. **Enable monitoring** and alerting

## Files

- `cloud-init-rocky-siab.yaml` - Cloud-init configuration
- `deploy-siab-maas.sh` - Automated deployment script
- `maas-config.yaml` - MAAS configuration template

## Next Steps

After deployment:
1. Review SIAB documentation: `/opt/SIAB/README.md`
2. Deploy your first application
3. Configure backup strategy
4. Set up monitoring dashboards

## Support

For issues:
- SIAB: https://github.com/morbidsteve/SIAB/issues
- MAAS: https://maas.io/docs

## License

MIT License - See SIAB repository for details
