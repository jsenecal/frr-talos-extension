# Network Announcements Configuration Guide

This guide explains how to configure FRR to announce specific networks/prefixes to upstream BGP peers with per-peer filtering.

## Overview

The FRR Talos extension supports flexible network announcement configurations:
- **Global networks**: Define networks to announce to all peers by default
- **Per-peer networks**: Override global settings with peer-specific announcements
- **Route attributes**: Set BGP attributes (communities, AS path prepend, etc.) per peer
- **Advanced filtering**: Use custom prefix-lists and route-maps for complex scenarios

## Configuration Structure

### Global Network Announcements

Define networks to announce to all upstream peers (unless overridden):

```yaml
bgp:
  upstream:
    networks:
      ipv4:
        - 192.168.0.0/24
        - 10.0.0.0/24
      ipv6:
        - 2001:db8:1::/48
```

### Per-Peer Network Announcements

Override global networks for specific peers using `advertise_networks`:

```yaml
bgp:
  upstream:
    peers:
      - address: 10.0.0.1
        remote_asn: 48579
        description: "Public-ISP"
        # Only announce these specific networks to this peer
        advertise_networks:
          - 203.0.113.0/24    # Public IP range
          - 198.51.100.0/24   # Another public range
        # Optional: Set BGP attributes for advertised routes
        advertise_set:
          as_path_prepend: "4200001001 4200001001"
          community: "48579:100"
          local_preference: 200
          metric: 50
```

## Common Use Cases

### 1. Public vs Private IP Separation

Announce public IPs to ISPs and private IPs to internal peers:

```yaml
peers:
  # ISP peer - only public IPs
  - address: 10.0.0.1
    remote_asn: 48579
    description: "ISP-Public"
    advertise_networks:
      - 203.0.113.0/24    # Your public IP block

  # Internal peer - only private IPs
  - address: 10.0.0.2
    remote_asn: 65001
    description: "Internal-Network"
    advertise_networks:
      - 192.168.0.0/16
      - 10.0.0.0/8
```

### 2. Multi-Homing with Different Preferences

Announce the same networks to multiple providers with different attributes:

```yaml
peers:
  # Primary ISP - preferred path
  - address: 10.0.0.1
    remote_asn: 48579
    description: "Primary-ISP"
    advertise_networks:
      - 203.0.113.0/24
    advertise_set:
      as_path_prepend: "4200001001"    # Shorter AS path

  # Backup ISP - less preferred
  - address: 10.0.0.2
    remote_asn: 65002
    description: "Backup-ISP"
    advertise_networks:
      - 203.0.113.0/24
    advertise_set:
      as_path_prepend: "4200001001 4200001001 4200001001"  # Longer AS path
```

### 3. IPv6 Network Announcements

Configure IPv6-specific peers and announcements:

```yaml
peers:
  - address: 2001:db8::ffff
    remote_asn: 65003
    address_family: ipv6
    description: "IPv6-Transit"
    advertise_networks:
      - 2001:db8:1::/48
      - 2001:db8:2::/48
    advertise_set:
      community: "65003:200"
```

## Advanced Filtering

### Custom Prefix Lists

Define custom prefix lists for fine-grained control:

```yaml
route_filters:
  prefix_lists:
    ipv4:
      PUBLIC_NETS:
        rules:
          - seq: 10
            action: permit
            prefix: 203.0.113.0/24
          - seq: 20
            action: permit
            prefix: 198.51.100.0/23
            ge: 24    # Match /24 or longer
            le: 24    # Match /24 or shorter
```

### Custom Route Maps

Create complex filtering and attribute manipulation:

```yaml
route_filters:
  route_maps:
    EXPORT_PUBLIC:
      rules:
        - seq: 10
          action: permit
          match:
            prefix_list: PUBLIC_NETS
            address_family: ipv4
          set:
            community: "48579:100 48579:200"
            local_preference: 150
        - seq: 20
          action: deny    # Deny everything else
```

Then reference the route map in peer configuration:

```yaml
peers:
  - address: 10.0.0.1
    remote_asn: 48579
    route_map_out: EXPORT_PUBLIC
```

## Configuration Priority

The system applies configurations in this order:

1. **Custom route-map** (`route_map_out`): If specified, uses the custom route-map
2. **Per-peer networks** (`advertise_networks`): If specified, auto-generates prefix-lists and route-maps
3. **Global networks**: Falls back to global network list if no peer-specific configuration

## BGP Attributes

When using `advertise_set`, you can configure these attributes:

- `as_path_prepend`: Prepend AS numbers to make path less preferred
- `community`: Add BGP community tags
- `local_preference`: Set local preference (iBGP only)
- `metric`: Set MED (Multi-Exit Discriminator)

## Complete Example

See `/examples/config-network-announce.yaml` for a comprehensive example covering:
- Multiple peer types (ISP, private, transit)
- Public vs private IP separation
- IPv4 and IPv6 announcements
- BGP attribute manipulation
- Custom prefix-lists and route-maps

## Verification

After applying configuration, verify announcements:

```bash
# Check BGP neighbor status
vtysh -c "show ip bgp summary"

# View advertised routes to a specific peer
vtysh -c "show ip bgp neighbor 10.0.0.1 advertised-routes"

# Check prefix-lists
vtysh -c "show ip prefix-list"

# Check route-maps
vtysh -c "show route-map"
```

## Troubleshooting

1. **Networks not being announced**: Ensure the network exists in the routing table (via `network` statement or redistribution)
2. **Wrong networks to peer**: Check peer-specific `advertise_networks` configuration
3. **Attributes not applied**: Verify `advertise_set` configuration and route-map syntax
4. **IPv6 not working**: Ensure `address_family: ipv6` is set for IPv6 peers