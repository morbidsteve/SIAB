# Where to Start - System Requirements and Setup

This guide explains **what you need** and **where to run** SIAB tools based on your operating system.

## Quick Answer

**Can I start from my Windows/Mac/Linux laptop?**

| Tool | Windows | macOS | Linux |
|------|---------|-------|-------|
| GUI Provisioner | ✅ Yes | ✅ Yes | ✅ Yes |
| Application Catalog (browse) | ✅ Yes | ✅ Yes | ✅ Yes |
| Direct Installation | ❌ No* | ❌ No* | ✅ Yes** |

*You need Rocky Linux, Ubuntu, or Xubuntu as the target system, but you can control provisioning from any OS.
**Linux direct installation works on Rocky Linux, Ubuntu 20.04+, and Xubuntu 20.04+

## Understanding the Components

### 1. Your Workstation (Control Machine)
**This is where YOU work from**

- Your laptop or desktop
- Can be Windows, macOS, or Linux
- Used to:
  - Run the GUI Provisioner
  - Browse the Application Catalog
  - Access the SIAB dashboard after installation

### 2. Provisioning Server (Optional)
**A Linux server that provisions other machines**

- Needed for bare metal deployments only
- Must be Linux (Rocky/RHEL/Ubuntu)
- Can be:
  - A VM on your laptop
  - A dedicated server
  - A cloud instance

### 3. Target Machines
**Where SIAB actually runs**

- Must run one of:
  - Rocky Linux 8.x or 9.x
  - Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
  - Xubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Can be:
  - Physical bare metal servers
  - VMs
  - Cloud instances

## Deployment Scenarios

### Scenario 1: I Have a Linux Machine Already

**✅ Start From: Any OS (Windows, macOS, Linux)**

**What You Need:**
- Your workstation (any OS)
- One or more Linux machines running Rocky Linux, Ubuntu, or Xubuntu (physical or VM)
- SSH access to the Linux machines

**Steps:**

```bash
# 1. On YOUR workstation, clone the repo
git clone https://github.com/morbidsteve/SIAB.git

# 2. SSH to your Linux machine
ssh user@linux-machine

# 3. On the Linux machine, run installer
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash

# 4. From your workstation's browser, access the platform
open https://dashboard.siab.local
```

**Requirements:**
- ✅ Works from: **Windows, macOS, Linux**
- Target: Rocky Linux 8.x/9.x, Ubuntu 20.04+, or Xubuntu 20.04+ with 4 CPU, 16GB RAM, 100GB disk

---

### Scenario 2: I Have Blank Hardware (Bare Metal)

**✅ Start From: Any OS (Windows, macOS, Linux) + Linux Provisioning Server**

**What You Need:**
- Your workstation (Windows, macOS, or Linux)
- One Linux machine for provisioning server (Rocky Linux or Ubuntu)
- Blank bare metal servers on the same network

#### Option A: Using GUI from Your Workstation

**Steps:**

```bash
# 1. On YOUR workstation (Windows/Mac/Linux), clone SIAB
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB/gui

# Windows:
SIAB-Provisioner.bat

# macOS/Linux:
./SIAB-Provisioner.sh

# 2. The GUI will help you:
#    - Setup a provisioning server (you'll need a Linux VM/server)
#    - Discover hardware
#    - Deploy cluster
```

**Requirements:**
- ✅ Your workstation: **Windows, macOS, or Linux**
- ✅ Provisioning server: **Rocky Linux or Ubuntu** (can be a VM)
- ✅ Target machines: Blank servers with PXE boot

#### Option B: Manual Setup on Linux Server

**Steps:**

```bash
# 1. On a Rocky Linux or Ubuntu server (provisioning server)
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB

# For PXE (works on Rocky Linux or Ubuntu):
sudo ./provisioning/pxe/setup-pxe-server.sh

# For MAAS (Ubuntu only):
sudo ./provisioning/maas/setup-maas.sh

# 2. Power on your blank servers (they auto-install via PXE)

# 3. Monitor from any browser
open http://provisioning-server:5240/MAAS  # MAAS UI
open https://catalog.siab.local             # After installation
```

**Requirements:**
- ✅ Provisioning server: **Rocky Linux 8/9 or Ubuntu 22.04**
- ✅ Control from browser: **Any OS**
- ✅ Target machines: Blank servers with PXE boot

---

### Scenario 3: I Want to Try in a VM First

**✅ Start From: Any OS (Windows, macOS, Linux)**

**What You Need:**
- Your workstation (any OS)
- VirtualBox, VMware, or similar
- Rocky Linux 9 ISO

**Steps:**

```bash
# 1. Download Rocky Linux 9 ISO
https://rockylinux.org/download

# 2. Create VM with:
#    - 4 CPU cores
#    - 16GB RAM
#    - 100GB disk
#    - Network: Bridged

# 3. Install Rocky Linux 9 (minimal)

# 4. In the VM, run SIAB installer
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash

# 5. From your workstation's browser
open https://<vm-ip>:30443  # Find NodePort from kubectl get svc
```

**Requirements:**
- ✅ Your workstation: **Windows, macOS, or Linux**
- ✅ Virtualization: VirtualBox, VMware, Hyper-V, KVM
- ✅ VM: Rocky Linux 9

---

### Scenario 4: Cloud Deployment (AWS, Azure, GCP)

**✅ Start From: Any OS (Windows, macOS, Linux)**

**What You Need:**
- Your workstation (any OS)
- Cloud account (AWS/Azure/GCP)
- Rocky Linux cloud image

**Steps:**

```bash
# 1. Launch Rocky Linux instance:
#    - OS: Rocky Linux 9
#    - Size: 4 vCPU, 16GB RAM
#    - Disk: 100GB
#    - Security Group: Allow 22, 80, 443, 6443

# 2. SSH to instance
ssh rocky@<instance-ip>

# 3. Install SIAB
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash

# 4. Access from browser
open https://<instance-ip>
```

**Requirements:**
- ✅ Your workstation: **Windows, macOS, or Linux**
- ✅ Cloud: AWS, Azure, GCP, etc.
- ✅ Instance: Rocky Linux 9

---

## Detailed OS Requirements

### Your Workstation (Where You Start)

#### Windows 10/11
**✅ Can Do:**
- Run GUI Provisioner
- Access web UIs (catalog, dashboard)
- SSH to Linux machines
- Git clone repositories

**Requirements:**
- Python 3.8+ (for GUI)
- Git for Windows
- PuTTY or built-in SSH
- Modern web browser

**Setup:**
```powershell
# Install Python from python.org
# Install Git from git-scm.com

# Clone SIAB
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB\gui
SIAB-Provisioner.bat
```

#### macOS 11+
**✅ Can Do:**
- Run GUI Provisioner
- Access web UIs
- SSH to Linux machines
- Git clone repositories

**Requirements:**
- Python 3 (usually pre-installed)
- Git (install via Xcode Command Line Tools)
- Terminal
- Modern web browser

**Setup:**
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Clone SIAB
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB/gui
./SIAB-Provisioner.sh
```

#### Linux (Ubuntu, Fedora, etc.)
**✅ Can Do:**
- Everything Windows/macOS can do
- Plus: Can BE a provisioning server

**Requirements:**
- Python 3 + tkinter
- Git
- Terminal
- Modern web browser

**Setup:**
```bash
# Ubuntu/Debian
sudo apt-get install python3 python3-tk git

# Fedora/RHEL/Rocky
sudo dnf install python3 python3-tkinter git

# Clone SIAB
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB/gui
./SIAB-Provisioner.sh
```

### Provisioning Server (For Bare Metal Only)

#### Rocky Linux 8.x or 9.x (Recommended)
**✅ Use For:**
- PXE boot server
- Direct SIAB installation
- Production deployments

**Setup:**
```bash
# Minimal install
# Enable network
# Run PXE setup
sudo ./provisioning/pxe/setup-pxe-server.sh
```

#### Ubuntu 22.04 LTS
**✅ Use For:**
- MAAS server (enterprise provisioning)
- PXE boot server (alternative)

**Setup:**
```bash
# For MAAS
sudo ./provisioning/maas/setup-maas.sh

# For PXE
sudo ./provisioning/pxe/setup-pxe-server.sh
```

#### ❌ NOT Supported for Provisioning Server:
- Windows
- macOS
- CentOS (use Rocky Linux instead)
- Debian (use Ubuntu instead)

### Target Machines (Where SIAB Runs)

#### Rocky Linux 8.x or 9.x ONLY
**This is what gets installed on your target servers**

**✅ Supported:**
- Rocky Linux 8.8+
- Rocky Linux 9.3+ (recommended)

**❌ NOT Supported:**
- Ubuntu, Debian
- CentOS (EOL)
- RHEL (should work but not tested)
- Other distributions

## Common Setups

### Home Lab Setup

```
Your Laptop (Windows/macOS/Linux)
    │
    ├─→ VirtualBox/VMware
    │   └─→ Rocky Linux 9 VM (4 CPU, 16GB RAM)
    │       └─→ SIAB installed here
    │
    └─→ Browser: https://<vm-ip>
```

### Small Office Setup

```
Your Laptop (Windows/macOS/Linux)
    │
    ├─→ Provisioning Server (Rocky Linux VM)
    │   └─→ PXE Server running
    │
    └─→ 3x Bare Metal Servers
        └─→ Auto-install Rocky Linux via PXE
        └─→ Auto-install SIAB
```

### Enterprise Setup

```
Your Laptop (Windows/macOS/Linux)
    │
    ├─→ MAAS Server (Ubuntu 22.04)
    │   └─→ Manages 50+ servers
    │
    └─→ Bare Metal Cluster
        └─→ Auto-provisioned
        └─→ SIAB platform running
```

## Prerequisites by OS

### For Windows Users

**What to Install:**
1. Python 3.8+ from python.org
   - ✅ Check "Add Python to PATH"
   - ✅ Check "tcl/tk and IDLE"

2. Git for Windows from git-scm.com
   - ✅ Use default settings

3. (Optional) PuTTY for SSH

**What You Get:**
- GUI Provisioner works
- Browser access to all UIs
- Can manage SIAB remotely

**What You Can't Do:**
- Can't run provisioning server on Windows
- Can't install SIAB directly on Windows

**Solution:**
Use a Linux VM or cloud instance for the provisioning server/SIAB installation.

### For macOS Users

**What to Install:**
1. Xcode Command Line Tools
   ```bash
   xcode-select --install
   ```

2. (Optional) Homebrew
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

**What You Get:**
- Python 3 usually pre-installed
- GUI Provisioner works
- Native SSH client
- Browser access to all UIs

**What You Can't Do:**
- Can't run provisioning server on macOS
- Can't install SIAB directly on macOS

**Solution:**
Use a Linux VM or cloud instance for the provisioning server/SIAB installation.

### For Linux Users

**What to Install:**

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install python3 python3-tk git curl
```

**Fedora/RHEL/Rocky:**
```bash
sudo dnf install python3 python3-tkinter git curl
```

**What You Get:**
- Everything works
- Can BE a provisioning server
- Can run SIAB directly (if Rocky Linux)

**Advantage:**
Linux users have the most options and can run everything locally if desired.

## Quick Start Decision Tree

```
Do you have Rocky Linux machines already?
├─ YES → SSH to them, run install.sh (works from any OS)
└─ NO
    └─ Do you have blank bare metal servers?
        ├─ YES
        │   └─ Setup provisioning server (need Linux VM)
        │       └─ Use GUI from your laptop (any OS)
        └─ NO
            └─ Create Rocky Linux VM
                └─ Install SIAB in VM
                └─ Access from your laptop (any OS)
```

## Testing Before Production

**Recommended Path:**

1. **Week 1: VM Testing**
   - Create Rocky Linux 9 VM on your laptop
   - Install SIAB
   - Play with it
   - Learn the UI

2. **Week 2: Small Cluster**
   - Setup PXE server (can be a VM)
   - Deploy to 3 machines/VMs
   - Test multi-node features

3. **Week 3: Production**
   - Deploy to real hardware
   - Use MAAS for scale
   - Production workloads

## Getting Help

If you're unsure what to use:

1. **Just want to try SIAB?**
   → Create a Rocky Linux 9 VM, run install.sh

2. **Have 1-5 servers?**
   → Use PXE boot from your laptop's GUI

3. **Have 10+ servers?**
   → Setup MAAS on Ubuntu, use GUI to manage

4. **Using cloud?**
   → Launch Rocky Linux instances, run install.sh

## Summary Table

| Your Situation | Your OS | What to Use | Target OS |
|----------------|---------|-------------|-----------|
| Try in VM | Any | VM software | Rocky Linux 9 |
| Have Rocky Linux | Any | SSH + install.sh | Rocky Linux |
| Bare metal (1-5) | Any | GUI + PXE server | Rocky Linux |
| Bare metal (10+) | Any | GUI + MAAS | Rocky Linux |
| Cloud | Any | Cloud console | Rocky Linux 9 |

## Next Steps

Once you know your scenario, see:

- [Getting Started Guide](./getting-started.md) - Installation steps
- [GUI Provisioner Guide](./gui-provisioner.md) - Using the GUI
- [Bare Metal Provisioning](./bare-metal-provisioning.md) - Detailed provisioning guide

## Still Confused?

**Simple answer:**

1. Download SIAB on your laptop (Windows, Mac, or Linux - doesn't matter)
2. Create a Rocky Linux 9 VM (or use a cloud instance)
3. SSH to it and run:
   ```bash
   curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
   ```
4. Access from your browser: `https://<rocky-linux-ip>`

That's it! Start there, then explore bare metal provisioning when you're ready.
