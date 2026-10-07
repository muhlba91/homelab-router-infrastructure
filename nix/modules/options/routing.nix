# Vars schema: BGP, the NetBird underlay, EVPN, and the internal list of mesh interfaces.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./types.nix { inherit lib; })
    str
    strD
    bool
    nullable
    typed
    typedD
    ip4
    ip6
    cidr4
    cidr6
    mtu
    ;

  bgpPeer = types.submodule {
    options = {
      name = str "Description of the neighbor (also used in FRR).";
      address = typed (types.either ip4 ip6) "Neighbor address (the session runs to this address).";
      remoteAs = mkOption {
        type = types.either types.ints.positive (
          types.enum [
            "internal"
            "external"
          ]
        );
        description = "Remote AS number, `internal` (iBGP) or `external` (any other AS).";
      };
      iface = nullable types.str "Bind the neighbor to this interface (`neighbor X interface IF`), e.g. the LAN for a link-local peer.";
      bfd = bool false "Enable BFD for this neighbor.";
      disableConnectedCheck = bool false "`neighbor X disable-connected-check`.";
      nextHopSelf = bool false "`neighbor X next-hop-self` in the activated families.";
      multihop = nullable (types.ints.between 1 255) "eBGP multihop TTL (also sets update-source to the static WAN address of the peer's family); null = directly connected.";
      v4 = bool true "Activate IPv4 unicast on this neighbor.";
      v6 = bool true "Activate IPv6 unicast on this neighbor.";
      inPolicy = mkOption {
        type = types.enum [
          "strict"
          "allow-all"
          "deny-all"
        ];
        default = "strict";
        description = "`strict`: accept only router.bgp.accept4/accept6 (any length), never our own originated prefixes back.";
      };
      outPolicy = mkOption {
        type = types.enum [
          "strict"
          "allow-all"
          "deny-all"
        ];
        default = "strict";
        description = "`strict`: announce only router.bgp.originate4/6.";
      };
      transit = bool false "Pass the routes accepted from this neighbor on to the other sites through EVPN (e.g. a k8s cluster with changing prefixes). Needs inPolicy `strict` and router.evpn. Never for a neighbor that is itself a site (a loop).";
    };
  };
in
{
  options.router = {
    bgp = {
      enable = bool true ''
        Run BGP (FRR). Off: no routing daemon, no BGP firewall rules; EVPN needs it on.
      '';
      asn = mkOption {
        type = types.ints.positive;
        description = "Local AS.";
      };
      routerId = typed ip4 "BGP router-id (explicit, unique; also the source of the EVPN router MAC).";
      originate4 = typedD (types.listOf cidr4) [ ] "IPv4 prefixes to announce (must exist in the RIB).";
      originate6 = typedD (types.listOf cidr6) [ ] "IPv6 prefixes to announce (must exist in the RIB).";
      accept4 = typedD (types.listOf cidr4) [
        "10.0.0.0/8"
      ] "IPv4 ranges (and all their more-specifics) accepted by the `strict` inbound policy.";
      accept6 = typedD (types.listOf cidr6) [
        "fc00::/7"
        "2001:678:dc0::/48"
      ] "IPv6 ranges (and all their more-specifics) accepted by the `strict` inbound policy.";
      peers = mkOption {
        type = types.listOf bgpPeer;
        default = [ ];
        description = "BGP neighbors.";
      };
    };

    transport.netbird = {
      enable = bool false "NetBird client: the encrypted underlay (overlay IPs) that EVPN/VXLAN runs over.";
      managementUrl = str "NetBird management URL (only used for the first login; then stored in the client state).";
      iface = strD "wt0" "Interface name.";
      port = typedD types.port 51820 "Local WireGuard port (opened on the WAN for direct connections).";
      mtu = typedD mtu 1420 "Interface MTU (VXLAN on top gets 50 bytes less).";
      enforcePolicies = bool true ''
        NetBird's firewall enforces the access policies (groups/policies in NetBird) on
        traffic arriving through the overlay: only peers a policy allows reach this router.
        NetBird then owns that interface: it inserts `iifname wt0 accept` at the top of our
        input/forward chains (and re-inserts it within a minute after an nftables reload),
        so our own wt0 rules only apply while NetBird is down. Off: everyone in the overlay
        reaches everything our nftables allows on wt0.
      '';
    };

    evpn = {
      enable = bool false ''
        EVPN/L3VNI over the NetBird underlay (needs transport.netbird): VRF + VXLAN + iBGP
        to the hub, which reflects the routes between the sites (modules/evpn.nix, bgp.nix).
      '';
      hubVtep = typed ip4 "Hub overlay IPv4 (its VTEP and our only EVPN neighbor; hub repo stack output `netbird.client.ipv4`).";
      underlay4 =
        typedD cidr4 "10.253.0.0/16"
          "NetBird IPv4 network range: VXLAN accepted from it, never learned through the overlay.";
      vrf = strD "mesh" "VRF that carries the L3VNI (the LAN stays in the default VRF; routes are leaked).";
      vni = typedD (types.ints.between 1 16777215) 50001 "L3VNI (50000+ = L3VNIs). Must match the hub.";
      table = typedD types.ints.positive 1001 "Kernel routing table of the VRF.";
      mtu = mkOption {
        type = mtu;
        default = config.router.transport.netbird.mtu - 50;
        defaultText = lib.literalExpression "router.transport.netbird.mtu - 50";
        description = "MTU of the VXLAN path: at most the NetBird MTU - 50 (VXLAN overhead).";
      };
    };

    # Internal: filled by modules, not by vars.
    mesh.interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      description = "Interfaces where routed traffic from other sites enters (firewall zone `mesh`; set by modules/evpn.nix).";
    };
  };
}
