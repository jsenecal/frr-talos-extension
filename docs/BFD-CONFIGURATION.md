# BFD (Bidirectional Forwarding Detection) Configuration Guide

This guide explains how to configure BFD with FRR for fast failure detection in BGP sessions.

## Overview

BFD provides rapid failure detection times between adjacent forwarding engines, with detection times typically in milliseconds. When integrated with BGP, it allows for much faster convergence than traditional BGP keepalive/hold timers.

## Benefits of BFD

1. **Fast Failure Detection**: Sub-second detection (typically 300-900ms)
2. **Lower Control Plane Load**: BFD runs at lower layer than BGP
3. **Protocol Independent**: Can be used with BGP, OSPF, static routes
4. **Hardware Offload**: Some NICs can offload BFD processing

## Configuration Structure

### BFD Profiles

Profiles define reusable timer configurations:

```yaml
bfd:
  profiles:
    aggressive:
      detect_multiplier: 3      # Number of missed packets before declaring down
      receive_interval: 100     # Expected receive interval in milliseconds
      transmit_interval: 100    # Transmit interval in milliseconds
      echo_mode: false         # Echo mode (typically disabled for iBGP)

    normal:
      detect_multiplier: 3
      receive_interval: 300
      transmit_interval: 300
      echo_mode: false

    relaxed:
      detect_multiplier: 5
      receive_interval: 1000
      transmit_interval: 1000
      echo_mode: false
```

### Detection Time Calculation

Detection time = `detect_multiplier × max(receive_interval, transmit_interval)`

Examples:
- **Aggressive**: 3 × 100ms = 300ms detection
- **Normal**: 3 × 300ms = 900ms detection
- **Relaxed**: 5 × 1000ms = 5 seconds detection

## BGP Integration

### Enable BFD for Cilium Peering

```yaml
bfd:
  cilium_peering:
    enabled: true
    profile: aggressive  # Use aggressive for local veth connection
    check_control_plane_failure: true
```

### Enable BFD for Fabric Peering

```yaml
bfd:
  fabric_peering:
    enabled: true
    profile: normal  # Use normal for physical network links
    check_control_plane_failure: true
```

## Deployment Options

### Option 1: Using ExtensionServiceConfig

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bfd:
        profiles:
          datacenter:
            detect_multiplier: 3
            receive_interval: 200
            transmit_interval: 200
        cilium_peering:
          enabled: true
          profile: datacenter
        fabric_peering:
          enabled: true
          profile: datacenter
    mountPath: /usr/local/etc/frr/config.yaml

environment:
  - FRR_USE_BFD=true
  - BFD_FABRIC_PROFILE=datacenter
```

### Option 2: Environment Variables

For simple on/off control:

```yaml
machine:
  env:
    FRR_USE_BFD: "true"
    BFD_FABRIC_ENABLED: "true"
    BFD_FABRIC_PROFILE: "normal"
    BFD_CILIUM_ENABLED: "true"
    BFD_CILIUM_PROFILE: "aggressive"
```

### Option 3: Direct Peer Configuration

Configure BFD peers independently of BGP:

```yaml
bfd:
  peers:
    - address: 10.0.0.1
      profile: normal
      multihop: true
      local_address: 10.10.10.10  # Your node IP

    - address: 10.0.0.2
      detect_multiplier: 4
      receive_interval: 500
      transmit_interval: 500
      multihop: true
```

## Profile Recommendations

### Local/Veth Connections (Cilium)
- **Profile**: `aggressive`
- **Detection Time**: 300ms
- **Use Case**: Container-to-container on same host

### Data Center Fabric
- **Profile**: `normal`
- **Detection Time**: 900ms
- **Use Case**: Typical data center with reliable network

### WAN/Internet
- **Profile**: `relaxed`
- **Detection Time**: 5 seconds
- **Use Case**: Internet peering, unreliable networks

### Custom Requirements

Create custom profiles for specific needs:

```yaml
bfd:
  profiles:
    ultra_fast:
      detect_multiplier: 2
      receive_interval: 50
      transmit_interval: 50
      # Detection time: 100ms (requires stable network)

    wan_stable:
      detect_multiplier: 6
      receive_interval: 2000
      transmit_interval: 2000
      # Detection time: 12 seconds (for high-latency links)
```

## Monitoring and Troubleshooting

### Check BFD Status

```bash
# Show all BFD peers
vtysh -c "show bfd peers"

# Show brief status
vtysh -c "show bfd peers brief"

# Show specific peer
vtysh -c "show bfd peer 10.0.0.1"

# Show BFD counters
vtysh -c "show bfd peers counters"
```

### Example Output

```
BFD Peers:
    peer 192.168.250.255 veth-frr
        ID: 12345
        Remote ID: 67890
        Status: up
        Uptime: 1 hour(s), 23 minute(s), 45 second(s)
        Diagnostics: ok
        Remote Diagnostics: ok
        Peer Type: configured
        Local timers:
            Detect-multiplier: 3
            Receive interval: 300ms
            Transmission interval: 300ms
        Remote timers:
            Detect-multiplier: 3
            Receive interval: 300ms
            Transmission interval: 300ms
```

### Debug BFD

```bash
# Enable BFD debugging
vtysh -c "debug bfd"

# Check logs
tail -f /var/log/frr/frr.log | grep bfd

# Show BFD configuration
vtysh -c "show running-config bfdd"
```

## Integration with BGP

### Verify BGP is using BFD

```bash
# Show BGP neighbor with BFD status
vtysh -c "show bgp neighbor 10.0.0.1"

# Look for:
# BFD: Type: single hop
# Detect Multiplier: 3, Min Rx interval: 300, Min Tx interval: 300
# Status: Up, Last update: 00:05:23
```

### BGP Behavior with BFD

When BFD detects a failure:
1. BFD session goes down
2. BGP is immediately notified
3. BGP session is torn down
4. Routes are withdrawn
5. Traffic reroutes to backup paths

Without BFD, BGP would wait for hold timer (default 180 seconds).

## Best Practices

### 1. Start Conservative
Begin with `normal` profile and tune based on needs:
- Monitor false positives
- Check CPU utilization
- Verify network stability

### 2. Match Peer Settings
Ensure both sides use compatible timers:
- Negotiation will use slowest intervals
- Mismatched settings can cause issues

### 3. Consider Network Quality
- **Stable networks**: Can use aggressive timers
- **Unstable networks**: Use relaxed timers to avoid flapping
- **WAN links**: Account for jitter and packet loss

### 4. Monitor Resources
BFD can consume CPU at very aggressive intervals:
- 50ms intervals = 20 packets/second per peer
- Consider hardware offload if available

### 5. Use Profiles
Define profiles for consistency:
- Easier to manage
- Reduces configuration errors
- Simplifies updates

## Common Issues

### BFD Session Not Establishing

1. **Check connectivity**:
   ```bash
   ping -I veth-frr 192.168.250.254
   ```

2. **Verify BFD daemon**:
   ```bash
   ps aux | grep bfdd
   ```

3. **Check firewall/iptables**:
   - BFD uses UDP ports 3784-3785
   - Ensure not blocked

### False Positives (Flapping)

If BFD sessions flap:
1. Increase intervals
2. Increase detect_multiplier
3. Check network stability
4. Monitor CPU usage

### BGP Not Using BFD

Verify configuration:
```bash
vtysh -c "show running-config" | grep -A5 "neighbor.*bfd"
```

Ensure both BGP and BFD are configured for the peer.

## Performance Tuning

### CPU Optimization

For many peers with aggressive timers:

```yaml
bfd:
  profiles:
    optimized:
      detect_multiplier: 3
      receive_interval: 250  # Balance between speed and CPU
      transmit_interval: 250
      echo_mode: false       # Disable echo to save CPU
```

### Network Optimization

For networks with micro-bursts:

```yaml
bfd:
  profiles:
    burst_tolerant:
      detect_multiplier: 5    # Higher tolerance
      receive_interval: 200   # Still reasonably fast
      transmit_interval: 200
```

## Migration from BGP Timers to BFD

### Before (BGP-only)
```yaml
bgp:
  upstream:
    timers:
      keepalive: 1    # 1 second
      hold: 3         # 3 seconds minimum detection
```

### After (with BFD)
```yaml
bgp:
  upstream:
    timers:
      keepalive: 10   # Can be relaxed
      hold: 30        # BFD handles fast detection

bfd:
  fabric_peering:
    enabled: true
    profile: normal  # 900ms detection
```

## References

- [FRR BFD Documentation](https://docs.frrouting.org/en/latest/bfd.html)
- [RFC 5880 - BFD](https://tools.ietf.org/html/rfc5880)
- [RFC 5882 - BFD for BGP](https://tools.ietf.org/html/rfc5882)