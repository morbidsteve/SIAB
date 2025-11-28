# Archived Helper Scripts

This directory contains helper scripts that were created during development and troubleshooting but are no longer needed for normal SIAB operation.

## Why These Scripts Were Archived

These scripts were created to fix specific issues during development:

- **fix-istio-mtls.sh** - Fixed mTLS configuration issues (now handled by install.sh)
- **fix-keycloak-*.sh** - Fixed Keycloak integration issues (now handled properly in manifests)
- **fix-rke2.sh** - Fixed RKE2 installation issues (now handled by install.sh)
- **deep-dive-keycloak.sh** - Debugging script for Keycloak issues
- **diagnose-keycloak-connectivity.sh** - Connection diagnostics for Keycloak

## Current Equivalent Functionality

The functionality these scripts provided is now handled by:

1. **install.sh** - Comprehensive installation script with proper configurations
2. **manifests/istio/peer-authentication.yaml** - Proper mTLS configuration
3. **manifests/istio/gateways.yaml** - Correct gateway setup with HTTPS redirects
4. **scripts/configure-firewalld.sh** - Comprehensive firewall configuration
5. **siab-diagnose.sh** - General diagnostics tool

## When You Might Need These

These scripts are kept for reference and may be useful if you encounter similar issues during development or need to understand how specific problems were solved.

## Recommended Alternatives

For troubleshooting, use:

- `siab-status.sh` - Check overall SIAB status
- `siab-diagnose.sh` - Comprehensive diagnostics
- `diagnose-upstream-errors.sh` - Diagnose upstream connection errors
- `test-https-access.sh` - Test HTTPS configuration
- `kubectl logs` - View pod logs for specific issues

## Restoration

If you need to use these scripts:

```bash
cd scripts/archived
chmod +x script-name.sh
./script-name.sh
```

**Note:** These scripts may not work correctly with the current configuration as they were designed for specific troubleshooting scenarios that have since been resolved.
