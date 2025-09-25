# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a customized FRR (Free Range Routing) Talos system extension for BGP routing on Kubernetes hosts. It creates a containerized FRR instance that:
- Provides BGP routing on the Talos Linux host
- Peers with Cilium BGP Control Plane to receive load balancer IP routes
- Forwards routes to upstream leaf routers
- Supports both IPv4 and IPv6
- Works with Cilium BGP Control Plane for LoadBalancer service management
- Includes BFD (Bidirectional Forwarding Detection) for fast failure detection

## Build Commands

```bash
# Build Docker image locally
docker build -t frr-talos-extension .

# The image is also automatically built and pushed via GitHub Actions on master/tags
# Published to: ghcr.io/jsenecal/frr-talos-extension
```

## Architecture

### Core Components

1. **Docker Container Build** (`Dockerfile`):
   - Multi-stage build using FRR base image (v8.5.7)
   - Installs required tools: gettext, j2cli, jq
   - Embeds configuration templates and startup scripts
   - Creates Talos extension structure in `/rootfs/usr/local/`

2. **Container Startup** (`docker-start`):
   - Creates Linux network namespace `cilium` for BGP peering
   - Sets up veth pair (veth-frr/veth-cilium) for BGP peering between FRR and Cilium
   - Loads configuration from YAML/JSON files using config_loader.py
   - Generates FRR config from Jinja2 template using loaded configuration
   - Starts syslogd and FRR services
   - Monitors BGP status in a loop

3. **BGP Configuration** (`frr.conf.j2`):
   - Two BGP instances:
     - VRF instance (AS 4200099998) for Cilium peering
     - Main instance for upstream fabric peering
   - Route redistribution from Cilium VRF to main routing table
   - Support for both IPv4 and IPv6 address families
   - Per-peer configuration for passwords, timers, and BFD profiles
   - Network announcement filtering:
     - Global network lists for default announcements
     - Per-peer advertise_networks for specific filtering
     - BGP attribute manipulation (AS path, communities, etc.)

4. **Configuration Management** (`config_loader.py`):
   - Loads configuration from YAML/JSON files exclusively
   - Merges multiple config files with override capability
   - Validates required configuration fields
   - Generates JSON output for Jinja2 template rendering

## Configuration Approach

This extension uses a **configuration file only** approach - all environment variables have been removed in favor of structured YAML configuration.

### Configuration via ExtensionServiceConfig
```yaml
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
          local_asn: 4200001001      # Node-specific ASN
          router_id: 10.10.10.10      # Node-specific IP
          peers:
            - address: 10.0.0.1
              remote_asn: 48579
              password: "secret"
              bfd:
                enabled: true
                profile: normal
    mountPath: /usr/local/etc/frr/config.yaml
```

### Default Values (in configuration templates)
- Cilium AS numbers: 4200099998 (FRR side), 4200099999 (Cilium side)
- Cilium namespace: `cilium` (Linux network namespace, not Kubernetes namespace)
- Veth IP addresses: 192.168.250.254/31 (IPv4), fdae:6bef:5e65::1/126 (IPv6)

## Project Structure

### Core Files
- `Dockerfile`: Multi-stage build with BFD support enabled
- `docker-start`: Unified startup script with config loader support
- `config_loader.py`: Python script for flexible configuration management
- `frr.yaml`: Container definition for Talos system extension
- `manifest.yaml`: Extension metadata (name, version, compatibility)
- `daemons`: FRR daemon configuration (enables zebra, bgpd, staticd, bfdd)

### Configuration Template
- `frr.conf.j2`: FRR configuration template with full feature support (multi-peer, BFD, network announcements)

### Documentation (`docs/`)
- `BFD-CONFIGURATION.md`: BFD setup and best practices
- `CONFIGURATION.md`: Configuration management guide
- `DEPLOYMENT.md`: Complete deployment instructions
- `TALOS-INTEGRATION.md`: Talos ExtensionServiceConfig integration

### Examples (`examples/`)
- `config.yaml`: Basic configuration without BFD
- `config-bfd.yaml`: Configuration with BFD profiles
- `cilium-values.yaml`: Helm values for Cilium
- `cilium-bgp-config.yaml`: Cilium BGP CRDs
- `extension-service-config*.yaml`: Talos service configurations
- `talos-config-example.yaml`: Complete Talos machine config

### CI/CD
- `.github/workflows/build-and-push.yaml`: GitHub Actions for container registry

## BGP Peering Details

### FRR to Upstream (Fabric)
- Upstream fabric peers with AS 48579 (hardcoded)
- Uses aggressive timers (1s keepalive, 3s hold)
- Multipath relaxed for load balancing
- Route maps for source address selection and loop prevention
- Connected routes redistributed from lo/dummy interfaces only

### FRR to Cilium
- FRR AS 4200099998 peers with Cilium AS 4200099999
- Peering over veth pair using Linux network namespace `cilium`
- Imports LoadBalancer service IPs from Cilium
- Supports both IPv4 and IPv6 address families

## Cilium Configuration

### Installation
```bash
helm install cilium cilium/cilium -f cilium-values.yaml
kubectl apply -f cilium-bgp-config.yaml
kubectl label node <node-name> bgp=enabled
```

### BGP Resources
- `CiliumBGPClusterConfig`: Defines BGP instances and peers
- `CiliumBGPPeerConfig`: BGP session parameters
- `CiliumBGPAdvertisement`: Specifies which services to advertise

## BFD Configuration

BFD is fully integrated with three predefined profiles:
- **aggressive**: 100ms intervals, 300ms detection (local/veth connections)
- **normal**: 300ms intervals, 900ms detection (data center fabric)
- **relaxed**: 1000ms intervals, 5s detection (WAN/Internet)

Configure BFD profiles and per-peer settings directly in the configuration YAML