# From a public LAN IPv6 prefix to ULA + NAT66

A LAN with a public IPv6 prefix needs no NAT. When the provider ends that prefix, the LAN moves to a ULA prefix and the
router translates (NAT66): its WAN address stays the only public one, and services are reached by port forwards.
Changes in the site file (example values; use a generated `fd` /48 of your own):

```yaml
network:
  lan:
    v6:
      address: "fd00:db8:1::1"
      netmask: 48
      network: "fd00:db8:1::"
      public: false                       # NAT66 instead of routing
      supernet: "fd00:db8:1::/48"
dhcp:
  v6:
    start: "fd00:db8:1:1::1"
    end: "fd00:db8:1:1::ffff"
firewall:
  forwards:
    v6:                                   # one entry per service, `to` inside the supernet
      - proto: tcp
        ports: [80, 443]
        to: "fd00:db8:1::10"
```

- Remove `firewall.extraForwardRules` rules that accepted the old public destinations: forwards.v6 opens what is needed.
- BGP neighbors with an address in the old prefix (a cluster on the LAN) move to their new ULA address.
- Announce the ULA through the mesh only if other sites must reach it (`additionalRoutableNetworks`).
- Check afterwards: [validation.md](validation.md) sections 4 to 6, and a connection from the internet to each forward.
