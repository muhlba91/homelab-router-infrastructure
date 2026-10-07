# Values computed once from router.* and shared by the modules.
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router;
  inherit (rlib) addr;
  hex2 = n: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString n));
in
{
  config.router.derived = {
    lanIf = cfg.lan.iface;
    wanParent = cfg.wan.iface;
    # The device carrying WAN traffic: the VLAN device if a VLAN is used.
    wanIf = if cfg.wan.vlan == null then cfg.wan.iface else "${cfg.wan.iface}.${toString cfg.wan.vlan}";
    lanAddr4 = addr cfg.lan.v4;
    lanAddr6 = addr cfg.lan.v6;
    wanAddr4 = if cfg.wan.v4.address == null then null else addr cfg.wan.v4.address;
    wanAddr6 = if cfg.wan.v6.address == null then null else addr cfg.wan.v6.address;
    # Reply-to for connections that arrive on the WAN (firewall.nix marks, networking.nix
    # routes): own mark bit 0x10000000 (NetBird uses 0x1bdxx) and routing table.
    wanReply = {
      mark = 268435456;
      table = 200;
    };
    # EVPN device names and the router MAC of the L3VNI (02:5e + router-id bytes).
    evpnBridge = "br${toString cfg.evpn.vni}";
    evpnVxlan = "vni${toString cfg.evpn.vni}";
    evpnRmac = lib.concatStringsSep ":" (
      [
        "02"
        "5e"
      ]
      ++ map (o: hex2 (lib.toInt o)) (lib.splitString "." cfg.bgp.routerId)
    );
  };
}
