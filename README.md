# FRR Talos System Extension

BGP routing for Talos Linux with Cilium integration, multi-peer support, and BFD configuration.

## Overview

This FRR extension provides BGP routing capabilities for Talos Linux nodes, integrating with Cilium BGP Control Plane for LoadBalancer service management. All configuration is managed through ExtensionServiceConfig files without environment variables.

## Features

- **Configuration via ExtensionServiceConfig**: All settings in YAML configuration files
- **Multiple BGP Peers**: Configure unlimited peers with individual settings
- **Per-Peer Configuration**: Different passwords, timers, BFD profiles per peer
- **BGP Routing**: Full BGP support with FRR 10.4.1
- **Cilium Integration**: Replaces MetalLB for LoadBalancer services
- **BFD Support**: Fast failure detection with configurable profiles
- **Dual Stack**: IPv4 and IPv6 support with per-peer address families

## Quick Start

### Build

```bash
docker build -t frr-talos-extension .
```

### Deploy

1. Install the extension in your Talos configuration:

```yaml
machine:
  install:
    extensions:
      - image: ghcr.io/elastx/frr-talos-extension:latest
```

2. Configure via ExtensionServiceConfig:

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001
          router_id: 10.10.10.10
          peers:
            - address: 10.0.0.1
              remote_asn: 48579
              password: "secret"
              bfd:
                enabled: true
                profile: normal
    mountPath: /etc/frr/config.yaml
```

## Configuration

### BGP Peers

Configure multiple peers with individual settings:

```yaml
peers:
  - address: 10.0.0.1
    remote_asn: 48579
    description: "Primary Leaf Switch"
    password: "uniquePassword1"
    bfd:
      enabled: true
      profile: aggressive

  - address: 10.0.0.2
    remote_asn: 48579
    description: "Secondary Leaf Switch"
    password: "uniquePassword2"
    bfd:
      enabled: true
      profile: normal

  - address: 10.0.0.3
    remote_asn: 64512
    description: "Backup Router"
    password: "backupPassword"
    multihop: 2
    bfd:
      enabled: true
      profile: relaxed
```

### BFD Profiles

Three predefined BFD profiles for different network scenarios:

- **aggressive**: 300ms detection (local/primary links)
- **normal**: 900ms detection (data center fabric)
- **relaxed**: 5s detection (backup/WAN links)

Monitor BFD status: `vtysh -c "show bfd peers"`

## Cilium Integration

1. Install Cilium with BGP enabled:
```bash
helm install cilium cilium/cilium -f examples/cilium-values.yaml
```

2. Apply BGP configuration:
```bash
kubectl apply -f examples/cilium-bgp-config.yaml
```

3. Label nodes for BGP:
```bash
kubectl label node <node-name> bgp=enabled
```

## Network Architecture

- FRR creates a veth pair (`veth-frr` and `veth-cilium`)
- `veth-cilium` is placed in the `cilium` Linux network namespace
- Cilium BGP Control Plane peers with FRR over this veth pair
- FRR imports routes from Cilium and advertises them to upstream routers

## Documentation

- [BFD Configuration](docs/BFD-CONFIGURATION.md) - Detailed BFD setup and profiles
- [Configuration Guide](docs/CONFIGURATION.md) - Complete configuration reference
- [Deployment Guide](docs/DEPLOYMENT.md) - Step-by-step deployment instructions
- [Talos Integration](docs/TALOS-INTEGRATION.md) - ExtensionServiceConfig details

## Examples

See the `examples/` directory for complete configuration examples:
- `config.yaml` - Basic configuration
- `config-bfd.yaml` - Configuration with BFD
- `extension-service-config.yaml` - Talos ExtensionServiceConfig
- `cilium-bgp-config.yaml` - Cilium BGP CRDs
- `cilium-values.yaml` - Cilium Helm values

## Image

Pre-built images are available at `ghcr.io/elastx/frr-talos-extension`