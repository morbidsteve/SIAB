# SIAB Modular Installation System

This directory contains the modular components for the improved SIAB installation system.

## What's New

### 1. Static UI (No Scrolling)
- Clean dashboard that updates in place
- Real-time progress tracking
- No more scrolling output cluttering the screen
- Beautiful terminal UI

### 2. Comprehensive Logging
- All output logged to timestamped files: `/var/log/siab/install-YYYYMMDD-HHMMSS.log`
- Symlink to latest: `/var/log/siab/install.log`
- Every command execution logged with timestamps and exit codes
- Detailed debugging information

### 3. Legacy Mode Support
- Set `SIAB_LEGACY_OUTPUT=1` to use old scrolling output
- Automatically falls back to legacy mode if:
  - Not running in a terminal (piped/redirected)
  - Terminal too small (< 24 rows or < 80 cols)

## Directory Structure

```
/tmp/siab-modular/
├── lib/
│   └── ui.sh              # UI and logging library
├── installers/            # Component installers (to be created)
│   ├── rke2.sh
│   ├── istio.sh
│   ├── storage.sh
│   ├── security.sh
│   └── monitoring.sh
└── README.md
```

## Quick Integration

### Option 1: Test the UI Library First

Integrate just the UI improvements into the existing install.sh:

```bash
cd /home/fscyber/soc/SIAB

# Backup existing install.sh
cp install.sh install.sh.backup

# Add the lib directory
sudo mkdir -p lib
sudo cp /tmp/siab-modular/lib/ui.sh lib/
sudo chown -R fscyber:fscyber lib/

# Modify install.sh to source the UI library
# Add after line 10 (after SIAB_BIN_DIR definition):
#   source "${SIAB_DIR}/lib/ui.sh" || source "$(dirname "$0")/lib/ui.sh"
```

### Option 2: Full Modular Installation (Recommended)

Wait for all modular components to be created, then:

```bash
cd /home/fscyber/soc/SIAB

# Backup existing
cp install.sh install.sh.backup

# Copy modular structure
sudo cp -r /tmp/siab-modular/lib .
sudo cp -r /tmp/siab-modular/installers .
sudo cp /tmp/siab-modular/install-new.sh install.sh
sudo chown -R fscyber:fscyber lib installers
```

## Using the UI Library

### Initialize in Your Script

```bash
#!/bin/bash
set -euo pipefail

# Constants
readonly SIAB_VERSION="1.0.0"
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"

# Source UI library
source "$(dirname "$0")/lib/ui.sh"

# Define installation steps
declare -a INSTALL_STEPS=(
    "System Requirements"
    "RKE2 Kubernetes"
    "Istio Service Mesh"
    # ... etc
)

# Initialize step tracking
declare -A STEP_STATUS
declare -A STEP_MESSAGE

for step in "${INSTALL_STEPS[@]}"; do
    STEP_STATUS["$step"]="pending"
done

# Initialize logging and UI
init_logging
init_ui

# Your installation steps
start_step "System Requirements"
update_log_output "Checking CPU cores..."
log_cmd "grep -c ^processor /proc/cpuinfo"
complete_step "System Requirements"

# Show final summary
show_summary
```

### Example Output

**Static UI Mode** (default):
```
╔════════════════════════════════════════════════════════════════╗
║              SIAB Installation Progress                        ║
╚════════════════════════════════════════════════════════════════╝

  ● System Requirements      ◐ Istio Service Mesh
  ● System Dependencies      ○ Istio Gateways
  ● RKE2 Kubernetes          ○ Keycloak Identity
  ● Helm Package Manager     ○ MinIO Storage

▶ Installing Istio Service Mesh...

Downloading istioctl version 1.20.1...

Log: /var/log/siab/install-20251128-162045.log
```

**Legacy Mode** (`SIAB_LEGACY_OUTPUT=1`):
```
[STEP] System Requirements
[INFO] Checking CPU cores
[✓] System Requirements completed
[STEP] RKE2 Kubernetes
[INFO] Installing RKE2 v1.28.4+rke2r1
...
```

## UI Library API

### Logging Functions

- `init_logging()` - Initialize logging system
- `log_cmd "command"` - Execute and log command with full output
- `log_info_file "message"` - Log to file only (INFO level)
- `log_warn_file "message"` - Log to file only (WARN level)
- `log_error_file "message"` - Log to file only (ERROR level)
- `log_info "message"` - Log with screen output (legacy mode) and file
- `log_warn "message"` - Warn with screen output and file
- `log_error "message"` - Error with screen output and file

### UI Functions

- `init_ui()` - Initialize static UI
- `cleanup_ui()` - Restore terminal on exit
- `update_current_step "message"` - Update current step indicator
- `update_log_output "message"` - Update last activity line
- `draw_status_dashboard()` - Redraw status grid

### Step Management

- `start_step "Step Name"` - Mark step as running
- `complete_step "Step Name" ["message"]` - Mark step as done
- `skip_step "Step Name" "reason"` - Mark step as skipped
- `fail_step "Step Name" "reason"` - Mark step as failed

### Final Summary

- `show_summary()` - Show completion summary with statistics

## Features

### Automatic Fallback
The UI automatically detects if it should use static or legacy mode:

- Not a TTY (piped/redirected): Legacy mode
- Terminal too small: Legacy mode
- `SIAB_LEGACY_OUTPUT=1` set: Legacy mode
- Otherwise: Static UI mode

### Comprehensive Logging
Every command execution is logged:

```
[2025-11-28 16:20:45] [CMD  ] Executing: kubectl get nodes
>>> Command: kubectl get nodes
>>> Started: 2025-11-28 16:20:45
NAME   STATUS   ROLES                       AGE   VERSION
siab   Ready    control-plane,etcd,master   10m   v1.28.4+rke2r1
>>> Exit code: 0
>>> Finished: 2025-11-28 16:20:46
```

### Exit Handling
Cleanup happens automatically on:
- Normal exit
- INT signal (Ctrl+C)
- TERM signal
- ERR trap

## Testing

### Test the UI Library

```bash
cd /tmp/siab-modular

# Create a test script
cat > test-ui.sh << 'EOF'
#!/bin/bash
source lib/ui.sh

SIAB_VERSION="1.0.0-test"
SIAB_LOG_DIR="/tmp"

declare -a INSTALL_STEPS=("Step 1" "Step 2" "Step 3")
declare -A STEP_STATUS
declare -A STEP_MESSAGE

for step in "${INSTALL_STEPS[@]}"; do
    STEP_STATUS["$step"]="pending"
done

init_logging
init_ui

start_step "Step 1"
sleep 2
complete_step "Step 1"

start_step "Step 2"
sleep 2
skip_step "Step 2" "Already configured"

start_step "Step 3"
sleep 2
complete_step "Step 3"

show_summary
EOF

chmod +x test-ui.sh
./test-ui.sh
```

### Test Legacy Mode

```bash
SIAB_LEGACY_OUTPUT=1 ./test-ui.sh
```

## Next Steps

1. **Review** the UI library code
2. **Test** the UI library with the test script
3. **Decide**:
   - Integrate just UI improvements into existing install.sh, OR
   - Wait for full modular system with component installers

4. **MAAS Integration**: After install.sh works perfectly, create MAAS automation

## Benefits

✅ Clean, professional installation experience
✅ Easy troubleshooting with comprehensive logs
✅ Modular, maintainable codebase
✅ Backward compatible with legacy mode
✅ No scrolling - updates in place
✅ Real-time progress tracking

## Files in This Package

- `lib/ui.sh` - 507 lines of UI and logging goodness
- `README.md` - This file

## Author Notes

The UI library is complete and tested. It can be integrated into the existing install.sh immediately, or we can wait to create the full modular system with all component installers separated.

The choice is yours!
