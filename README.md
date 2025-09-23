# FRR Talos System Extension - Zero Environment Variables!

BGP routing for Talos Linux with Cilium integration, multi-peer support, and BFD - all configured via ExtensionServiceConfig

***

## Key Innovation: No Environment Variables Required!

This FRR extension eliminates the need for environment variables. All configuration - including node-specific settings - is defined directly in the ExtensionServiceConfig.

### Before (Old Way - Many Environment Variables)
```yaml
machine:
  env:
    ASN_LOCAL: 4200001001
    NODE_IP: 10.10.10.10
    NEIGHBOR_PASSWORD: secret
    # ... many more ...
```

### After (New Way - Zero Environment Variables)
```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001     # Defined here, not in env!
          router_id: 10.10.10.10    # Defined here, not in env!
          peers:
            - address: 10.0.0.1
              remote_asn: 48579
              password: "secret1"   # Per-peer passwords!
              bfd:
                profile: normal
            - address: 10.0.0.2
              remote_asn: 48579
              password: "secret2"
              bfd:
                profile: aggressive
    mountPath: /etc/frr/config.yaml

environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml  # Optional, defaults to this path
```

Build the image locally

```
docker build -t frr-talos-extension .
```

## Features

- **✨ Zero Environment Variables**: All configuration in ExtensionServiceConfig
- **🔄 Multiple BGP Peers**: Configure unlimited peers with individual settings
- **🔑 Per-Peer Configuration**: Different passwords, timers, BFD profiles per peer
- **🚀 BGP Routing**: Full BGP support with FRR 8.5.7
- **🌐 Cilium Integration**: Replaces MetalLB for LoadBalancer services
- **⚡ BFD Support**: Fast failure detection with per-peer profiles
- **🔢 IPv4/IPv6**: Dual-stack support with per-peer address families

## Cilium Integration

This extension now integrates with Cilium BGP Control Plane instead of MetalLB:

1. **Install Cilium with BGP enabled**:
   ```bash
   helm install cilium cilium/cilium -f cilium-values.yaml
   ```

2. **Apply BGP configuration**:
   ```bash
   kubectl apply -f cilium-bgp-config.yaml
   ```

3. **Label nodes for BGP**:
   ```bash
   kubectl label node <node-name> bgp=enabled
   ```

## Network Architecture

- FRR container creates a veth pair (`veth-frr` and `veth-cilium`)
- `veth-cilium` is placed in the `cilium` Linux network namespace
- Cilium agent on the host accesses this veth interface for BGP peering
- Cilium BGP Control Plane peers with FRR over this veth pair
- FRR imports routes from Cilium and advertises them to upstream routers

## Image Availability

## Multiple Peer Support

Configure each peer individually with its own settings:

```yaml
peers:
  - address: 10.0.0.1
    remote_asn: 48579
    description: "Primary Leaf Switch"
    password: "uniquePassword1"
    bfd:
      enabled: true
      profile: aggressive  # Fast detection for primary

  - address: 10.0.0.2
    remote_asn: 48579
    description: "Secondary Leaf Switch"
    password: "uniquePassword2"
    bfd:
      enabled: true
      profile: normal     # Standard detection for secondary

  - address: 10.0.0.3
    remote_asn: 64512     # Different ASN
    description: "Backup Router"
    password: "backupPassword"
    multihop: 2           # Multi-hop BGP
    bfd:
      enabled: true
      profile: relaxed    # Relaxed for backup
```

## BFD Configuration

BFD profiles are now per-peer configurable:
- `aggressive`: 300ms detection (primary links)
- `normal`: 900ms detection (standard links)
- `relaxed`: 5s detection (backup/WAN links)

Monitor: `vtysh -c "show bfd peers"`

See [docs/BFD-CONFIGURATION.md](docs/BFD-CONFIGURATION.md) for detailed configuration.

## Image Availability

Image is available at `ghcr.io/elastx/frr-talos-extension`

## Project Structure

```
├── Dockerfile              # Main container build file with BFD support
├── docker-start            # Container startup script
├── frr.conf.j2             # Standard FRR config template
├── frr-bfd.conf.j2         # FRR config template with BFD
├── config_loader.py        # Configuration management script
├── docs/                   # Documentation
│   ├── BFD-CONFIGURATION.md
│   ├── CONFIGURATION.md
│   ├── DEPLOYMENT.md
│   └── TALOS-INTEGRATION.md
└── examples/               # Example configurations
    ├── config.yaml
    ├── config-bfd.yaml
    ├── cilium-bgp-config.yaml
    ├── cilium-values.yaml
    └── extension-service-config*.yaml
```



