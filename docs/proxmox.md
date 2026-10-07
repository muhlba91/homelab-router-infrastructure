# Proxmox host for a router VM

A server with a single public IPv4 address (and optionally IPv6) runs Proxmox; the router is a VM behind it and the
edge firewall of the site. The host forwards everything except its own SSH (22) and web UI (8006) to the router.

| Bridge | Ports | Host address | Purpose |
| --- | --- | --- | --- |
| `vmbr0` | physical NIC | public | internet (created by the Proxmox installer) |
| `vmbr1` | none | transfer net | host <-> router WAN; NAT to/from the internet, hairpin |
| `vmbr10` | none | none | VM network behind the router (the router's LAN) |

The host needs no route to the site's networks: the site announces the transfer net
(`network.wan.v4.announce`/`v6.announce`) and masquerades traffic from the mesh into it, so the host only ever sees
the router's address.

## Variables

Set these in the host's shell for the commands below (example values):

```bash
export PUBLIC_IP=203.0.113.10                # the host's public IPv4 address (on vmbr0)
export TRANSFER_HOST=10.255.255.0            # transfer net /31: host side
export TRANSFER_ROUTER=10.255.255.1          #                   router side (the site's network.wan.v4.address)
export TRANSFER6_HOST=fd12:3456:789a::       # optional, IPv6 transfer net /127: host side
export TRANSFER6_ROUTER=fd12:3456:789a::1    #                                  router side (network.wan.v6.address)
export ROUTER_VMID=100
export WAN_MAC=02:00:00:00:00:01             # the site's network.wan.mac
export LAN_MAC=02:00:00:00:00:02             # the site's network.lan.mac
```

## Bridges and NAT

`vmbr0` stays as the installer created it. The NAT rules hang on `vmbr1`, so they exist exactly while the transfer
net does; `post-down` removes them again, so a reload does not stack duplicates.

```bash
cat >> /etc/network/interfaces <<EOF

auto vmbr1
iface vmbr1 inet static
        address ${TRANSFER_HOST}/31
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        # DNAT: everything except the host's SSH and web UI to the router
        post-up   iptables -t nat -A PREROUTING -i vmbr0 -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-up   iptables -t nat -A PREROUTING -i vmbr0 -p udp -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-down iptables -t nat -D PREROUTING -i vmbr0 -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-down iptables -t nat -D PREROUTING -i vmbr0 -p udp -j DNAT --to-destination ${TRANSFER_ROUTER}
        # Hairpin: the router (and the LAN behind its masquerade) reaches its own forwards via the public IP
        post-up   iptables -t nat -A PREROUTING -i vmbr1 -d ${PUBLIC_IP} -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-up   iptables -t nat -A PREROUTING -i vmbr1 -d ${PUBLIC_IP} -p udp -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-down iptables -t nat -D PREROUTING -i vmbr1 -d ${PUBLIC_IP} -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER_ROUTER}
        post-down iptables -t nat -D PREROUTING -i vmbr1 -d ${PUBLIC_IP} -p udp -j DNAT --to-destination ${TRANSFER_ROUTER}
        # SNAT: internet access of the router
        post-up   iptables -t nat -A POSTROUTING -s ${TRANSFER_HOST}/31 -o vmbr0 -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s ${TRANSFER_HOST}/31 -o vmbr0 -j MASQUERADE

auto vmbr10
iface vmbr10 inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        # The host must not configure itself from the router's router advertisements
        post-up sysctl -w net.ipv6.conf.vmbr10.disable_ipv6=1
EOF

cat > /etc/sysctl.d/99-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system
ifreload -a
```

Check: `iptables -t nat -S` lists the five rules once.

### IPv6 (optional)

With a single public IPv6 address, IPv6 works like IPv4: NAT66 to the router's (ULA) WAN address (ICMPv6 stays
with the host):

```bash
cat >> /etc/network/interfaces <<EOF

iface vmbr1 inet6 static
        address ${TRANSFER6_HOST}/127
        post-up   ip6tables -t nat -A PREROUTING -i vmbr0 -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER6_ROUTER}
        post-up   ip6tables -t nat -A PREROUTING -i vmbr0 -p udp -j DNAT --to-destination ${TRANSFER6_ROUTER}
        post-down ip6tables -t nat -D PREROUTING -i vmbr0 -p tcp -m multiport ! --dports 22,8006 -j DNAT --to-destination ${TRANSFER6_ROUTER}
        post-down ip6tables -t nat -D PREROUTING -i vmbr0 -p udp -j DNAT --to-destination ${TRANSFER6_ROUTER}
        post-up   ip6tables -t nat -A POSTROUTING -s ${TRANSFER6_HOST}/127 -o vmbr0 -j MASQUERADE
        post-down ip6tables -t nat -D POSTROUTING -s ${TRANSFER6_HOST}/127 -o vmbr0 -j MASQUERADE
EOF
ifreload -a
```

With a public prefix of its own for the site, route it to the router instead of NAT
(`ip -6 route add <prefix> via ${TRANSFER6_ROUTER}`). If the provider treats that prefix as on-link (no route to
the host), the host must also answer neighbor solicitations for it (`ndppd`).

## Router VM

| Setting | Value | Why |
| --- | --- | --- |
| `machine` | `q35` | PCIe chipset (the default `i440fx` is legacy PCI): virtio devices on PCIe, passthrough works, the ICH9 watchdog (`iTCO_wdt`) is built in for the site's `system.watchdog` |
| `bios` | `seabios` or `ovmf` | the `qemu` profile boots with either (GRUB for BIOS and UEFI); OVMF needs an EFI disk with `pre-enrolled-keys=0` (Secure Boot off); switching needs no reinstall |
| `cpu` | `host` | all host CPU features (crypto, vector instructions for WireGuard/VXLAN) |
| `memory` / `balloon` | `2048` / `0` | CrowdSec and the build on the router need ~1 GB; no ballooning |
| `net0` / `net1` | `virtio`, the site's MACs, `queues` = cores | the router names its NICs by MAC; multiqueue spreads packet processing over the vCPUs |
| `scsihw` / disk | `virtio-scsi-single`, `iothread=1`, `discard=on`, `ssd=1` | the site's `hardware.disk` is `/dev/sda` |
| `agent` | `1` | the profile runs the QEMU guest agent (clean shutdown, IP display) |

```bash
qm set "$ROUTER_VMID" --machine q35 --cpu host --memory 2048 --balloon 0 --agent 1 --onboot 1 --startup order=1
qm set "$ROUTER_VMID" --net0 "virtio=${WAN_MAC},bridge=vmbr1,queues=2" --net1 "virtio=${LAN_MAC},bridge=vmbr10,queues=2"
```

`machine` and `bios` apply after a full stop and start of the VM. Further VMs of the site attach to `vmbr10` only.

## First install

`./router install` (from `nix/` on the workstation) needs plain SSH to the installer: port 22 of the public IP is
forwarded to it during the install. New connections to the host's own SSH fail meanwhile: keep a session open or use
the web UI (8006).

1. On the host: the VM settings above, plus 3 GiB RAM for the install (the partitioning runs in the installer's RAM),
   the NixOS minimal ISO and the boot order disk first (an empty disk falls through to the ISO; after the install the
   disk boots). Reusing a VM (e.g. the old router): back it up and snapshot it first; its disk still boots, so press
   `Esc` in the console at power-on and pick the CD-ROM once.

   ```bash
   wget -P /var/lib/vz/template/iso https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso   # the release of nix/flake.nix
   vzdump "$ROUTER_VMID" --mode stop --compress zstd --storage local   # reused VM only
   qm snapshot "$ROUTER_VMID" pre-nixos                                # reused VM only
   qm set "$ROUTER_VMID" --memory 3072 --ide2 local:iso/latest-nixos-minimal-x86_64-linux.iso,media=cdrom --boot order='scsi0;ide2'
   iptables -t nat -I PREROUTING 1 -i vmbr0 -p tcp --dport 22 -j DNAT --to-destination "$TRANSFER_ROUTER"
   qm start "$ROUTER_VMID"
   ```

2. In the VM's console (user `nixos`; no paste, so short commands; the WAN NIC is the one with the site's WAN MAC,
   `ip -br link`, usually `ens18`):

   ```bash
   passwd                       # temporary password, only for copying the key
   sudo -i
   ip addr add <TRANSFER_ROUTER>/31 dev ens18 && ip route add default via <TRANSFER_HOST>
   echo 'nameserver 9.9.9.10' > /etc/resolv.conf
   systemctl start sshd
   ```

3. On the workstation (in `nix/`): copy the site's deploy key to `root` (asks for the temporary password), then
   install (wipes the disk, reboots into the router):

   ```bash
   ssh-keygen -y -f ../infrastructure/outputs/keys/<site>/deploy-key | ssh -o StrictHostKeyChecking=no \
     -o UserKnownHostsFile=/dev/null nixos@<PUBLIC_IP> 'sudo mkdir -p /root/.ssh && sudo tee /root/.ssh/authorized_keys'
   ./router install <site> <PUBLIC_IP>
   ```

4. On the host: remove the forward, the ISO and the extra RAM (the RAM applies at the next full stop and start):

   ```bash
   iptables -t nat -D PREROUTING -i vmbr0 -p tcp --dport 22 -j DNAT --to-destination "$TRANSFER_ROUTER"
   qm set "$ROUTER_VMID" --ide2 none --boot order=scsi0 --memory 2048
   ```

5. Validate the router: [validation.md](validation.md) (including a full stop and start).

The router comes up with its pinned SSH host key, its secrets and NetBird enrolled. Rollback of a reused VM:
`qm rollback "$ROUTER_VMID" pre-nixos && qm start "$ROUTER_VMID"`. Once the router has run for a while, delete the
snapshot (`qm delsnapshot "$ROUTER_VMID" pre-nixos`) and the backup (`pvesm list local --content backup`, then
`pvesm free <volid>`).

Interactive SSH through the host as jump host (works if the transfer net is a trusted network on the WAN,
`network.trustedNetworks.wan`):

```bash
ssh -J "root@${PUBLIC_IP}" "deploy@${TRANSFER_ROUTER}"
```
