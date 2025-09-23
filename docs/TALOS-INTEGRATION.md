# Talos Extension Services Integration

This document explains how the FRR extension integrates with Talos v1.5+ ExtensionServiceConfig to minimize environment variable usage.

## Overview

Starting with Talos v1.5.0, extension services can be configured using `ExtensionServiceConfig` documents, which provide a structured way to:
- Mount complete configuration files directly into the extension container
- Eliminate the need for environment variables
- Manage service dependencies and lifecycle

## Architecture

```
┌─────────────────────────────────────────────┐
│            Talos Machine Config              │
│                                              │
│  ┌─────────────────────────────────────┐    │
│  │    ExtensionServiceConfig (FRR)     │    │
│  │                                      │    │
│  │  - configFiles:                     │    │
│  │    - config.yaml                    │    │
│  │    - neighbors.json                 │    │
│  │    - daemons                        │    │
│  │                                      │    │
│  │  - environment:                     │    │
│  │    - FRR_CONFIG_FILE (optional)    │    │
│  └─────────────────────────────────────┘    │
│                      │                       │
│                      ▼                       │
│  ┌─────────────────────────────────────┐    │
│  │      FRR Extension Container        │    │
│  │                                      │    │
│  │  /etc/frr/config.yaml (mounted)     │    │
│  │  config_loader.py (reads configs)   │    │
│  │  docker-start (uses configs)        │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Configuration Methods

### Method 1: Full ExtensionServiceConfig (Recommended)

```yaml
# /var/lib/talos/machine-config.yaml
machine:
  install:
    extensions:
      - image: ghcr.io/elastx/frr-talos-extension:latest

---
# ExtensionServiceConfig contains ALL configuration
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        cilium:
          local_asn: 4200099998
          remote_asn: 4200099999
          namespace: cilium
          peering:
            ipv4:
              local: 192.168.250.254
              remote: 192.168.250.255
              prefix: 31
        upstream:
          local_asn: 4200001001      # Define directly here
          fabric_asn: 48579
          router_id: 10.10.10.10    # Define directly here
      network:
        interface_mtu: 1500
    mountPath: /etc/frr/config.yaml

environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml  # Optional
```

### Method 2: Per-Node Configuration

```yaml
# Different config for each node
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001  # node1 specific
          router_id: 10.10.10.1
    mountPath: /etc/frr/config.yaml
```

### Method 3: Override Specific Values

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  # Override just the neighbors
  - content: |
      {
        "neighbours": {
          "ipv4": ["10.0.0.1", "10.0.0.2"],
          "ipv6": ["2001:db8::1", "2001:db8::2"]
        }
      }
    mountPath: /etc/frr/neighbors.json

environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml
```

## How It Works

1. **Talos loads the extension** with the system extension image
2. **ExtensionServiceConfig is applied**:
   - Config files are written to specified mountPaths
3. **Container starts** with docker-start script
4. **config_loader.py**:
   - Reads config files (YAML/JSON) only
   - No environment variable processing
   - Generates final configuration
5. **FRR starts** with the configuration

## Zero Environment Variables Approach

### Before (Many Environment Variables)
```yaml
machine:
  env:
    ASN_LOCAL: "4200001001"
    NODE_IP: "10.10.10.10"
    NEIGHBOR_PASSWORD: "secret"
    # ... many more ...
```

### After (Config Files Only)
```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001  # All values in config
          router_id: 10.10.10.10
          password: "secret"
    mountPath: /etc/frr/config.yaml
environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml  # Only config path
```

## Advanced Features

### Dynamic Configuration Updates

```yaml
# Use Talos machine config patches for updates
talosctl patch mc --patch-file frr-config-update.yaml
```

### Per-Node Configuration

```yaml
# node1-config.yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001
          router_id: 10.10.10.1
    mountPath: /etc/frr/config.local.yaml
```

### Secret Management

```yaml
# Use Talos secrets for sensitive data
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
environment:
  - NEIGHBOR_PASSWORD=${secrets.bgp_password}
```

## Deployment Steps

1. **Build and push the extension image**:
```bash
docker build -f Dockerfile.v2 -t ghcr.io/yourorg/frr-talos-extension:latest .
docker push ghcr.io/yourorg/frr-talos-extension:latest
```

2. **Create machine config with ExtensionServiceConfig**:
```yaml
# machine-config.yaml
machine:
  install:
    extensions:
      - image: ghcr.io/yourorg/frr-talos-extension:latest

---
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
# ... configuration
```

3. **Apply configuration**:
```bash
talosctl apply-config -n <node-ip> -f machine-config.yaml
```

4. **Verify the service**:
```bash
talosctl service frr status -n <node-ip>
talosctl logs frr -n <node-ip>
```

## Troubleshooting

### Check Extension Service Status
```bash
talosctl service frr status -n <node-ip>
```

### View Configuration Files
```bash
talosctl read /etc/frr/config.yaml -n <node-ip>
```

### Check Logs
```bash
talosctl logs frr -n <node-ip> -f
```

### Verify ExtensionServiceConfig
```bash
talosctl get extensionserviceconfigs -n <node-ip>
```

## Migration Guide

### Step 1: Identify Static vs Dynamic Values

**Static** (move to configFiles):
- Cilium AS numbers
- Network namespaces
- Peering IPs
- Interface settings

**Dynamic** (keep as environment):
- Node-specific ASN
- Node IP address
- Passwords/secrets

### Step 2: Create ExtensionServiceConfig

1. Move static values to config.yaml
2. Keep only essential env variables
3. Test with one node first

### Step 3: Rollout

```bash
# Apply to one node
talosctl apply-config -n node1 -f new-config.yaml

# Verify
talosctl service frr status -n node1

# Apply to all nodes
talosctl apply-config -n node1,node2,node3 -f new-config.yaml
```

## Compatibility

- **Talos**: >= v1.5.0 (ExtensionServiceConfig support)
- **FRR**: 8.5.7 (container version)
- **Cilium**: 1.14+ (BGP Control Plane)

## References

- [Talos Extension Services](https://www.talos.dev/v1.11/advanced/extension-services/)
- [ExtensionServiceConfig Reference](https://www.talos.dev/v1.11/reference/configuration/extensions/extensionserviceconfig/)
- [System Extensions Guide](https://www.talos.dev/v1.11/talos-guides/configuration/system-extensions/)