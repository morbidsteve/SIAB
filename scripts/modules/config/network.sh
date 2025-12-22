#!/bin/bash
# SIAB - Network Configuration Module
# Network policies and Kubernetes namespace management

# Requires: logging.sh, config.sh, progress/status.sh

# Create Kubernetes namespaces
create_namespaces() {
    start_step "Kubernetes Namespaces"

    log_info "Creating Kubernetes namespaces..."

    # Create namespaces for SIAB components
    for ns in "${SIAB_NAMESPACES[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    done

    # Label namespaces for Istio injection where appropriate
    kubectl label namespace siab-dashboard istio-injection=enabled --overwrite 2>/dev/null || true
    kubectl label namespace siab-deployer istio-injection=enabled --overwrite 2>/dev/null || true
    kubectl label namespace oauth2-proxy istio-injection=enabled --overwrite 2>/dev/null || true

    # Disable Istio injection for namespaces that don't support it well
    kubectl label namespace monitoring istio-injection=disabled --overwrite 2>/dev/null || true
    kubectl label namespace minio istio-injection=disabled --overwrite 2>/dev/null || true
    kubectl label namespace keycloak istio-injection=disabled --overwrite 2>/dev/null || true
    kubectl label namespace kubernetes-dashboard istio-injection=disabled --overwrite 2>/dev/null || true

    complete_step "Kubernetes Namespaces"
    log_info "Namespaces created"
}

# Apply security policies
apply_security_policies() {
    start_step "Security Policies"

    log_info "Applying security policies..."

    # Default deny network policy for default namespace
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
EOF

    # Apply additional security policies from repo if available
    if [[ -d "${SIAB_REPO_DIR}/manifests/security" ]]; then
        log_info "Applying additional security policies..."
        kubectl apply -f "${SIAB_REPO_DIR}/manifests/security/" 2>/dev/null || {
            log_warn "Some security policies may have failed to apply (gatekeeper constraints need templates first)"
        }
    fi

    complete_step "Security Policies"
    log_info "Security policies applied"
}

# Update /etc/hosts with SIAB domain entries
update_hosts_file() {
    log_info "Updating /etc/hosts with SIAB entries..."

    # Load network config if available
    if [[ -f "${SIAB_CONFIG_DIR}/network.env" ]]; then
        source "${SIAB_CONFIG_DIR}/network.env"
    fi

    # Get gateway IPs from Kubernetes if not in config
    local admin_ip="${ADMIN_GATEWAY_ACTUAL_IP:-}"
    local user_ip="${USER_GATEWAY_ACTUAL_IP:-}"

    if [[ -z "$admin_ip" ]]; then
        admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    if [[ -z "$user_ip" ]]; then
        user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    # Admin plane hosts
    if [[ -n "$admin_ip" ]]; then
        local admin_hosts="keycloak.${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN}"

        for host in $admin_hosts; do
            if ! grep -q "$host" /etc/hosts; then
                echo "${admin_ip} ${host}" >> /etc/hosts
            fi
        done
    fi

    # User plane hosts
    if [[ -n "$user_ip" ]]; then
        local user_hosts="auth.${SIAB_DOMAIN} deployer.${SIAB_DOMAIN} dashboard.${SIAB_DOMAIN} ${SIAB_DOMAIN}"

        for host in $user_hosts; do
            if ! grep -q "$host" /etc/hosts; then
                echo "${user_ip} ${host}" >> /etc/hosts
            fi
        done
    fi

    log_info "Hosts file updated"
}

# Remove SIAB entries from /etc/hosts
cleanup_hosts_file() {
    log_info "Removing SIAB entries from /etc/hosts..."

    # Remove lines containing SIAB domain
    sed -i "/${SIAB_DOMAIN}/d" /etc/hosts 2>/dev/null || true

    log_info "Hosts file cleaned"
}
