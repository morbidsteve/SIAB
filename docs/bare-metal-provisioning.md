# Bare Metal Provisioning Guide

This guide explains how to deploy SIAB on unprovisioned bare metal hardware.

## Overview

SIAB supports multiple methods for bare metal provisioning:

1. **MAAS (Metal as a Service)** - Enterprise solution for large deployments
2. **PXE Boot** - Lightweight solution for small deployments
3. **Cloud-Init** - For cloud providers or MAAS

## Prerequisites

### For MAAS Provisioning
- Ubuntu 22.04 LTS server for MAAS controller
- Network with DHCP control
- IPMI/BMC access to target servers (recommended)
- Minimum 4GB RAM, 40GB disk for MAAS server

### For PXE Provisioning
- Rocky Linux or RHEL 8/9 server for PXE server
- Network with DHCP control
- HTTP server for serving boot images
- TFTP server for PXE boot files

### Target Hardware
- x86_64 architecture
- Minimum 4 CPU cores
- Minimum 16GB RAM
- Minimum 30GB disk
- PXE boot capable network card
- IPMI/BMC interface (optional but recommended)

## Method 1: MAAS Provisioning (Recommended for Enterprise)

MAAS provides comprehensive bare metal lifecycle management.

### Step 1: Install MAAS Server

On an Ubuntu 22.04 server, run the SIAB MAAS setup script:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./provisioning/maas/setup-maas.sh
```

This script will:
- Install MAAS 3.4
- Configure PostgreSQL database
- Set up DHCP and DNS
- Download Rocky Linux boot images
- Configure PXE boot
- Create SIAB deployment scripts

### Step 2: Access MAAS UI

After installation, access the MAAS web interface:

```
http://<maas-server-ip>:5240/MAAS
Username: admin
Password: admin (change this!)
```

### Step 3: Add Hardware

**Option A: Automatic Discovery (with IPMI)**

1. Run hardware discovery:
```bash
cd SIAB/provisioning/scripts
./discover-hardware.sh --subnet 192.168.1.0/24 --ipmi --output inventory.json
```

2. Import to MAAS:
```bash
./import-to-maas.sh
```

**Option B: Manual Addition**

1. Power on machines with PXE boot enabled
2. MAAS will automatically discover them
3. Or manually add via MAAS UI: Hardware → Add hardware

### Step 4: Commission Hardware

Commission the discovered machines:

```bash
# List machines
maas admin machines read | jq -r '.[] | "\(.system_id) \(.hostname)"'

# Commission all
maas admin machines commission all

# Or commission specific machine
maas admin machine commission <system-id>
```

### Step 5: Deploy SIAB Cluster

**Single Node:**
```bash
maas admin machine deploy <system-id> osystem=rocky distro_series=9.3
```

**Multi-Node Cluster:**
```bash
cd SIAB/provisioning/scripts
./provision-cluster.sh --method maas --nodes 3 --cluster production
```

### Step 6: Monitor Deployment

```bash
# Watch deployment status
watch -n 5 'maas admin machines read | jq -r ".[] | \"\(.hostname) - \(.status_name)\""'

# View events
maas admin events query level=INFO

# SSH to deployed node (after deployment completes)
ssh root@<node-ip>

# Monitor SIAB installation
journalctl -u siab-autoinstall -f
```

## Method 2: PXE Boot Provisioning

For smaller deployments or when MAAS is overkill.

### Step 1: Set Up PXE Server

On a Rocky Linux server:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./provisioning/pxe/setup-pxe-server.sh
```

When prompted, provide:
- Network subnet (e.g., 192.168.1.0)
- Netmask (e.g., 255.255.255.0)
- Gateway IP
- DHCP range start and end
- DNS server

### Step 2: Verify Services

Check that all services are running:

```bash
# DHCP
systemctl status dhcpd

# TFTP
systemctl status xinetd  # RHEL/Rocky
# or
systemctl status tftpd-hpa  # Debian/Ubuntu

# HTTP
systemctl status httpd  # RHEL/Rocky
# or
systemctl status apache2  # Debian/Ubuntu
```

### Step 3: Boot Target Machines

1. Configure target machines to PXE boot:
   - Enter BIOS/UEFI settings
   - Set boot order: Network → Disk
   - Enable network boot

2. Power on the machines

3. They will:
   - Get IP from DHCP
   - PXE boot from TFTP
   - Download Rocky Linux installer
   - Run kickstart for automated installation
   - Auto-install SIAB on first boot

### Step 4: Monitor Installation

On the PXE server:

```bash
# Watch DHCP leases
tail -f /var/lib/dhcp/dhcpd.leases

# Watch TFTP requests
journalctl -u xinetd -f

# Watch HTTP access
tail -f /var/log/httpd/access_log

# List provisioned systems
./provisioning/scripts/inventory-hardware.sh
```

### Step 5: Access Deployed Nodes

After installation completes (~30 minutes):

```bash
# SSH to node (password: set in kickstart)
ssh root@<node-ip>

# Check SIAB installation progress
journalctl -u siab-autoinstall -f

# View SIAB status
systemctl status siab-autoinstall
```

## Method 3: Cloud-Init Provisioning

For cloud providers or MAAS with custom user-data.

### Using Cloud-Init Template

1. Use the provided cloud-init configuration:
```bash
cat provisioning/cloud-init/siab-user-data.yaml
```

2. Customize for your environment:
   - Add SSH keys
   - Set hostname pattern
   - Configure cluster settings
   - Add custom packages

3. Deploy to cloud provider or MAAS:

**For MAAS:**
```bash
maas admin machine deploy <system-id> \
    osystem=rocky \
    distro_series=9.3 \
    user_data="$(cat provisioning/cloud-init/siab-user-data.yaml)"
```

**For Cloud Providers:**
- AWS: Use user-data in EC2 launch configuration
- Azure: Use custom-data in VM creation
- GCP: Use user-data in instance metadata

## Hardware Discovery

### Scan Network for Hardware

```bash
cd SIAB/provisioning/scripts
./discover-hardware.sh --subnet 192.168.1.0/24 --output hardware.json
```

### Scan for PXE-Capable Devices

```bash
./discover-hardware.sh --subnet 192.168.1.0/24 --pxe
```

### Scan for IPMI Interfaces

```bash
./discover-hardware.sh --subnet 192.168.1.0/24 --ipmi --output ipmi-hosts.json
```

The output includes:
- IP addresses
- MAC addresses
- Hostnames
- Open ports
- IPMI availability
- PXE capability

## Kickstart Customization

### Edit Kickstart File

The kickstart file is located at `provisioning/kickstart/siab-rocky9.ks`.

Common customizations:

**Change Root Password:**
```bash
# Generate encrypted password
python3 -c 'import crypt; print(crypt.crypt("mypassword", crypt.mksalt(crypt.METHOD_SHA512)))'

# Update kickstart
rootpw --iscrypted <encrypted-password>
```

**Custom Partitioning:**
```
# Example: Separate /var/lib/rancher partition
logvol /var/lib/rancher --fstype=xfs --name=lv_rancher --vgname=vg_system --size=200000 --grow
```

**Additional Packages:**
```
%packages
@^minimal-environment
@core
# Add your packages here
vim
htop
%end
```

**Custom Post-Install Script:**
```
%post
# Add your custom commands here
echo "Custom configuration" >> /etc/motd
%end
```

## Multi-Node Cluster Deployment

### Deploy Production Cluster

```bash
# Set cluster configuration
export CLUSTER_NAME="production"
export CLUSTER_SIZE=5
export MAAS_URL="http://maas.example.com:5240/MAAS"
export MAAS_API_KEY="<your-api-key>"

# Deploy cluster
./provisioning/scripts/provision-cluster.sh \
    --method maas \
    --nodes 5 \
    --cluster production
```

### High Availability Setup

For HA, deploy at least 3 master nodes:

1. First node (master):
```bash
export SIAB_SINGLE_NODE="false"
./install.sh
```

2. Get cluster token:
```bash
cat /var/lib/rancher/rke2/server/node-token
```

3. Additional masters:
```bash
export SIAB_JOIN_TOKEN="<token-from-step-2>"
export SIAB_JOIN_ADDRESS="<first-master-ip>:9345"
./install.sh
```

## Troubleshooting

### PXE Boot Issues

**Problem: Machine doesn't PXE boot**

Check:
```bash
# DHCP is running
systemctl status dhcpd

# TFTP is running
systemctl status xinetd

# Firewall allows DHCP and TFTP
firewall-cmd --list-all

# PXE files exist
ls -la /var/lib/tftpboot/pxelinux.0
```

**Problem: TFTP timeout**

```bash
# Check TFTP logs
journalctl -u xinetd -n 50

# Test TFTP manually
tftp <pxe-server-ip>
> get pxelinux.0
```

### MAAS Issues

**Problem: Machine stuck in "Commissioning"**

```bash
# Check machine logs
maas admin machine get-curtin-config <system-id>

# View events
maas admin events query system_id=<system-id>

# Abort and retry
maas admin machine abort <system-id>
maas admin machine commission <system-id>
```

**Problem: Can't access IPMI**

```bash
# Test IPMI manually
ipmitool -I lanplus -H <ipmi-ip> -U ADMIN -P ADMIN chassis status

# Common default credentials to try:
# Dell: root/calvin
# HP: Administrator/random (check sticker)
# Supermicro: ADMIN/ADMIN
```

### Installation Issues

**Problem: SIAB auto-install fails**

```bash
# Check service status
systemctl status siab-autoinstall

# View logs
journalctl -u siab-autoinstall -n 100

# Check installation log
cat /var/log/siab/install.log

# Run installer manually
/opt/siab/install.sh
```

**Problem: Network connectivity issues**

```bash
# Check network configuration
ip addr show
ip route show

# Test DNS
dig google.com

# Test internet connectivity
curl -I https://google.com
```

## Best Practices

### Security

1. **Change Default Passwords**
   - MAAS admin password
   - IPMI/BMC passwords
   - Root password in kickstart

2. **Use SSH Keys**
   - Add your public key to cloud-init or kickstart
   - Disable password authentication

3. **Network Isolation**
   - Use dedicated provisioning network
   - VLAN separation for management

4. **Secure IPMI**
   - Change default credentials immediately
   - Use dedicated IPMI network
   - Enable IPMI encryption

### Performance

1. **Local Mirror**
   - Mirror Rocky Linux repositories locally
   - Reduces installation time
   - Reduces bandwidth usage

2. **Parallel Deployment**
   - Deploy multiple nodes simultaneously
   - MAAS handles this automatically

3. **SSD for MAAS**
   - Use SSD for MAAS database
   - Improves responsiveness

### Maintenance

1. **Regular Updates**
   - Keep MAAS updated
   - Update boot images regularly

2. **Monitor Deployments**
   - Set up alerts for failed deployments
   - Regular hardware health checks

3. **Documentation**
   - Document your network layout
   - Keep inventory of hardware
   - Document custom configurations

## Integration with SIAB

### Post-Deployment Hooks

Create custom post-deployment actions:

```bash
# Edit /etc/siab/post-provision-hook.sh on deployed nodes
cat > /etc/siab/post-provision-hook.sh <<'EOF'
#!/bin/bash
# Custom post-provision actions

# Example: Join existing cluster
export SIAB_JOIN_TOKEN="your-token"
export SIAB_JOIN_ADDRESS="master:9345"

# Example: Custom domain
export SIAB_DOMAIN="mycompany.com"

# Example: Enable specific features
export SIAB_ENABLE_MONITORING="true"
export SIAB_ENABLE_BACKUP="true"

EOF
```

### Automated Testing

Test deployments automatically:

```bash
#!/bin/bash
# Test script to verify SIAB deployment

# Wait for SIAB to be ready
timeout 3600 bash -c 'until systemctl is-active siab-autoinstall; do sleep 10; done'

# Verify Kubernetes
kubectl get nodes
kubectl get pods -A

# Run smoke tests
kubectl apply -f examples/simple-app.yaml
kubectl wait --for=condition=Ready pod -l app=simple-web-app --timeout=300s

# Cleanup
kubectl delete -f examples/simple-app.yaml
```

## Reference

### Quick Commands

```bash
# MAAS
maas login admin http://localhost:5240/MAAS/api/2.0/ <api-key>
maas admin machines read
maas admin machine commission <system-id>
maas admin machine deploy <system-id> osystem=rocky distro_series=9.3

# Hardware Discovery
./provisioning/scripts/discover-hardware.sh --subnet 192.168.1.0/24

# Cluster Deployment
./provisioning/scripts/provision-cluster.sh --method maas --nodes 3

# PXE Server
./provisioning/pxe/setup-pxe-server.sh

# Inventory
./provisioning/scripts/inventory-hardware.sh
```

### File Locations

```
/var/lib/tftpboot/              - PXE boot files
/var/www/html/siab-provision/   - HTTP served files
/etc/dhcp/dhcpd.conf           - DHCP configuration
/etc/siab/                     - SIAB configuration
/opt/siab/install.sh           - SIAB installer
/var/log/siab/                 - SIAB logs
```

### Network Ports

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| DHCP    | 67   | UDP      | IP allocation |
| TFTP    | 69   | UDP      | PXE boot files |
| HTTP    | 80   | TCP      | Installation files |
| MAAS UI | 5240 | TCP      | Web interface |
| IPMI    | 623  | UDP      | Hardware management |

## Next Steps

After successful deployment:

1. [Verify Installation](./getting-started.md#verify-installation)
2. [Deploy Applications](./deployment.md)
3. [Configure Security](./security.md)
4. [Set Up Monitoring](./monitoring.md)
