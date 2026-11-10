# Vars schema: the firewall (port forwards, the services on the router, raw rules, the
# drop log).
{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./types.nix { inherit lib; })
    bool
    nullable
    typed
    typedD
    ip4
    ip6
    cidr4
    cidr6
    ;

  # Port forward; `addr`/`net` are the address types of the family, `toDesc` describes `to`.
  forward =
    {
      addr,
      net,
      toDesc,
    }:
    types.submodule {
      options = {
        proto = mkOption {
          type = types.enum [
            "tcp"
            "udp"
          ];
          description = "Protocol.";
        };
        ports = mkOption {
          type = types.listOf types.port;
          description = "Ports on the WAN address.";
        };
        to = typed addr toDesc;
        from = nullable (types.listOf (types.either addr net)) "Source addresses/networks allowed to use the forward; null = everyone.";
      };
    };
  forward4 = forward {
    addr = ip4;
    net = cidr4;
    toDesc = "Internal destination address.";
  };
  forward6 = forward {
    addr = ip6;
    net = cidr6;
    toDesc = "Internal destination address (inside lan.v6Supernet, i.e. behind NAT66).";
  };

  service = types.submodule {
    options = {
      enable = bool true "Open this service.";
      proto = mkOption {
        type = types.enum [
          "tcp"
          "udp"
          "both"
        ];
        description = "Protocol (`both` = TCP and UDP).";
      };
      ports = mkOption {
        type = types.listOf types.port;
        description = "Ports on the router.";
      };
      from = mkOption {
        type = types.listOf (
          types.enum [
            "lan"
            "mesh"
            "trusted"
            "wan"
          ]
        );
        description = "Who may connect: `lan` (the LAN interface), `mesh` (routed in from other sites, EVPN), `trusted` (sources in trusted.v4/v6; on the WAN only with trusted.onWan), `wan` (everyone on the WAN interface, i.e. the internet).";
      };
    };
  };
in
{
  options.router = {
    firewall = {
      forwards = {
        v4 = mkOption {
          type = types.listOf forward4;
          default = [ ];
          description = "DNAT port forwards from the WAN address (open to everyone unless `from` is set).";
        };
        v6 = mkOption {
          type = types.listOf forward6;
          default = [ ];
          description = ''
            DNAT port forwards from the WAN IPv6 address to a LAN host, the IPv6 counterpart of
            forwards.v4 for a ULA LAN behind NAT66 (needs nat66.enable; a routable LAN needs no
            DNAT, only a forward rule: firewall.extraForwardRules).
          '';
        };
      };
      services = mkOption {
        type = types.attrsOf service;
        default = { };
        description = ''
          Services on the router (input chain). The input policy is drop, so only these (plus
          the rules generated from the features) are reachable; a service accepts every client
          of its `from` zones. Defaults: `dhcp`, `ntp` (lan), `dns` (lan, mesh, trusted),
          `dns-ui`, `ssh` (lan, trusted); `metrics` (lan, trusted) comes from the monitoring
          module when Prometheus exporters are enabled and `nut` (lan) from the UPS module.
          A site overrides single fields (`services.ssh.from = [ "lan" ];`), disables one
          (`enable = false`) or adds its own. Rules for NetBird, BGP, VXLAN and the DHCPv6
          client are generated from the features.
        '';
      };
      extraInputRules = mkOption {
        type = types.lines;
        default = "";
        description = "Raw nftables rules at the end of the input chain (before the drop policy).";
      };
      logDrops = {
        enable = bool true ''
          Log new connections from the WAN that the input and forward chains drop (kernel log,
          prefix `nft-drop-in: `/`nft-drop-fwd: `), e.g. for CrowdSec and log shipping.
        '';
        rate = typedD (types.strMatching "[0-9]+/(second|minute|hour)") "5/second" ''
          Rate limit of the drop log, per chain; internet background noise would flood the log
          otherwise.
        '';
        burst = typedD types.ints.positive 20 "Burst (packets) of the drop log's rate limit.";
      };
      icmpEchoRate = typedD (types.strMatching "[0-9]+/(second|minute|hour)") "10/second" ''
        Rate limit of ICMP/ICMPv6 echo requests arriving on the WAN, per source address;
        faster ones are dropped. Other ICMP types and all non-WAN interfaces are not limited.
      '';
      extraForwardRules = mkOption {
        type = types.lines;
        default = "";
        description = "Raw nftables rules at the end of the forward chain (before the drop policy).";
      };
    };
  };
}
