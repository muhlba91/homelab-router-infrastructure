# IPv6 router advertisements on the LAN (radvd): managed (M=1, O=1), no SLAAC; addresses
# come from DHCPv6, the router is the default router.
{ config, ... }:
let
  cfg = config.router;
  d = cfg.derived;
in
{
  services.radvd = {
    enable = true;
    config = ''
      interface ${d.lanIf} {
        AdvSendAdvert on;
        MinRtrAdvInterval 200;
        MaxRtrAdvInterval 300;
        AdvLinkMTU 1500;
        AdvCurHopLimit 64;
        AdvManagedFlag on;
        AdvOtherConfigFlag on;
        RemoveAdvOnExit on;
        prefix ${cfg.lan.v6Net} {
          DeprecatePrefix on;
          AdvOnLink on;
          AdvAutonomous off;
        };
        RDNSS ${d.lanAddr6} {
        };
        DNSSL ${cfg.site.domain} {
        };
      };
    '';
  };
}
