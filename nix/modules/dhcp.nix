# DHCPv4 + DHCPv6 on the LAN (Kea): 12 h leases, router/DNS/domain options, static
# reservations.
{ config, ... }:
let
  cfg = config.router;
  d = cfg.derived;
  domain = cfg.site.domain;

  # Kea opens its sockets once at start: when the LAN interface is not ready yet (its
  # link-local address is still tentative at boot) a socket fails, and with the defaults
  # (no retries, not required) the server keeps running without answering anyone. Retrying
  # makes it come up when the interface does.
  interfacesConfig = {
    interfaces = [ d.lanIf ];
    service-sockets-max-retries = 30;
    service-sockets-retry-wait-time = 2000; # ms
  };

  leaseSeconds = 12 * 3600;

  # Settings both servers share; `kind` is "4" or "6".
  common = kind: {
    interfaces-config = interfacesConfig;
    lease-database = {
      name = "/var/lib/kea/dhcp${kind}.leases";
      persist = true;
      type = "memfile";
    };
    valid-lifetime = leaseSeconds;
    loggers = [
      {
        name = "kea-dhcp${kind}";
        output_options = [ { output = "stdout"; } ];
        severity = "INFO";
      }
    ];
  };
in
{
  services.kea.dhcp4 = {
    enable = true;
    settings = common "4" // {
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
    settings = common "6" // {
      mac-sources = [ "ipv6-link-local" ];
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

  # Both servers use the runtime directory `kea` (the control sockets). Started at the same
  # moment at boot, each unit's setup of that directory raced with the other server's check
  # of its permissions and both failed once; DHCPv6 starts after DHCPv4 instead.
  systemd.services.kea-dhcp6-server.after = [ "kea-dhcp4-server.service" ];
}
