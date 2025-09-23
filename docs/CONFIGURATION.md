# Configuration Guide

This FRR extension uses a configuration file approach with all settings defined in YAML files mounted via ExtensionServiceConfig.

## Configuration Structure

All configuration is defined in YAML files mounted via ExtensionServiceConfig:

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      # Complete configuration here
    mountPath: /etc/frr/config.yaml
environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml  # Optional, this is the default
```

## Configuration Files

The system loads configuration files in this order (later files override earlier ones):

1. `/etc/frr/config.default.yaml` - Built-in defaults from container
2. `/etc/frr/config.yaml` - Main configuration file
3. `/etc/frr/config.local.yaml` - Local overrides (if present)
4. File specified in `FRR_CONFIG_FILE` environment variable (if set)

## Complete Configuration Example

```yaml
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
      ipv6:
        local: "fdae:6bef:5e65::1"
        remote: "fdae:6bef:5e65::2"
        prefix: 126

  upstream:
    local_asn: 4200001001      # Node's ASN
    router_id: 10.10.10.10      # Node's IP
    router_id_v6: "2001:db8::1" # Node's IPv6 (optional)

    # Multiple peers with individual settings
    peers:
      - address: 10.0.0.1
        remote_asn: 48579
        description: "Leaf Switch 1"
        password: "peer1secret"
        timers:
          keepalive: 1
          hold: 3
        bfd:
          enabled: true
          profile: normal

      - address: 10.0.0.2
        remote_asn: 48579
        description: "Leaf Switch 2"
        password: "peer2secret"
        bfd:
          enabled: true
          profile: aggressive

      # IPv6 peer
      - address: "2001:db8:ffff::1"
        remote_asn: 48579
        description: "Leaf Switch 1 IPv6"
        address_family: ipv6
        bfd:
          enabled: true
          profile: normal

network:
  interface_mtu: 1500
  veth_names:
    frr_side: veth-frr
    cilium_side: veth-cilium

bfd:
  profiles:
    aggressive:
      detect_multiplier: 3
      receive_interval: 100
      transmit_interval: 100
    normal:
      detect_multiplier: 3
      receive_interval: 300
      transmit_interval: 300
    relaxed:
      detect_multiplier: 5
      receive_interval: 1000
      transmit_interval: 1000

  cilium_peering:
    enabled: true
    profile: aggressive
```

## Per-Node Configuration

Since each node needs its own ASN and router ID, create a separate ExtensionServiceConfig for each node:

### Node 1
```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001
          router_id: 10.10.10.1
          peers:
            - address: 10.0.0.1
              remote_asn: 48579
              password: "node1secret"
    mountPath: /etc/frr/config.yaml
```

### Node 2
```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001002
          router_id: 10.10.10.2
          peers:
            - address: 10.0.0.2
              remote_asn: 48579
              password: "node2secret"
    mountPath: /etc/frr/config.yaml
```

## Applying Configuration

1. Create your configuration file
2. Add it to the ExtensionServiceConfig
3. Apply to the node:

```bash
talosctl apply-config -n <node-ip> -f machine-config.yaml
```

## Configuration Validation

The config loader validates required fields on startup:

- `bgp.upstream.local_asn` - Required
- `bgp.upstream.router_id` - Required
- `bgp.cilium.local_asn` - Required
- `bgp.cilium.remote_asn` - Required

If validation fails, the container will exit with an error message.

## Debugging Configuration

To see the loaded configuration:

```bash
# Inside the container
python3 /usr/local/bin/config_loader.py --json

# View the generated FRR config
cat /etc/frr/frr.conf

# Check FRR status
vtysh -c "show running-config"
```

## Key Benefits

- **Single source of truth**: All configuration in one file
- **Type safety**: YAML structure prevents configuration errors
- **Self-documenting**: Clear structure and field names
- **Version control friendly**: Easy to diff and review changes
- **Multiple peers**: Configure many peers with different settings
- **Clean machine config**: Simple ExtensionServiceConfig approach