# SIAB Provisioning GUI

A cross-platform graphical interface for deploying SIAB on bare metal hardware.

## Overview

The SIAB Provisioning GUI provides an easy-to-use interface for:
- Setting up PXE or MAAS provisioning servers
- Discovering hardware on your network
- Deploying multi-node Kubernetes clusters
- Monitoring cluster status

## Installation

### Requirements

- Python 3.6 or higher
- tkinter (usually included with Python)

### Platform-Specific Setup

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install python3-tk
```

**Linux (Fedora/RHEL/Rocky):**
```bash
sudo dnf install python3-tkinter
```

**macOS:**
tkinter is included with Python from python.org

**Windows:**
tkinter is included with Python installer from python.org

## Launching the GUI

### Double-Click Launch

**Linux/macOS:**
1. Navigate to the `gui/` directory
2. Double-click `SIAB-Provisioner.sh`

**Windows:**
1. Navigate to the `gui/` directory
2. Double-click `SIAB-Provisioner.bat`

### Command Line Launch

```bash
cd SIAB/gui
python3 siab-provisioner-gui.py
```

Or using the launcher:
```bash
cd SIAB/gui
./SIAB-Provisioner.sh  # Linux/macOS
# or
SIAB-Provisioner.bat   # Windows
```

## Using the GUI

### Setup Tab

Configure your provisioning method:

1. **Choose Provisioning Method**
   - **PXE Boot Server**: Lightweight, good for small deployments
   - **MAAS**: Enterprise solution, best for large deployments

2. **Network Configuration**
   - Enter your subnet (e.g., 192.168.1.0/24)
   - Automatically detected by default

3. **MAAS Configuration** (if using MAAS)
   - Enter MAAS URL (e.g., http://maas-server:5240/MAAS)
   - Enter API key (get from MAAS admin)

4. **Setup Provisioning Server**
   - Click "Setup Provisioning Server"
   - Monitor progress in the output log
   - Wait for completion

### Discover Hardware Tab

Scan your network for bare metal servers:

1. **Configure Scan Options**
   - ☑ Scan for IPMI interfaces
   - ☑ Filter PXE-capable devices

2. **Run Network Scan**
   - Click "Scan Network"
   - Wait for discovery to complete
   - View results in the table

3. **Review Discovered Hardware**
   - IP Address
   - MAC Address
   - Hostname
   - IPMI Available (Yes/No)
   - PXE Ready (Yes/No)

4. **Export Results**
   - Click "Export to JSON"
   - Save inventory for later use

### Deploy Cluster Tab

Deploy a multi-node Kubernetes cluster:

1. **Configure Cluster**
   - Enter cluster name (e.g., "production")
   - Set number of nodes (1-100)

2. **Deploy Cluster**
   - Click "Deploy Cluster"
   - Monitor deployment progress in log
   - Wait for completion (~30-60 minutes)

3. **Monitor Progress**
   - Real-time logs show deployment status
   - Errors and warnings are highlighted
   - Success message when complete

### Monitor Tab

Check cluster status:

1. **Refresh Status**
   - Click "Refresh Status"
   - View cluster nodes
   - See all pods
   - Check SIAB applications

2. **Review Information**
   - Node status and versions
   - Pod health and resources
   - Application deployments

## Features

### Automated Subnet Detection

The GUI automatically detects your local subnet, but you can override it if needed.

### Real-Time Logs

All operations show real-time output, making it easy to troubleshoot issues.

### Parallel Operations

The GUI runs commands in background threads, keeping the interface responsive.

### Export Capabilities

Hardware inventory can be exported to JSON for automation or record-keeping.

## Workflow Examples

### Small Deployment (PXE)

1. **Setup Tab**
   - Select "PXE Boot Server"
   - Click "Setup Provisioning Server"
   - Wait for setup to complete

2. **Discover Tab**
   - Click "Scan Network"
   - Verify target machines appear
   - Note PXE-capable systems

3. **Deploy Tab**
   - Enter cluster name
   - Set nodes to 3
   - Click "Deploy Cluster"

4. **Monitor Tab**
   - Click "Refresh Status"
   - Verify nodes joined
   - Check pod health

### Large Deployment (MAAS)

1. **Setup Tab**
   - Select "MAAS"
   - Enter MAAS URL and API key
   - Click "Setup Provisioning Server"

2. **Discover Tab**
   - Enable IPMI scanning
   - Click "Scan Network"
   - Export hardware inventory

3. **Deploy Tab**
   - Enter cluster name
   - Set nodes to 10+
   - Click "Deploy Cluster"

4. **Monitor Tab**
   - Periodically refresh
   - Track deployment progress
   - Verify all nodes online

## Troubleshooting

### GUI Won't Start

**Problem**: "Python not found" or "tkinter not found"

**Solution**:
```bash
# Linux
sudo apt-get install python3 python3-tk

# macOS
brew install python-tk

# Windows
Reinstall Python from python.org, ensure "tcl/tk" is selected
```

### Permission Denied

**Problem**: Scripts require sudo but GUI doesn't have permissions

**Solution**:
Run the GUI with sudo (Linux/macOS):
```bash
sudo python3 siab-provisioner-gui.py
```

Or configure passwordless sudo for specific scripts.

### Network Scan Finds No Devices

**Problem**: Hardware discovery returns empty

**Solution**:
1. Verify subnet is correct
2. Ensure machines are powered on
3. Check network connectivity
4. Try manual nmap scan:
   ```bash
   nmap -sn 192.168.1.0/24
   ```

### Deployment Fails

**Problem**: Cluster deployment errors

**Solution**:
1. Check logs in the Deploy tab
2. Verify provisioning server is running:
   ```bash
   systemctl status dhcpd
   systemctl status xinetd  # or tftpd-hpa
   ```
3. Ensure target machines can PXE boot
4. Check MAAS UI for errors (if using MAAS)

## Advanced Usage

### Custom Scripts

The GUI calls scripts from `provisioning/scripts/`. You can modify these scripts and the GUI will use your changes.

### Environment Variables

Set these before launching the GUI:

```bash
export SIAB_DOMAIN="mycompany.com"
export MAAS_URL="http://maas.example.com:5240/MAAS"
python3 siab-provisioner-gui.py
```

### Logging

All operations are logged to:
- GUI console (visible in tabs)
- System logs (for backend scripts)

To save GUI logs:
1. Select text in log area
2. Right-click → Copy
3. Paste to a file

## Security Considerations

### Running as Root

Some operations require root privileges. The GUI will prompt for sudo when needed.

### Network Scanning

Hardware discovery performs network scanning. Ensure you have permission to scan your network.

### Credentials

MAAS API keys are displayed in the GUI. Don't share screenshots of the Setup tab.

## Integration

### With PXE Server

The GUI sets up:
- DHCP server
- TFTP server
- HTTP server for boot images
- Kickstart configurations

### With MAAS

The GUI configures:
- MAAS API access
- Image imports
- Machine commissioning
- Deployment automation

### With SIAB

After cluster deployment:
- SIAB installer runs automatically
- Platform components deploy
- Applications become available
- Catalog can be accessed

## Tips

1. **Save Hardware Inventory**: Export discovered hardware to JSON for future reference

2. **Monitor During Deployment**: Keep the Monitor tab open during deployment to catch issues early

3. **Check Prerequisites**: Ensure target machines meet SIAB requirements (4 CPU, 16GB RAM, 30GB disk)

4. **Use MAAS for Scale**: For 10+ nodes, use MAAS instead of PXE

5. **Test with One Node**: Deploy a single-node cluster first to verify everything works

## Next Steps

After successful deployment:

1. Access the SIAB dashboard:
   ```
   https://dashboard.siab.local
   ```

2. Deploy applications from the catalog:
   ```
   https://catalog.siab.local
   ```

3. Configure Keycloak for user management:
   ```
   https://keycloak.siab.local
   ```

See the [Getting Started Guide](./getting-started.md) for next steps.
