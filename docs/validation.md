# Router validation

Run after a first install, a migration or a risky change, from `nix/` (site data as for `./router deploy`). Each check
shows what a healthy router returns. Placeholders: `<site>`, `<LAN_V4>` (the site's LAN address), `<REMOTE>` (a LAN
address of another site), `<PUBLIC_IP>`.

## 1. Health

```bash
./router health <site>
```

`ok bgp: n/n established`, `ok failed units: 0`, no pending-reboot warning.

## 2. NetBird (sites with NetBird)

```bash
./router ssh <site> sudo netbird-backbone status -d
```

The hub and every other site `Connected`, `Connection type: P2P`. `Relayed` works but is slower: UDP 51820 does not
reach the router (firewall or NAT in front of it).

## 3. EVPN (sites with EVPN)

```bash
./router ssh <site> "sudo vtysh -c 'show bgp l2vpn evpn summary'"
./router ssh <site> "sudo vtysh -c 'show bgp l2vpn evpn route type prefix self-originate'"
./router ssh <site> "ip -4 route show proto bgp | grep -vc 'src <LAN_V4>'; ip -6 route show proto bgp | wc -l; ip nexthop"
```

- `hub-evpn` established, prefixes received (the other sites).
- Self-originated: exactly the site's own prefixes (LAN, announced WAN nets, public prefixes, loopbacks).
- `0` IPv4 routes without the LAN address as source, more than `0` IPv6 routes, no nexthop objects.

## 4. Traffic from the router

```bash
./router ssh <site> "ping -c2 <REMOTE>; ping -c2 1.1.1.1"
./router ssh <site> "dig +short @127.0.0.1 nixos.org; dig +short @127.0.0.1 <host>.<other site's domain>"
```

Both pings answer; both names resolve (the second through a conditional forward). The AdGuard UI needs a login:
`curl -s -o /dev/null -w '%{http_code}' http://<LAN_V4>:3000/control/status` answers `401`.

## 5. From outside the site

- From another site: `ping <LAN_V4>`; LAN hosts answer as well.
- An announced WAN net (`network.wan.v4.announce`): its gateway answers from another site, e.g. `ssh root@<gateway>`.
- From the internet: only the site's forwards answer (`nc -vz <PUBLIC_IP> <port>`), everything else times out.

## 6. LAN clients (sites with clients)

On a client: a DHCPv4 and DHCPv6 lease, `ping 1.1.1.1` (NAT), `ping <REMOTE>` (routed, no NAT), `dig <name>` (the
router's DNS).

## 7. Reboot

A full stop and start of the VM (it also applies changed VM hardware) or `./router ssh <site> sudo systemctl reboot`,
then sections 1-3 again: the router is back within a minute.

Keep the rollback of a migration (VM snapshot, the old hub link) until the router has run for a while without
findings.
