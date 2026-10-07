# DHCPv4 + DHCPv6 on the LAN (Kea): 12h leases, router/DNS/domain options, static
# reservations.
{ config, ... }:
let
  cfg = config.router;
  d = cfg.derived;
  domain = cfg.site.domain;
in
{
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ d.lanIf ];
      lease-database = {
        name = "/var/lib/kea/dhcp4.leases";
        persist = true;
        type = "memfile";
      };
      valid-lifetime = 43200;
      loggers = [
        {
          name = "kea-dhcp4";
          output_options = [ { output = "stdout"; } ];
          severity = "INFO";
        }
      ];
      subnet4 = [
        {
          id = 1;
          subnet = cfg.lan.v4Net;
          pools = [ { pool = cfg.dhcp.pool4; } ];
          option-data = [
            {
              name = "routers";
              data = d.lanAddr4;
            }
            {
              name = "domain-name-servers";
              data = d.lanAddr4;
            }
            {
              name = "domain-name";
              data = domain;
            }
            {
              name = "domain-search";
              data = domain;
            }
          ];
          reservations = map (r: {
            ip-address = r.ip;
            hw-address = r.mac;
            inherit (r) hostname;
          }) cfg.dhcp.reservations4;
        }
      ];
    };
  };

  services.kea.dhcp6 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ d.lanIf ];
      lease-database = {
        name = "/var/lib/kea/dhcp6.leases";
        persist = true;
        type = "memfile";
      };
      valid-lifetime = 43200;
      mac-sources = [ "ipv6-link-local" ];
      loggers = [
        {
          name = "kea-dhcp6";
          output_options = [ { output = "stdout"; } ];
          severity = "INFO";
        }
      ];
      subnet6 = [
        {
          id = 1;
          subnet = cfg.lan.v6Net;
          interface = d.lanIf;
          pools = [ { pool = cfg.dhcp.pool6; } ];
          option-data = [
            {
              name = "dns-servers";
              data = d.lanAddr6;
            }
            {
              name = "domain-search";
              data = domain;
            }
          ];
          reservations = map (r: {
            inherit (r) duid hostname;
            ip-addresses = [ r.ip ];
          }) cfg.dhcp.reservations6;
        }
      ];
    };
  };
}
