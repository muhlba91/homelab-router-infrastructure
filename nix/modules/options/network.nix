# Vars schema: WAN, LAN, NAT66, public IPv6 prefixes, loopbacks, DHCP.
{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./types.nix { inherit lib; })
    str
    strD
    bool
    nullable
    typed
    ip4
    ip6
    cidr4
    cidr6
    mac
    ;

  reservation4 = types.submodule {
    options = {
      ip = typed ip4 "IPv4 address.";
      mac = typed mac "Hardware address.";
      hostname = str "Hostname.";
    };
  };
  reservation6 = types.submodule {
    options = {
      ip = typed ip6 "IPv6 address.";
      duid = str "Client DUID.";
      hostname = str "Hostname.";
    };
  };
in
{
  options.router = {
    wan = {
      mac = typed mac "MAC of the WAN NIC (NICs are renamed by MAC; a change needs a reboot).";
      iface = strD "wan0" "Name given to the WAN NIC (a change needs a reboot).";
      vlan = nullable (types.ints.between 1 4094) "VLAN id on the WAN NIC (the WAN device then is <iface>.<vlan>; a change needs a reboot).";
      v4 = {
        method = mkOption {
          type = types.enum [
            "static"
            "dhcp"
          ];
          default = "static";
          description = "How the WAN IPv4 address is obtained.";
        };
        address = nullable cidr4 "Address with prefix length (required for `static`).";
        gateway = nullable ip4 "Default gateway (static).";
        announce = bool false ''
          Announce the WAN IPv4 network (static) in BGP and let the other sites reach it,
          masqueraded to the WAN address (e.g. a transfer net to a hypervisor's management).
        '';
      };
      v6 = {
        method = mkOption {
          type = types.enum [
            "static"
            "dhcp6"
            "none"
          ];
          default = "static";
          description = "How the WAN IPv6 address is obtained (dhcp6 also uses RA for the default route).";
        };
        address = nullable cidr6 "Address with prefix length (required for `static`).";
        gateway = nullable ip6 "Default gateway (static).";
        announce = bool false ''
          Announce the WAN IPv6 network (static, ULA) in BGP and let the other sites reach it,
          masqueraded to the WAN address (e.g. a transfer net to a hypervisor's management).
        '';
      };
      shaping.upload = nullable (types.strMatching "[0-9]+[KMG]") ''
        Shape the upload to this rate (CAKE on the WAN device, e.g. `45M`; null = off). Set it
        slightly below the line's real upload rate, so the queue builds here, where CAKE keeps
        latency low under load (bufferbloat), not in the modem. Turning it off later needs a
        reboot or `tc qdisc del dev <wan device> root`: networkd does not remove the qdisc.
      '';
    };

    lan = {
      mac = typed mac "MAC of the LAN NIC (a change needs a reboot).";
      iface = strD "lan0" "Name given to the LAN NIC (a change needs a reboot).";
      v4 = typed cidr4 "Router address with prefix length.";
      v4Net = typed cidr4 "IPv4 network.";
      v6 = typed cidr6 "Router IPv6 address with prefix length.";
      v6Net = typed cidr6 "IPv6 network of the LAN.";
      v6Supernet = typed cidr6 "Prefix covering the LANs behind this router: the NAT66 source range.";
    };

    nat66.enable = bool true "Masquerade IPv6 from v6Supernet to the WAN address (for ULA LANs). Off when the LAN has routable addresses.";

    publicV6 = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            prefix = typed cidr6 "Public prefix owned by the site (e.g. a /56), originated by BGP from a blackhole route.";
            anchor = typed ip6 "Address (/128) on the loopback inside the prefix.";
          };
        }
      );
      default = [ ];
      description = ''
        Site-owned public IPv6 prefixes: each gets an anchor address on the loopback and a
        blackhole route, so BGP can originate it (more-specifics from downstream win).
      '';
    };

    loopbacks = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            address = typed (types.either ip4 ip6) "Host address (/32 or /128) on the loopback.";
            announce = bool true "Originate the address in BGP (needs router.bgp.enable).";
          };
        }
      );
      default = [ ];
      description = ''
        Extra addresses on the loopback, independent of the LAN (e.g. a stable management
        address). Other sites only accept them inside their router.bgp.accept4/6 ranges.
      '';
    };

    dhcp = {
      pool4 = str "IPv4 pool (`a - b`).";
      pool6 = str "IPv6 pool (`a - b`).";
      reservations4 = mkOption {
        type = types.listOf reservation4;
        default = [ ];
        description = "Static DHCPv4 leases.";
      };
      reservations6 = mkOption {
        type = types.listOf reservation6;
        default = [ ];
        description = "Static DHCPv6 leases.";
      };
    };
  };
}
