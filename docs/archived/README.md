# Archived Documentation

This directory contains documentation files that have been superseded by the new consolidated documentation structure.

## Why These Files Were Archived

As part of documentation consolidation, we identified significant redundancy and fragmentation across multiple documentation files. These files have been archived because their content has been incorporated into the new streamlined documentation.

## New Documentation Structure

The new consolidated documentation provides a clear, hierarchical structure:

### Primary Documentation (Root Directory)

- **README.md** - Main entry point with quick start, architecture overview, and links to detailed guides
- **SIAB-Complete-Documentation-Wiki.md** - Comprehensive single-file documentation for Wiki.js
- **SECURITY.md** - Complete security guide covering HTTPS, firewalld, mTLS, IAM, and best practices

### Detailed Guides (docs/ Directory)

- **APPLICATION-DEPLOYMENT-GUIDE.md** - Comprehensive application deployment walkthrough
- **FIREWALLD-CONFIGURATION.md** - Detailed firewall configuration guide
- **HTTPS-CONFIGURATION.md** - HTTPS and TLS configuration guide
- **bare-metal-provisioning.md** - PXE/MAAS provisioning guide

## What Was Archived and Where to Find It Now

| Archived File | Replacement | Notes |
|---------------|-------------|-------|
| QUICK-START.md | README.md (Quick Start section) | Consolidated into main README |
| getting-started.md | README.md + docs/APPLICATION-DEPLOYMENT-GUIDE.md | Split between overview and detailed guide |
| deployment.md | docs/APPLICATION-DEPLOYMENT-GUIDE.md | Expanded into comprehensive guide |
| security.md | SECURITY.md (root) | Consolidated and expanded |
| configuration.md | SECURITY.md + docs/FIREWALLD-CONFIGURATION.md + docs/HTTPS-CONFIGURATION.md | Split into focused guides |
| testing-istio-access.md | scripts/test-https-access.sh + docs/HTTPS-CONFIGURATION.md | Automated via script, documented in guide |
| external-vm-access.md | docs/HTTPS-CONFIGURATION.md | Covered in HTTPS access section |
| where-to-start.md | README.md | Main README now provides clear starting point |
| istio-migration.md | N/A | Obsolete - installation now uses current Istio version |
| gui-provisioner.md | docs/bare-metal-provisioning.md | Consolidated into bare metal guide |
| TROUBLESHOOTING-UPSTREAM-ERRORS.md | siab-diagnose.sh + docs/FIREWALLD-CONFIGURATION.md | Automated diagnostics + firewall troubleshooting |

## Benefits of the New Structure

1. **Single Entry Point**: README.md provides clear starting point with links to detailed guides
2. **No Redundancy**: Each topic covered once in the appropriate location
3. **Clear Hierarchy**: General → Specific → Advanced flow
4. **Wiki-Friendly**: SIAB-Complete-Documentation-Wiki.md provides single comprehensive document
5. **Focused Guides**: Each guide covers one topic thoroughly rather than fragmenting information

## Using Archived Files

These files are kept for reference but should not be used for new installations or configurations. If you need historical context or want to see how documentation evolved, these files remain available.

For current documentation, always refer to:
- README.md (start here)
- SIAB-Complete-Documentation-Wiki.md (comprehensive reference)
- docs/ directory guides (detailed topics)
