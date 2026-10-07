# EVPN/L3VNI over the NetBird underlay: the hub is the only BGP neighbor and reflects the
# routes of all sites (type-5); traffic goes site-to-site directly over the overlay.
# VRF `mesh` carries only the L3VNI; the LAN and all services stay in the default VRF and
# FRR leaks routes both ways (modules/bgp.nix). Devices: VRF <- bridge (router MAC) <- VXLAN.
# The VXLAN's local address is our NetBird overlay IP, which only exists after the first
# enrollment: networkd builds VRF + bridge, a small unit creates/updates the VXLAN device
# from wt0's address and keeps its settings (timer: also heals a re-enrollment).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.router;
  ev = cfg.evpn;
  inherit (cfg.derived) evpnBridge evpnVxlan evpnRmac;
  wt = cfg.transport.netbird.iface;
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
  };
}
