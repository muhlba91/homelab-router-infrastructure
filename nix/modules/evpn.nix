# EVPN/L3VNI over the NetBird underlay: the hub is the only BGP neighbor and reflects the
# routes of all sites (type-5); traffic goes site-to-site directly over the overlay.
# VRF `mesh` carries only the L3VNI; the LAN and all services stay in the default VRF and
# FRR leaks routes both ways (modules/bgp.nix). Devices: VRF <- bridge (router MAC) <- VXLAN.
# The VXLAN's local address is our NetBird overlay IP, which only exists after the first
# enrollment: networkd builds VRF + bridge, a small unit creates/updates the VXLAN device
# from wt0's address and keeps its settings (timer: also heals a re-enrollment).
# Egress: sources of the public prefixes use the hub's default route in the mesh table (policy
# rules), after the specific routes of the main table.
{
  config,
  lib,
  pkgs,
  rlib,
  ...
}:
let
  cfg = config.router;
  ev = cfg.evpn;
  inherit (cfg.derived) evpnBridge evpnVxlan evpnRmac;
  wt = cfg.transport.netbird.iface;
  # Whether an egress source lies inside a prefix of the site.
  ownSource = s: lib.any (p: rlib.within6 p.prefix s) cfg.publicV6;
in
{
  config = lib.mkIf ev.enable {
    assertions = [
      {
        assertion = cfg.transport.netbird.enable;
        message = "router.evpn needs router.transport.netbird (the VXLAN runs over the overlay)";
      }
      {
        assertion = ev.mtu <= cfg.transport.netbird.mtu - 50;
        message = "router.evpn.mtu must be at most router.transport.netbird.mtu - 50 (VXLAN overhead)";
      }
      {
        assertion = cfg.bgp.enable;
        message = "router.evpn needs router.bgp.enable (the routes are exchanged with the hub over BGP)";
      }
      {
        assertion = !ev.egress.enable || ev.egress.sources != [ ];
        message = "router.evpn.egress needs sources (router.publicV6 is empty)";
      }
      {
        assertion = !ev.egress.enable || lib.all ownSource ev.egress.sources;
        message = "router.evpn.egress.sources must lie inside router.publicV6 (other sources are not ours)";
      }
      {
        assertion = !ev.egress.enable || !lib.elem "::/0" cfg.bgp.accept6;
        message = "router.bgp.accept6 must not contain ::/0 with router.evpn.egress (the hub's default route would replace the site's)";
      }
    ];

    boot.kernelModules = [
      "vrf"
      "vxlan"
    ];
    boot.kernel.sysctl = {
      # Traffic from other sites reaches the router's own addresses through the VRF
      # device; sockets of the default VRF (sshd, AdGuard, ...) accept it only with these.
      "net.ipv4.tcp_l3mdev_accept" = 1;
      "net.ipv4.udp_l3mdev_accept" = 1;
    };

    systemd.network.netdevs."40-${ev.vrf}" = {
      netdevConfig = {
        Kind = "vrf";
        Name = ev.vrf;
      };
      vrfConfig.Table = ev.table;
    };
    systemd.network.networks."40-${ev.vrf}" = {
      matchConfig.Name = ev.vrf;
      linkConfig.RequiredForOnline = "no";
      # Egress: the specific routes of the main table first (the LAN, the other sites), then
      # the default route of the mesh table (the hub); without one, the site's default route.
      routingPolicyRules = lib.optionals ev.egress.enable (
        lib.concatMap (source: [
          {
            Family = "ipv6";
            From = source;
            Table = "main";
            SuppressPrefixLength = 0;
            Priority = 500;
          }
          {
            Family = "ipv6";
            From = source;
            Table = ev.table;
            Priority = 501;
          }
        ]) ev.egress.sources
      );
    };
    systemd.network.netdevs."41-${evpnBridge}" = {
      netdevConfig = {
        Kind = "bridge";
        Name = evpnBridge;
        MACAddress = evpnRmac;
        MTUBytes = toString ev.mtu;
      };
      bridgeConfig = {
        STP = false;
        ForwardDelaySec = 0;
      };
    };
    systemd.network.networks."41-${evpnBridge}" = {
      matchConfig.Name = evpnBridge;
      networkConfig = {
        VRF = ev.vrf;
        LinkLocalAddressing = "no";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "no";
    };

    router.mesh.interfaces = [
      evpnBridge
      ev.vrf
    ];

    systemd.services.evpn-vtep = {
      description = "VXLAN ${evpnVxlan} with the NetBird overlay IP as local VTEP";
      after = [
        "systemd-networkd.service"
        "netbird-backbone.service"
      ];
      wants = [ "netbird-backbone.service" ];
      path = [ pkgs.iproute2 ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        set -- $(ip -4 -o addr show dev ${wt} 2>/dev/null) ""
        vtep=''${4:-}
        vtep=''${vtep%/*}
        # Not ready yet (e.g. NetBird restarting): the timer retries.
        [ -n "$vtep" ] || { echo "${wt} has no IPv4 address yet"; exit 0; }
        ip link show ${evpnBridge} >/dev/null 2>&1 || { echo "${evpnBridge} missing"; exit 1; }
        if ip link show ${evpnVxlan} >/dev/null 2>&1; then
          case "$(ip -d -o link show ${evpnVxlan})" in
            *" local $vtep "*) ;;
            *)
              echo "VTEP changed: re-creating ${evpnVxlan} with local $vtep"
              ip link del ${evpnVxlan}
              ;;
          esac
        fi
        if ! ip link show ${evpnVxlan} >/dev/null 2>&1; then
          ip link add ${evpnVxlan} type vxlan id ${toString ev.vni} local "$vtep" dstport 4789 nolearning
          ip link set ${evpnVxlan} addrgenmode none
          echo "${evpnVxlan}: local $vtep"
        fi
        # Every run: a changed configuration also reaches an existing device.
        ip link set ${evpnVxlan} master ${evpnBridge} mtu ${toString ev.mtu}
        ip link set ${evpnVxlan} type bridge_slave neigh_suppress on learning off
        ip link set ${evpnVxlan} up
      '';
    };
    systemd.timers.evpn-vtep = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15s";
        OnUnitActiveSec = "1min";
      };
    };

    # Recovery of a NetBird client that stays in `Connecting` after its server was down: it
    # keeps sending offers and never reconnects. The hub session lost for `after` minutes
    # while the hub's overlay address does not answer means the tunnel is dead (a ping that
    # works with BGP down is not NetBird's fault: no restart). State lives in /run.
    systemd.services.evpn-recovery = lib.mkIf ev.recovery.enable {
      description = "Restart the NetBird client when the hub stays unreachable";
      after = [ "frr.service" ];
      path = [
        pkgs.coreutils
        pkgs.frr
        pkgs.iputils
        pkgs.jq
        pkgs.systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "evpn-recovery";
        RuntimeDirectoryPreserve = "yes";
      };
      script = ''
        set -eu
        dir=/run/evpn-recovery
        now=$(date +%s)
        state=$(vtysh -c "show bgp neighbors ${ev.hubVtep} json" 2>/dev/null \
          | jq -r '[.[] | .bgpState?][0] // empty' || true)
        # FRR not answering is not a NetBird problem.
        [ -n "$state" ] || exit 0
        if [ "$state" = Established ] || ping -c 2 -W 2 ${ev.hubVtep} >/dev/null 2>&1; then
          rm -f "$dir/down"
          exit 0
        fi
        [ -e "$dir/down" ] || echo "$now" > "$dir/down"
        down=$(cat "$dir/down")
        [ $((now - down)) -ge ${toString (ev.recovery.after * 60)} ] || exit 0
        last=$(cat "$dir/restart" 2>/dev/null || echo 0)
        [ $((now - last)) -ge ${toString (ev.recovery.cooldown * 60)} ] || exit 0
        echo "hub ${ev.hubVtep} ($state) lost for $(( (now - down) / 60 )) min, no ping answer: restarting netbird-backbone"
        echo "$now" > "$dir/restart"
        systemctl restart netbird-backbone.service
      '';
    };
    systemd.timers.evpn-recovery = lib.mkIf ev.recovery.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1min";
      };
    };
  };
}
