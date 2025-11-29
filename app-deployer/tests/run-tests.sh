#!/bin/bash
#
# SIAB App Deployer Test Runner
#
# Usage:
#   ./run-tests.sh              # Run all tests locally
#   ./run-tests.sh --in-cluster # Run tests inside the cluster
#   ./run-tests.sh --quick      # Run quick unit tests only
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")/backend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  SIAB App Deployer Test Suite"
echo "========================================"
echo ""

# Parse arguments
RUN_IN_CLUSTER=false
QUICK_TESTS=false

for arg in "$@"; do
    case $arg in
        --in-cluster)
            RUN_IN_CLUSTER=true
            ;;
        --quick)
            QUICK_TESTS=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --in-cluster   Run tests inside the cluster pod"
            echo "  --quick        Run quick unit tests only (skip cluster tests)"
            echo "  --help         Show this help message"
            exit 0
            ;;
    esac
done

# Function to run tests locally
run_local_tests() {
    echo -e "${YELLOW}Running local tests...${NC}"
    echo ""

    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: python3 is not installed${NC}"
        exit 1
    fi

    # Install test dependencies if needed
    pip3 install --quiet flask flask-cors pyyaml requests 2>/dev/null || true

    # Change to backend directory and run tests
    cd "$BACKEND_DIR"

    # Skip Python tests if dependencies not available, go straight to API tests
    if python3 -c "import flask" 2>/dev/null; then
        if [ "$QUICK_TESTS" = true ]; then
            echo "Running quick unit tests (skipping cluster integration)..."
            python3 -c "
import sys
import importlib.util
sys.path.insert(0, '.')
spec = importlib.util.spec_from_file_location('api', 'app-deployer-api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)

# Quick smoke tests
print('Testing content detection...')
result = api.detect_content_type('apiVersion: v1\nkind: Service', 'test.yaml')
assert result['type'] == 'manifest', 'Manifest detection failed'
print('  ✓ Manifest detection works')

result = api.detect_content_type('services:\n  web:\n    image: nginx', 'compose.yml')
assert result['type'] == 'compose', 'Compose detection failed'
print('  ✓ Compose detection works')

result = api.detect_content_type('FROM python:3.11\nRUN pip install flask', 'Dockerfile')
assert result['type'] == 'dockerfile', 'Dockerfile detection failed'
print('  ✓ Dockerfile detection works')

print('')
print('Testing pre-built image detection...')
image, port = api.check_prebuilt_image('FROM base', {'org': 'linuxserver', 'repo': 'docker-wireshark'})
assert image == 'lscr.io/linuxserver/wireshark:latest', 'Linuxserver image detection failed'
print('  ✓ Linuxserver image detection works')

print('')
print('Testing docker-compose parsing...')
compose = '''
services:
  web:
    image: nginx
    ports:
      - \"80:80\"
'''
manifests = api.parse_docker_compose(compose)
assert len(manifests) == 2, 'Compose parsing failed'
print('  ✓ Compose parsing works')

print('')
print('Testing manifest generation...')
manifests, error = api.create_deployment_from_image('test', 'nginx', 'default', 80)
assert error is None, f'Manifest generation failed: {error}'
assert len(manifests) == 2, 'Wrong number of manifests'
print('  ✓ Manifest generation works')

print('')
print('All quick tests passed!')
"
        else
            # Run full test suite
            python3 "$SCRIPT_DIR/test_deployer.py"
        fi
    else
        echo -e "${YELLOW}Python Flask not available locally. Skipping unit tests.${NC}"
        echo "Running API integration tests only..."
    fi
}

# Function to run tests in cluster
run_cluster_tests() {
    echo -e "${YELLOW}Running tests inside cluster...${NC}"
    echo ""

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi

    # Find the backend pod
    POD=$(kubectl get pods -n siab-deployer -l app=app-deployer-backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POD" ]; then
        echo -e "${RED}Error: Could not find app-deployer-backend pod${NC}"
        echo "Make sure the app-deployer is deployed in the siab-deployer namespace"
        exit 1
    fi

    echo "Found pod: $POD"
    echo ""

    # Copy test file to pod
    echo "Copying test file to pod..."
    kubectl cp "$SCRIPT_DIR/test_deployer.py" "siab-deployer/$POD:/tmp/test_deployer.py" -c api

    # Run tests in pod
    echo "Running tests in pod..."
    kubectl exec -n siab-deployer "$POD" -c api -- python3 /tmp/test_deployer.py
}

# Run API endpoint tests
run_api_tests() {
    echo -e "${YELLOW}Running API endpoint tests...${NC}"
    echo ""

    # Determine the API URL
    API_URL="${API_URL:-https://deployer.siab.local}"

    echo "Testing API at: $API_URL"
    echo ""

    # Test health endpoint
    echo -n "Testing /health endpoint... "
    HEALTH=$(curl -s -k "$API_URL/health" 2>/dev/null)
    if echo "$HEALTH" | grep -q '"status".*"healthy"'; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Response: $HEALTH"
    fi

    # Test fetch-git with linuxserver repo
    echo -n "Testing /api/fetch-git with linuxserver repo... "
    FETCH=$(curl -s -k -X POST -H "Content-Type: application/json" \
        -d '{"url":"https://github.com/linuxserver/docker-wireshark"}' \
        "$API_URL/api/fetch-git" 2>/dev/null)
    if echo "$FETCH" | grep -q '"success".*true'; then
        echo -e "${GREEN}PASS${NC}"
        # Check if repo_info is included
        if echo "$FETCH" | grep -q '"repo_info"'; then
            echo "  ✓ repo_info included in response"
        fi
        if echo "$FETCH" | grep -q '"type".*"dockerfile"'; then
            echo "  ✓ Detected as Dockerfile"
        fi
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Response: $FETCH"
    fi

    # Test fetch-git with invalid URL
    echo -n "Testing /api/fetch-git with invalid URL... "
    FETCH=$(curl -s -k -X POST -H "Content-Type: application/json" \
        -d '{"url":"https://invalid-url-that-does-not-exist.invalid/repo"}' \
        "$API_URL/api/fetch-git" 2>/dev/null)
    if echo "$FETCH" | grep -q '"success".*false'; then
        echo -e "${GREEN}PASS${NC} (correctly returned error)"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    # Test namespaces endpoint
    echo -n "Testing /api/namespaces... "
    NS=$(curl -s -k "$API_URL/api/namespaces" 2>/dev/null)
    if echo "$NS" | grep -q '"namespaces"'; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    # Test applications list
    echo -n "Testing /api/applications... "
    APPS=$(curl -s -k "$API_URL/api/applications?namespace=all" 2>/dev/null)
    if echo "$APPS" | grep -q '"applications"'; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    echo ""
}

# Main execution
if [ "$RUN_IN_CLUSTER" = true ]; then
    run_cluster_tests
else
    run_local_tests

    echo ""
    echo "========================================"
    echo "  Running API Integration Tests"
    echo "========================================"
    echo ""

    run_api_tests
fi

echo ""
echo -e "${GREEN}Test run complete!${NC}"
