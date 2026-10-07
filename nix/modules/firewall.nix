# Firewall (nftables). Zones: lan, wan, mesh (routed in from other sites: the EVPN devices)
# and trusted (sources in trusted.v4/v6; on the WAN only with trusted.onWan). Contents:
# services on the router (defaults below), rules generated from the features, port
# forwards, the announced WAN nets, reply-to on the WAN, NAT44/NAT66 and the drop log.
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router;
  d = cfg.derived;
  nb = cfg.transport.netbird;
  ev = cfg.evpn;
  inherit (rlib) nftSet quote isV6;
  # The WAN networks other sites may reach (router.wan.v4/v6.announce), else null.
  wanNet = if cfg.wan.v4.announce then rlib.network4 cfg.wan.v4.address else null;
  wanNet6 = if cfg.wan.v6.announce then rlib.network6 cfg.wan.v6.address else null;
  # Trusted sources count on the WAN only where it is a private network of ours.
  notWan = lib.optionalString (!cfg.trusted.onWan) ''iifname != "${wanIf}" '';

  inherit (d) wanIf lanIf;
  meshIfs = cfg.mesh.interfaces; # set by modules/evpn.nix
  hasMesh = meshIfs != [ ];
  meshSet = nftSet (quote meshIfs);

  # BGP neighbors by address family of the neighbor *address* (none while BGP is off).
  peers = lib.optionals cfg.bgp.enable cfg.bgp.peers;
  bgpPeers4 = map (p: p.address) (lib.filter (p: !(isV6 p.address)) peers);
  bgpPeers6 = map (p: p.address) (lib.filter (p: isV6 p.address) peers);
  anyBfd = lib.any (p: p.bfd) peers;
  replyMark = "0x${lib.toHexString d.wanReply.mark}";
  # Last rule before the drop policy: what is left from the WAN is dropped, rate-limited log.
  ld = cfg.firewall.logDrops;
  logDrop =
    chain:
    lib.optionalString ld.enable ''iifname "${wanIf}" limit rate ${ld.rate} burst ${toString ld.burst} packets log prefix "nft-drop-${chain}: " level info'';

  # Services: one commented rule group per name, one rule per zone (trusted: v4 + v6).
  zoneMatch = {
    lan = [ ''iifname "${lanIf}"'' ];
    mesh = lib.optional hasMesh "iifname ${meshSet}";
    trusted = [
      "${notWan}ip saddr @trusted4"
      "${notWan}ip6 saddr @trusted6"
    ];
    wan = [ ''iifname "${wanIf}"'' ];
  };
  portSet = s: nftSet (map toString s.ports);
  l4 =
    s:
    if s.proto == "both" then
      "meta l4proto { tcp, udp } th dport ${portSet s}"
    else
      "${s.proto} dport ${portSet s}";
  serviceRules = lib.concatStringsSep "\n  " (
    lib.mapAttrsToList (
      name: s:
      lib.concatStringsSep "\n  " (
        [ "# ${name}: ${s.proto} ${portSet s} from ${lib.concatStringsSep ", " s.from}" ]
        ++ map (m: "${m} ${l4 s} accept") (lib.concatMap (z: zoneMatch.${z}) s.from)
      )
    ) (lib.filterAttrs (_: s: s.enable) cfg.firewall.services)
  );
  siteRules =
    opt:
    lib.optionalString (cfg.firewall.${opt} != "") ''
      # Site rules (router.firewall.${opt})
      ${cfg.firewall.${opt}}
    '';
  service =
    proto: ports: from:
    lib.mapAttrs (_: lib.mkDefault) { inherit proto ports from; };
  # DNAT rules of router.firewall.forwards.v4/v6 (same shape; `saddr` = ip or ip6).
  dnatRules =
    saddr:
    lib.concatMapStringsSep "\n        " (
      f:
      ''iifname "${wanIf}" ${
        lib.optionalString (f.from != null) "${saddr} saddr ${nftSet f.from} "
      }${f.proto} dport ${nftSet (map toString f.ports)} dnat to ${f.to}''
    );
in
{
  assertions = [
    {
      assertion = cfg.firewall.forwards.v6 == [ ] || cfg.nat66.enable;
      message = "router.firewall.forwards.v6 needs router.nat66.enable (a routable LAN needs no DNAT: firewall.extraForwardRules)";
    }
    {
      assertion = !cfg.wan.v4.announce || (cfg.wan.v4.method == "static" && cfg.wan.v4.address != null);
      message = "router.wan.v4.announce needs a static WAN IPv4 address";
    }
    {
      assertion =
        !cfg.wan.v6.announce
        || (
          cfg.wan.v6.method == "static"
          && cfg.wan.v6.address != null
          && builtins.match "f[cd].*" (lib.toLower cfg.wan.v6.address) != null
        );
      message = "router.wan.v6.announce needs a static WAN IPv6 ULA address (fc00::/7)";
    }
  ];

  # Default services (ports from the service modules); a site overrides single fields or
  # disables one in its vars.
  router.firewall.services = {
    dhcp = service "udp" [ 67 547 ] [ "lan" ]; # Kea (v4 + v6)
    dns = service "both" [ config.services.adguardhome.settings.dns.port ] [ "lan" "mesh" "trusted" ];
    dns-ui = service "tcp" [ config.services.adguardhome.port ] [ "lan" "trusted" ]; # AdGuard web UI/API
    ntp = service "udp" [ 123 ] [ "lan" ]; # chrony
    ssh = service "tcp" config.services.openssh.ports [
      "lan"
      "trusted"
    ];
  };

  networking.nftables.enable = true;
  # A reload must leave foreign tables alone (NetBird's own tables, see
  # transport.netbird.enforcePolicies). Ours are all `networking.nftables.tables`: each
  # deletes and recreates itself.
  networking.nftables.flushRuleset = false;

  # Port forwards live in the nat table; `ct status dnat` lets them through.
  networking.nftables.tables.router = {
    family = "inet";
    content = ''
      set trusted4 { type ipv4_addr; flags interval; elements = ${nftSet cfg.trusted.v4} }
      set trusted6 { type ipv6_addr; flags interval; elements = ${nftSet cfg.trusted.v6} }
      ${lib.optionalString (
        bgpPeers4 != [ ]
      ) "set bgp_peers4 { type ipv4_addr; elements = ${nftSet bgpPeers4} }"}
      ${lib.optionalString (
        bgpPeers6 != [ ]
      ) "set bgp_peers6 { type ipv6_addr; elements = ${nftSet bgpPeers6} }"}

      chain input {
        type filter hook input priority filter; policy drop;
        ct state vmap { established : accept, related : accept, invalid : drop }
        iifname "lo" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Services (router.firewall.services)
        ${serviceRules}

        # Infrastructure (generated from the features)
        ${lib.optionalString (cfg.wan.v6.method == "dhcp6") ''
          # DHCPv6 client: the server answers from its link-local to our 546, while our request
          # went to a multicast group, so conntrack does not match the reply
          iifname "${wanIf}" ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept
        ''}
        ${lib.optionalString nb.enable ''
          # NetBird underlay: WireGuard from anywhere but the mesh (no tunnel through itself)
          ${lib.optionalString hasMesh "iifname != ${meshSet} "}udp dport ${toString nb.port} accept
        ''}
        # BGP only from the configured neighbours
        ${lib.optionalString (bgpPeers4 != [ ]) "ip saddr @bgp_peers4 tcp dport 179 accept"}
        ${lib.optionalString (bgpPeers6 != [ ]) "ip6 saddr @bgp_peers6 tcp dport 179 accept"}
        ${lib.optionalString (
          anyBfd && bgpPeers4 != [ ]
        ) "ip saddr @bgp_peers4 udp dport { 3784, 4784 } accept # BFD"}
        ${lib.optionalString (
          anyBfd && bgpPeers6 != [ ]
        ) "ip6 saddr @bgp_peers6 udp dport { 3784, 4784 } accept # BFD"}
        ${lib.optionalString ev.enable ''
          # EVPN: VXLAN only through the overlay, from its range (with enforcePolicies NetBird's
          # policies decide first). BGP to the hub is our outgoing session (the hub only listens).
          iifname "${nb.iface}" ip saddr ${ev.underlay4} udp dport 4789 accept
        ''}
        ${siteRules "extraInputRules"}
        ${logDrop "in"}
      }

      # Reply-to (routes: networking.nix): connections arriving on the WAN get a ct mark bit,
      # their packets from elsewhere (LAN replies, our own) the packet mark -> WAN table.
      chain wan_reply_pre {
        type filter hook prerouting priority mangle; policy accept;
        iifname "${wanIf}" ct state new ct mark set ct mark or ${replyMark}
        iifname != "${wanIf}" ct mark and ${replyMark} == ${replyMark} meta mark set meta mark or ${replyMark}
      }
      chain wan_reply_out {
        type route hook output priority mangle; policy accept;
        ct mark and ${replyMark} == ${replyMark} meta mark set meta mark or ${replyMark}
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state vmap { established : accept, related : accept, invalid : drop }
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        iifname "${lanIf}" accept                       # lan -> anywhere
        ${lib.optionalString hasMesh ''
          # TCP MSS follows the path MTU of the mesh (VXLAN 1370 < 1500), both directions
          oifname ${meshSet} tcp flags syn tcp option maxseg size set rt mtu
          iifname ${meshSet} oifname "${lanIf}" accept  # mesh -> lan (spoke: no transit)
        ''}
        ${lib.optionalString (hasMesh && wanNet != null) ''
          iifname ${meshSet} oifname "${wanIf}" ip daddr ${wanNet} accept  # mesh -> announced WAN net
        ''}
        ${lib.optionalString (hasMesh && wanNet6 != null) ''
          iifname ${meshSet} oifname "${wanIf}" ip6 daddr ${wanNet6} accept  # mesh -> announced WAN net
        ''}
        ct status dnat accept                           # port forwards
        ${lib.optionalString cfg.trusted.onWan ''
          iifname "${wanIf}" oifname "${lanIf}" ip saddr @trusted4 accept
          iifname "${wanIf}" oifname "${lanIf}" ip6 saddr @trusted6 accept
        ''}
        ${siteRules "extraForwardRules"}
        ${logDrop "fwd"}
      }
    '';
  };

  networking.nftables.tables.nat4 = {
    family = "ip";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ${dnatRules "ip" cfg.firewall.forwards.v4}
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ${lib.optionalString (wanNet != null) ''
          # The announced WAN net sees every site as the WAN address
          oifname "${wanIf}" ip daddr ${wanNet} masquerade
        ''}
        # Internet-bound only; our other networks (trusted.v4) are routed, not NATed.
        oifname "${wanIf}" ip saddr ${cfg.lan.v4Net} ip daddr != ${nftSet cfg.trusted.v4} masquerade
      }
    '';
  };

  # NAT66: a ULA LAN reaches the IPv6 internet through the WAN address; trusted.v6 is
  # routed, never NATed. Port forwards and the announced WAN net work as for IPv4.
  networking.nftables.tables.nat6 = lib.mkIf (cfg.nat66.enable || wanNet6 != null) {
    family = "ip6";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ${dnatRules "ip6" cfg.firewall.forwards.v6}
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ${lib.optionalString (wanNet6 != null) ''
          oifname "${wanIf}" ip6 daddr ${wanNet6} masquerade
        ''}
        ${lib.optionalString cfg.nat66.enable ''
          oifname "${wanIf}" ip6 saddr ${cfg.lan.v6Supernet} ip6 daddr != ${nftSet cfg.trusted.v6} masquerade
        ''}
      }
    '';
  };
}
