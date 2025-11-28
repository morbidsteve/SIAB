# Firewalld Configuration for SIAB

## Overview

This document explains how to properly configure firewalld to work with SIAB's RKE2, Canal (Calico+Flannel), and Istio components.

## Why Firewalld Configuration is Critical

**IMPORTANT:** By default, firewalld conflicts with RKE2's Canal networking and will cause pod-to-pod connectivity failures with errors like:
```
upstream connect error: delayed connect error: 113 (No route to host)
```

However, completely disabling firewalld is **not recommended** for production systems. Instead, firewalld must be configured to allow the necessary traffic.

## Quick Start

Run the provided configuration script as root:

```bash
sudo /home/fscyber/soc/SIAB/scripts/configure-firewalld.sh
```

This script will automatically configure all required firewall rules.

## Manual Configuration

If you prefer to configure firewalld manually, follow these steps:

### 1. Add CNI Interfaces to Trusted Zone

CNI interfaces must be in the trusted zone for pod-to-pod communication:

```bash
# Add CNI interfaces (some may not exist until pods are created)
sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1
sudo firewall-cmd --permanent --zone=trusted --add-interface=tunl0
```

### 2. Add Pod and Service CIDRs to Trusted Sources

```bash
# Pod CIDR
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16

# Service CIDR
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
```

### 3. Open Required Ports

#### RKE2 Ports

```bash
# Kubernetes API Server
sudo firewall-cmd --permanent --add-port=6443/tcp

# RKE2 Supervisor API
sudo firewall-cmd --permanent --add-port=9345/tcp

# Kubelet
sudo firewall-cmd --permanent --add-port=10250/tcp

# etcd
sudo firewall-cmd --permanent --add-port=2379-2380/tcp

# NodePort Services
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
```

#### Canal (Calico + Flannel) Ports

```bash
# Flannel VXLAN
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --permanent --add-port=4789/udp

# Flannel Wireguard (if used)
sudo firewall-cmd --permanent --add-port=51820-51821/udp

# Calico BGP
sudo firewall-cmd --permanent --add-port=179/tcp

# Calico Typha
sudo firewall-cmd --permanent --add-port=5473/tcp
```

#### Istio Ports

```bash
# Ingress gateways (HTTP/HTTPS)
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp

# Istio control plane
sudo firewall-cmd --permanent --add-port=15010/tcp
sudo firewall-cmd --permanent --add-port=15012/tcp
sudo firewall-cmd --permanent --add-port=15014/tcp
sudo firewall-cmd --permanent --add-port=15017/tcp

# Istio health and metrics
sudo firewall-cmd --permanent --add-port=15021/tcp
sudo firewall-cmd --permanent --add-port=15090/tcp
```

### 4. Enable Masquerading

```bash
sudo firewall-cmd --permanent --zone=public --add-masquerade
sudo firewall-cmd --permanent --zone=trusted --add-masquerade
```

### 5. Reload Firewalld

```bash
sudo firewall-cmd --reload
```

## Verification

### Check Firewalld Status

```bash
sudo firewall-cmd --state
```

### List Configured Rules

```bash
# List all zones
sudo firewall-cmd --list-all-zones

# Check trusted zone
sudo firewall-cmd --zone=trusted --list-all

# Check public zone
sudo firewall-cmd --zone=public --list-all
```

### Test Pod-to-Pod Connectivity

```bash
# Test from ingress gateway to a backend pod
kubectl exec -n istio-system deployment/istio-ingress-admin -- nc -zv <backend-pod-ip> 8080
```

## Troubleshooting

### Connectivity Issues After Enabling Firewalld

If you experience connectivity issues after enabling firewalld:

1. **Check CNI interfaces are in trusted zone:**
   ```bash
   sudo firewall-cmd --zone=trusted --list-interfaces
   ```

2. **Verify pod/service CIDRs are trusted:**
   ```bash
   sudo firewall-cmd --zone=trusted --list-sources
   ```

3. **Check for blocked traffic in logs:**
   ```bash
   sudo journalctl -u firewalld -f
   ```

4. **Temporarily disable to confirm firewalld is the issue:**
   ```bash
   sudo systemctl stop firewalld
   # Test connectivity
   sudo systemctl start firewalld
   ```

### Common Issues

#### Issue: "No route to host" errors

**Cause:** CNI interfaces not in trusted zone or pod CIDR not allowed.

**Solution:** Ensure cni0, flannel.1, and tunl0 are in the trusted zone and pod CIDR 10.42.0.0/16 is a trusted source.

#### Issue: Ingress gateway cannot reach backend pods

**Cause:** Missing firewall rules for Istio or CNI traffic.

**Solution:** Run the configure-firewalld.sh script or manually add all required ports and trusted zones.

## References

- [RKE2 Known Issues - Firewalld](https://docs.rke2.io/known_issues)
- [Calico Firewall Integration](https://docs.tigera.io/calico/latest/operations/firewall)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)

## Port Reference Table

| Port(s) | Protocol | Service | Purpose |
|---------|----------|---------|---------|
| 6443 | TCP | Kubernetes API | API server access |
| 9345 | TCP | RKE2 | Supervisor API |
| 10250 | TCP | Kubelet | Kubelet API |
| 2379-2380 | TCP | etcd | etcd client and peer communication |
| 30000-32767 | TCP | NodePort | NodePort service range |
| 8472 | UDP | Flannel | VXLAN overlay network |
| 4789 | UDP | Flannel | VXLAN overlay network (alt) |
| 51820-51821 | UDP | Flannel | Wireguard encryption |
| 179 | TCP | Calico | BGP routing |
| 5473 | TCP | Calico | Typha communication |
| 80 | TCP | Istio | HTTP ingress |
| 443 | TCP | Istio | HTTPS ingress |
| 15010-15017 | TCP | Istio | Control plane communication |
| 15021 | TCP | Istio | Health checks |
| 15090 | TCP | Istio | Prometheus metrics |
