# Deployment Guide: FRR with Cilium BGP Integration on Talos

This guide walks through deploying the FRR Talos extension with Cilium BGP Control Plane integration.

## Prerequisites

- Talos Linux cluster
- kubectl access to the cluster
- Helm 3.x installed

## Step 1: Configure Talos Machine

Create a machine configuration with ExtensionServiceConfig:

```yaml
machine:
  # Install the FRR system extension
  install:
    extensions:
      - image: ghcr.io/jsenecal/frr-talos-extension:latest

---
# All configuration in ExtensionServiceConfig
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      bgp:
        upstream:
          local_asn: 4200001001      # Your local AS number
          router_id: 10.10.10.10      # Your node IP
          router_id_v6: "2001:db8::1"  # Your node IPv6 (optional)
          peers:
            - address: 10.0.0.1
              remote_asn: 48579
              password: "secret"
              bfd:
                enabled: true
                profile: normal
      # ... rest of configuration
    mountPath: /etc/frr/config.yaml
environment:
  - FRR_CONFIG_FILE=/etc/frr/config.yaml
```

Apply the configuration:
```bash
talosctl apply-config -n <node-ip> -f machine-config.yaml
```

## Step 2: Install Cilium with BGP Support

1. Add Cilium Helm repository:
```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
```

2. Install Cilium with BGP enabled:
```bash
helm install cilium cilium/cilium \
  --version 1.18.2 \
  --namespace kube-system \
  -f cilium-values.yaml
```

3. Wait for Cilium to be ready:
```bash
cilium status --wait
```

## Step 3: Configure BGP Peering

1. Apply the BGP configuration:
```bash
kubectl apply -f cilium-bgp-config.yaml
```

2. Label nodes that should run BGP:
```bash
kubectl label node <node-name> bgp=enabled
```

## Step 4: Configure LoadBalancer IP Pool

Create an IP pool for LoadBalancer services:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
  - start: "192.168.100.10"
    stop: "192.168.100.250"
  serviceSelector:
    matchLabels:
      loadbalancer: "enabled"
```

Apply the configuration:
```bash
kubectl apply -f loadbalancer-pool.yaml
```

## Step 5: Verify BGP Peering

1. Check FRR container status:
```bash
# SSH into Talos node
talosctl shell -n <node-ip>

# Check FRR BGP status
docker exec frr vtysh -c "show bgp vrf all summary"
docker exec frr vtysh -c "show ip route"
```

2. Check Cilium BGP status:
```bash
# Get Cilium pod
CILIUM_POD=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

# Check BGP status
kubectl -n kube-system exec $CILIUM_POD -- cilium-dbg bgp peers
kubectl -n kube-system exec $CILIUM_POD -- cilium-dbg bgp routes
```

## Step 6: Test LoadBalancer Service

Create a test service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: test-lb
  labels:
    loadbalancer: "enabled"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: test
```

Check if the service gets an external IP:
```bash
kubectl get svc test-lb
```

Verify the route is advertised:
```bash
# On FRR
docker exec frr vtysh -c "show ip bgp"

# Check upstream router for the advertised route
```

## Troubleshooting

### BGP Session Not Establishing

1. Check network namespace:
```bash
ip netns list
ip netns exec cilium ip addr show
```

2. Check veth interfaces:
```bash
ip link show | grep veth
```

3. Check FRR logs:
```bash
docker logs frr
```

4. Check Cilium logs:
```bash
kubectl -n kube-system logs -l k8s-app=cilium | grep -i bgp
```

### Routes Not Being Advertised

1. Verify Cilium BGP advertisements:
```bash
kubectl get ciliumbgpadvertisements -o yaml
```

2. Check if services have the correct labels:
```bash
kubectl get svc -l loadbalancer=enabled
```

3. Verify IP pool assignment:
```bash
kubectl get ciliumloadbalancerippool -o yaml
```

## Advanced Configuration

### IPv6 Support

To enable IPv6 BGP peering, ensure:

1. IPv6 addresses are configured in the config file
2. Cilium has IPv6 enabled in values.yaml
3. BGP advertisements include IPv6 address family
4. IPv6 peers have `address_family: ipv6` set

### Multiple BGP Peers

To add more upstream BGP peers, modify the `neighbors.json` file:

```json
{
  "neighbours": {
    "ipv4": [
      "10.0.0.1",
      "10.0.0.2"
    ],
    "ipv6": [
      "2001:db8::1",
      "2001:db8::2"
    ]
  }
}
```

### Custom Route Maps

Add custom route maps in `frr.conf.j2` for advanced routing policies.

## References

- [Cilium BGP Control Plane Documentation](https://docs.cilium.io/en/stable/network/bgp-control-plane/)
- [FRR Documentation](https://docs.frrouting.org/)
- [Talos System Extensions](https://www.talos.dev/latest/talos-guides/configuration/system-extensions/)