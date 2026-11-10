# IPv6 router advertisements on the LAN (radvd): managed (M=1, O=1), no SLAAC; addresses
# come from DHCPv6, the router is the default router.
{ config, ... }:
let
  cfg = config.router;
  d = cfg.derived;
  # Advertisement interval (s): frequent enough that hosts notice a restart quickly (RFC 4861
  # allows 4-1800; max must be >= 4/3 of min).
  minAdvInterval = 200;
  maxAdvInterval = 300;
  # Ethernet MTU of the LAN; advertised so hosts do not pick a larger one.
  lanMtu = 1500;
  # Hop limit hosts put into outgoing packets (the common default).
  hopLimit = 64;
in
{
  services.radvd = {
    enable = true;
    config = ''
      interface ${d.lanIf} {
        AdvSendAdvert on;
        MinRtrAdvInterval ${toString minAdvInterval};
        MaxRtrAdvInterval ${toString maxAdvInterval};
        AdvLinkMTU ${toString lanMtu};
        AdvCurHopLimit ${toString hopLimit};
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
