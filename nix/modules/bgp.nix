# Routing: BGP (FRR).
# * Own prefixes: originate4/6, publicV6, announced loopbacks and WAN nets.
# * Policy, strict by default: announce only own prefixes (PEER-OUT); accept only
#   accept4/6 and never own prefixes or their more-specifics (PEER-IN). Per neighbor
#   inPolicy/outPolicy can be allow-all or deny-all.
# * EVPN (devices: evpn.nix): iBGP l2vpn-evpn to the hub. Own prefixes are leaked into the
#   L3VNI VRF (MESH-OUT), remote ones out of it (PEER-IN, never the NetBird underlay).
#   Leaked IPv4 routes get the LAN address as source (SRC4): their device has no address
#   of the default VRF. IPv6 cannot (the kernel takes the source only from the route's
#   device), so the router's own IPv6 traffic to other sites needs one (e.g. ping -I).
# * Transit (peer.transit): accepted routes get a marker (large community ASN:0:1) and pass
#   MESH-OUT to the other sites. All other inbound maps and MESH-OUT remove the marker, and
#   routes from the VRF are never leaked back, so nothing learned through the hub returns.
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router;
  d = cfg.derived;
  inherit (cfg) bgp;
  inherit (rlib) isV6;
  announced = lib.filter (l: l.announce) cfg.loopbacks;
  own4 =
    bgp.originate4
    ++ lib.optional cfg.wan.v4.announce (rlib.network4 cfg.wan.v4.address)
    ++ map (l: "${l.address}/32") (lib.filter (l: !isV6 l.address) announced);
  own6 =
    bgp.originate6
    ++ lib.optional cfg.wan.v6.announce (rlib.network6 cfg.wan.v6.address)
    ++ map (p: p.prefix) cfg.publicV6
    ++ map (l: "${l.address}/128") (lib.filter (l: isV6 l.address) announced);
  # "<list> seq N <action> <prefix> le <max>" lines, numbered from `start` in steps of 10.
  plist =
    kw: name: start: action: max: prefixes:
    lib.concatImapStringsSep "\n" (
      i: n:
      "${kw} ${name} seq ${toString (start + i * 10)} ${action} ${n}${
        lib.optionalString (max != null) " le ${toString max}"
      }"
    ) prefixes;
  ev = cfg.evpn;
  inherit (bgp) peers;
  peersV4 = lib.filter (p: p.v4) peers;
  peersV6 = lib.filter (p: p.v6) peers;
  anyBfd = lib.any (p: p.bfd) peers;
  marker = "${toString bgp.asn}:0:1";
  hasTransit = lib.any (p: p.transit) peers;
  # Removes the transit marker from a route (inbound from non-transit neighbors, into EVPN).
  strip = lib.optionalString hasTransit "\n set large-comm-list TRANSIT delete";
  # Inbound map of a neighbor; `sfx` is "" (IPv4) or "6".
  inMap =
    sfx: p:
    if p.inPolicy == "deny-all" then
      "DENY-ALL"
    else if p.transit then
      "PEER-IN${sfx}-TRANSIT"
    else if p.inPolicy == "allow-all" then
      if hasTransit then "ALLOW-ALL-IN" else "ALLOW-ALL"
    else
      "PEER-IN${sfx}";
  # Strict inbound maps (`fam`: "ip"/"ipv6", `list`: IN4/IN6) and the leak into the VRF
  # (`out`: OUT4/OUT6); the transit parts only when a neighbor uses them.
  familyMaps = sfx: fam: list: out: ''
    route-map PEER-IN${sfx} permit 10
     match ${fam} address prefix-list ${list}${strip}
    exit
    route-map PEER-OUT${sfx} permit 10
     match ${fam} address prefix-list ${out}
    exit${lib.optionalString hasTransit ''

      route-map PEER-IN${sfx}-TRANSIT permit 10
       match ${fam} address prefix-list ${list}
       set large-community ${marker} additive
      exit''}${lib.optionalString ev.enable ''

      route-map MESH-OUT${sfx} permit 10
       match ${fam} address prefix-list ${out}
      exit''}${
      lib.optionalString (ev.enable && hasTransit) ''

        route-map MESH-OUT${sfx} permit 20
         match large-community TRANSIT
         match ${fam} address prefix-list ${list}${strip}
        exit''
    }'';

  mapName =
    strict: pol:
    if pol == "strict" then
      strict
    else if pol == "allow-all" then
      "ALLOW-ALL"
    else
      "DENY-ALL";
  allPolicies = lib.concatMap (p: [
    p.inPolicy
    p.outPolicy
  ]) peers;
  # A multihop session starts from the static WAN address of the peer's family.
  updateSource = p: if isV6 p.address then d.wanAddr6 else d.wanAddr4;
  # Only emitted when some neighbor uses them (keeps the strict-only output minimal).
  extraMaps =
    lib.optionalString (lib.elem "allow-all" allPolicies) "\n    route-map ALLOW-ALL permit 100\n    exit"
    + lib.optionalString (lib.elem "deny-all" allPolicies) "\n    route-map DENY-ALL deny 100\n    exit"
    + lib.optionalString (
      hasTransit && lib.any (p: p.inPolicy == "allow-all") peers
    ) "\n    route-map ALLOW-ALL-IN permit 100${strip}\n    exit";
in
lib.mkIf bgp.enable {
  assertions = [
    {
      assertion = lib.all (p: p.multihop == null || updateSource p != null) peers;
      message = "router.bgp: a multihop peer uses the static WAN address of its family as update-source; set router.wan.v4.address or router.wan.v6.address";
    }
    {
      assertion = lib.all (p: !p.transit || p.inPolicy == "strict") peers;
      message = "router.bgp: a transit peer needs inPolicy = \"strict\" (its routes reach every site)";
    }
    {
      assertion = !hasTransit || ev.enable;
      message = "router.bgp: transit peers need router.evpn (their routes are passed on through it)";
    }
  ];

  services.frr.bgpd.enable = true;
  # A changed config restarts FRR instead of reloading it: `frrinit.sh reload` starts a new
  # watchfrr and can only move it back into the service's cgroup on cgroup v1, so on v2
  # systemd waits out its stop timeout (2 min) and kills every daemon. Both reset the BGP
  # sessions; the restart takes seconds.
  systemd.services.frr.reloadIfChanged = lib.mkForce false;
  # FRR's routes and the kernel's l3mdev rule (EVPN) are "foreign" to networkd: a networkd
  # restart (any deploy that changes a unit) must not remove them.
  systemd.network.config.networkConfig = {
    ManageForeignRoutes = false;
    ManageForeignRoutingPolicyRules = false;
  };
  services.frr.bfdd.enable = anyBfd;

  # `ip nht resolve-via-default` is only emitted for multihop peers (their address
  # is reachable only via the default route).
  # `no zebra nexthop kernel enable`: routes carry their nexthops inline instead of kernel
  # nexthop groups. networkd deletes foreign nexthop objects when it (re)configures a link
  # (systemd < 256 unconditionally), the kernel drops every route using them and zebra only
  # re-creates the group, not the routes; inline routes are kept by ManageForeignRoutes=no.
  services.frr.config = ''
    frr defaults traditional
    no zebra nexthop kernel enable
    ${lib.optionalString (lib.any (p: p.multihop != null) peers) "ip nht resolve-via-default"}
    !

    ${plist "ip prefix-list" "OUT4" 0 "permit" null own4}
    ${lib.optionalString ev.enable "ip prefix-list IN4 seq 5 deny ${ev.underlay4} le 32"}
    ${plist "ip prefix-list" "IN4" 0 "deny" 32 own4}
    ${plist "ip prefix-list" "IN4" 1000 "permit" 32 bgp.accept4}
    ${plist "ipv6 prefix-list" "OUT6" 0 "permit" null own6}
    ${plist "ipv6 prefix-list" "IN6" 0 "deny" 128 own6}
    ${plist "ipv6 prefix-list" "IN6" 1000 "permit" 128 bgp.accept6}
    !
    ${lib.optionalString hasTransit "bgp large-community-list standard TRANSIT seq 5 permit ${marker}"}
    ${familyMaps "" "ip" "IN4" "OUT4"}
    ${familyMaps "6" "ipv6" "IN6" "OUT6"}${extraMaps}
    !
    ${lib.optionalString ev.enable ''
      route-map SRC4 permit 10
       set src ${d.lanAddr4}
      exit
      ip protocol bgp route-map SRC4
      !''}
    ${lib.optionalString ev.enable "vrf ${ev.vrf}\n vni ${toString ev.vni}\nexit-vrf\n!"}
    router bgp ${toString bgp.asn}
     bgp router-id ${bgp.routerId}
     no bgp default ipv4-unicast
     ${lib.concatMapStringsSep "\n " (
       p:
       lib.concatStringsSep "\n " (
         [
           "neighbor ${p.address} remote-as ${toString p.remoteAs}"
           "neighbor ${p.address} description ${p.name}"
         ]
         ++ lib.optional (p.iface != null) "neighbor ${p.address} interface ${p.iface}"
         ++ lib.optional p.disableConnectedCheck "neighbor ${p.address} disable-connected-check"
         ++ lib.optionals (p.multihop != null) [
           "neighbor ${p.address} ebgp-multihop ${toString p.multihop}"
           "neighbor ${p.address} update-source ${updateSource p}"
         ]
         ++ lib.optional p.bfd "neighbor ${p.address} bfd"
       )
     ) peers}
     ${lib.optionalString ev.enable ''
       neighbor ${ev.hubVtep} remote-as internal
        neighbor ${ev.hubVtep} description hub-evpn
        neighbor ${ev.hubVtep} update-source ${cfg.transport.netbird.iface}
        neighbor ${ev.hubVtep} timers 10 30
        neighbor ${ev.hubVtep} timers connect 10''}
     !
     address-family ipv4 unicast
      ${lib.concatMapStringsSep "\n  " (n: "network ${n}") own4}
      ${lib.concatMapStringsSep "\n  " (
        p:
        lib.concatStringsSep "\n  " (
          [ "neighbor ${p.address} activate" ]
          ++ lib.optional p.nextHopSelf "neighbor ${p.address} next-hop-self"
          ++ [
            "neighbor ${p.address} route-map ${inMap "" p} in"
            "neighbor ${p.address} route-map ${mapName "PEER-OUT" p.outPolicy} out"
          ]
        )
      ) peersV4}
      ${lib.optionalString ev.enable "import vrf ${ev.vrf}
  import vrf route-map PEER-IN"}
     exit-address-family
     !
     address-family ipv6 unicast
      ${lib.concatMapStringsSep "\n  " (n: "network ${n}") own6}
      ${lib.concatMapStringsSep "\n  " (
        p:
        lib.concatStringsSep "\n  " (
          [ "neighbor ${p.address} activate" ]
          ++ lib.optional p.nextHopSelf "neighbor ${p.address} next-hop-self"
          ++ [
            "neighbor ${p.address} route-map ${inMap "6" p} in"
            "neighbor ${p.address} route-map ${mapName "PEER-OUT6" p.outPolicy} out"
          ]
        )
      ) peersV6}
      ${lib.optionalString ev.enable "import vrf ${ev.vrf}
  import vrf route-map PEER-IN6"}
     exit-address-family
     ${lib.optionalString ev.enable ''
       !
        address-family l2vpn evpn
         neighbor ${ev.hubVtep} activate
         advertise-all-vni
        exit-address-family''}
    exit
    ${lib.optionalString ev.enable ''
      !
      router bgp ${toString bgp.asn} vrf ${ev.vrf}
       bgp router-id ${bgp.routerId}
       !
       address-family ipv4 unicast
        import vrf default
        import vrf route-map MESH-OUT
       exit-address-family
       !
       address-family ipv6 unicast
        import vrf default
        import vrf route-map MESH-OUT6
       exit-address-family
       !
       address-family l2vpn evpn
        advertise ipv4 unicast
        advertise ipv6 unicast
       exit-address-family
      exit''}
    ${lib.optionalString anyBfd "!\n    bfd\n    exit"}
  '';
}
