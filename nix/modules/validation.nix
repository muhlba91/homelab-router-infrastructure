# Cross-checks of the LAN addressing: the router address, the DHCP pools and the supernet
# must belong to the LAN's networks (a typo would otherwise only show up as a broken LAN).
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router;
  inherit (cfg) lan dhcp;
  inherit (rlib) addr within4 within6;

  # "a - b" -> [ a b ]
  poolEnds =
    pool:
    let
      m = builtins.match " *([^ ]+) *- *([^ ]+) *" pool;
    in
    if m == null then [ ] else m;
in
{
  assertions = [
    {
      assertion = within4 lan.v4Net (addr lan.v4);
      message = "router.lan.v4 (${lan.v4}) is not inside router.lan.v4Net (${lan.v4Net})";
    }
    {
      assertion = within6 lan.v6Net lan.v6;
      message = "router.lan.v6 (${lan.v6}) is not inside router.lan.v6Net (${lan.v6Net})";
    }
    {
      assertion = within6 lan.v6Supernet lan.v6Net;
      message = "router.lan.v6Net (${lan.v6Net}) is not inside router.lan.v6Supernet (${lan.v6Supernet})";
    }
    {
      assertion = lib.all (a: within4 lan.v4Net a) (poolEnds dhcp.pool4);
      message = "router.dhcp.pool4 (${dhcp.pool4}) is not inside router.lan.v4Net (${lan.v4Net})";
    }
    {
      assertion = lib.all (a: within6 lan.v6Net "${a}/128") (poolEnds dhcp.pool6);
      message = "router.dhcp.pool6 (${dhcp.pool6}) is not inside router.lan.v6Net (${lan.v6Net})";
    }
  ];
}
