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

  forward4 = types.submodule {
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
      to = typed ip4 "Internal destination address.";
      from = nullable (types.listOf (types.either ip4 cidr4)) "Source addresses/networks allowed to use the forward; null = everyone.";
    };
  };
  forward6 = types.submodule {
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
      to = typed ip6 "Internal destination address (inside lan.v6Supernet, i.e. behind NAT66).";
      from = nullable (types.listOf (types.either ip6 cidr6)) "Source addresses/networks allowed to use the forward; null = everyone.";
    };
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
          Services on the router (input chain), the only gate: the services accept every
          client. Defaults: `dhcp`, `ntp` (lan), `dns` (lan, mesh, trusted), `dns-ui`, `ssh`
          (lan, trusted), `metrics` (lan, trusted; with monitoring), `nut` (lan; with a UPS).
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
      extraForwardRules = mkOption {
        type = types.lines;
        default = "";
        description = "Raw nftables rules at the end of the forward chain (before the drop policy).";
      };
    };
  };
}
