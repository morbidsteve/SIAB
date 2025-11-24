#!/bin/bash
# Script to merge testing suite to main branch
# Run this if you have admin access to bypass branch protection

set -e

echo "Merging testing suite commits to main..."

# Ensure we're on the feature branch
git checkout claude/test-vm-access-015M6jdDBfNsyDcTMb1PcCEc

# Checkout main and pull latest
git checkout main
git pull origin main

# Merge the feature branch
git merge claude/test-vm-access-015M6jdDBfNsyDcTMb1PcCEc --no-ff -m "Merge: Add comprehensive testing suite

Adds complete test suite and documentation:
- siab-test.sh: Comprehensive validation script (14 test categories)
- docs/testing-guide.md: Full testing documentation
- TESTING.md: Quick reference guide
- README updates with testing section

Enables users to validate all SIAB components and troubleshoot issues."

# Try to push (may fail if branch protection is enabled)
echo "Attempting to push to main..."
git push origin main || {
    echo ""
    echo "❌ Push failed (branch protection enabled)"
    echo ""
    echo "Please merge via Pull Request:"
    echo "https://github.com/morbidsteve/SIAB/compare/main...claude/test-vm-access-015M6jdDBfNsyDcTMb1PcCEc"
    exit 1
}

echo "✅ Successfully merged to main!"
