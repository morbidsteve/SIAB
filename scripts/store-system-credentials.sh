#!/bin/bash
# Store SIAB system credentials in protected Kubernetes secrets
# This script should be run after initial setup to ensure all credentials are stored
# Credentials are stored in siab-system namespace (admin access only)

set -e

NAMESPACE="siab-system"

echo "=== SIAB System Credentials Storage ==="
echo "Storing credentials in namespace: $NAMESPACE"
echo ""

# Ensure namespace exists
kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# Function to store credentials
store_credential() {
    local name="$1"
    local username="$2"
    local password="$3"
    local url="$4"
    local notes="$5"
    local extra_key="$6"
    local extra_value="$7"

    echo "Storing credentials for: $name"

    # Build the secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: system-creds-${name}
  namespace: ${NAMESPACE}
  labels:
    siab.local/credential-type: system-credentials
    siab.local/service-name: ${name}
type: Opaque
stringData:
  service-name: "${name}"
  username: "${username}"
  password: "${password}"
  url: "${url}"
  notes: "${notes}"
  created: "$(date -Iseconds)"
$(if [ -n "$extra_key" ]; then echo "  ${extra_key}: \"${extra_value}\""; fi)
EOF
}

# Function to store token-based credentials
store_token_credential() {
    local name="$1"
    local token="$2"
    local url="$3"
    local notes="$4"

    echo "Storing token for: $name"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: system-creds-${name}
  namespace: ${NAMESPACE}
  labels:
    siab.local/credential-type: system-credentials
    siab.local/service-name: ${name}
type: Opaque
stringData:
  service-name: "${name}"
  token: "${token}"
  url: "${url}"
  notes: "${notes}"
  created: "$(date -Iseconds)"
EOF
}

echo ""
echo "--- Kubernetes Dashboard ---"
# Generate a fresh long-lived token using kubectl create token (modern K8s 1.24+ method)
# This creates a proper JWT token that works with K8s Dashboard
K8S_TOKEN=$(kubectl create token siab-admin -n kubernetes-dashboard --duration=87600h 2>/dev/null || echo "")
if [ -z "$K8S_TOKEN" ]; then
    # Fallback: try reading from the static secret (older method)
    K8S_TOKEN=$(kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
fi
if [ -n "$K8S_TOKEN" ]; then
    store_token_credential "kubernetes-dashboard" \
        "$K8S_TOKEN" \
        "https://k8s-dashboard.siab.local" \
        "Use this bearer token to login to Kubernetes Dashboard (valid for 10 years)"
else
    echo "Warning: Could not generate K8s Dashboard token"
fi

echo ""
echo "--- Keycloak ---"
# Get Keycloak admin password
KEYCLOAK_PASS=$(kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "admin")
store_credential "keycloak" \
    "admin" \
    "$KEYCLOAK_PASS" \
    "https://keycloak.siab.local" \
    "Keycloak admin console - manages SSO and user authentication"

echo ""
echo "--- MinIO ---"
# Get MinIO credentials
MINIO_USER=$(kubectl get secret minio -n minio -o jsonpath='{.data.rootUser}' 2>/dev/null | base64 -d || echo "admin")
MINIO_PASS=$(kubectl get secret minio -n minio -o jsonpath='{.data.rootPassword}' 2>/dev/null | base64 -d || echo "")
if [ -n "$MINIO_PASS" ]; then
    store_credential "minio" \
        "$MINIO_USER" \
        "$MINIO_PASS" \
        "https://minio.siab.local" \
        "MinIO object storage - S3-compatible storage backend"
else
    echo "Warning: Could not retrieve MinIO credentials"
fi

echo ""
echo "--- Grafana ---"
# Get Grafana admin password
GRAFANA_PASS=$(kubectl get secret grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$GRAFANA_PASS" ]; then
    store_credential "grafana" \
        "admin" \
        "$GRAFANA_PASS" \
        "https://grafana.siab.local" \
        "Grafana monitoring dashboards"
else
    echo "Info: Grafana credentials not found (may not be deployed)"
fi

echo ""
echo "--- Longhorn ---"
# Longhorn uses basic auth - check for existing secret
LONGHORN_USER=$(kubectl get secret longhorn-auth -n longhorn-system -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
LONGHORN_PASS=$(kubectl get secret longhorn-auth -n longhorn-system -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$LONGHORN_USER" ] && [ -n "$LONGHORN_PASS" ]; then
    store_credential "longhorn" \
        "$LONGHORN_USER" \
        "$LONGHORN_PASS" \
        "https://longhorn.siab.local" \
        "Longhorn storage management UI"
else
    echo "Info: Longhorn auth not configured (UI may be open)"
    store_credential "longhorn" \
        "none" \
        "none" \
        "https://longhorn.siab.local" \
        "Longhorn storage management UI - no authentication configured"
fi

echo ""
echo "=== Credential Storage Complete ==="
echo ""
echo "To view all stored credentials:"
echo "  kubectl get secrets -n $NAMESPACE -l siab.local/credential-type"
echo ""
echo "To view a specific credential:"
echo "  kubectl get secret system-creds-<name> -n $NAMESPACE -o yaml"
echo ""
echo "To decode a password:"
echo "  kubectl get secret system-creds-keycloak -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "To decode a token:"
echo "  kubectl get secret system-creds-kubernetes-dashboard -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d"
