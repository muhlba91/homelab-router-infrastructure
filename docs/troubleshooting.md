# Troubleshooting

The healthy state is described in [validation.md](validation.md). This page lists failures by symptom. Router commands
run from `nix/`.

## DHCPv6 clients get no answer after a boot

Kea DHCPv6 can start without its socket on 547 and then runs without answering anyone.

- Check: `ss -ulnp | grep -E ':(67|547)\b'` and `journalctl -u kea-dhcp6-server -b`.
- Fix: restart `kea-dhcp6-server`. `service-sockets-max-retries` in `nix/modules/dhcp.nix` prevents the failure on
  later boots.

## BGP session is not `Established`

`./router health <site>` shows the sessions; for the details: `./router ssh <site> "sudo vtysh -c 'show bgp summary'"`.

- `Active` or `Connect`: no TCP session. The peer is unreachable or not listening: test the address (`ping -6`) and
  TCP 179.
- `Idle`: the peer reset the session. See the reset reason in `show bgp neighbors <peer>`.

## Two clients get the same DHCPv6 DUID

A cloned VM keeps its machine-id. Reset it (`sudo rm /etc/machine-id && sudo systemd-machine-id-setup`) and reboot, or
create a fresh VM.
