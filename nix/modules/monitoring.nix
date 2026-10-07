# Monitoring: vnstat (traffic history, always on, local only) and the Prometheus exporters
# of router.observability.monitoring.prometheus, scraped from outside: they listen on every
# address, and the firewall service `metrics` (lan, trusted by default) opens exactly their
# ports.
{ config, lib, ... }:
let
  cfg = config.router;
  prom = cfg.observability.monitoring.prometheus;
  has = e: prom.enable && lib.elem e prom.exporters;
  exporters = config.services.prometheus.exporters;
  crowdsecPort = 6060;
  ports =
    lib.optional (has "node") exporters.node.port
    ++ lib.optional (has "kea") exporters.kea.port
    ++ lib.optional (has "frr") exporters.frr.port
    ++ lib.optional (has "smartctl") exporters.smartctl.port
    ++ lib.optional (has "crowdsec") crowdsecPort
    ++ lib.optional (has "nut") exporters.nut.port;
  keaSocket = v: "/run/kea/kea-dhcp${v}.socket";
in
{
  assertions = [
    {
      assertion = !(has "crowdsec") || cfg.security.crowdsec.enable;
      message = "router.observability.monitoring.prometheus.exporters contains crowdsec, but router.security.crowdsec is off";
    }
    {
      assertion = !(has "nut") || cfg.hardware.ups.enable;
      message = "router.observability.monitoring.prometheus.exporters contains nut, but router.hardware.ups is off";
    }
  ];

  services.vnstat.enable = true;

  services.prometheus.exporters = {
    node = lib.mkIf (has "node") {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };
    # Kea's statistics through its control sockets (the exporter runs as Kea's user).
    kea = lib.mkIf (has "kea") {
      enable = true;
      targets = [
        (keaSocket "4")
        (keaSocket "6")
      ];
    };
    # The sessions we run: EVPN (l2vpn), IPv6 unicast, BFD only with a neighbor using it.
    frr = lib.mkIf (has "frr") {
      enable = true;
      enabledCollectors = [ "bgp6" ] ++ lib.optional cfg.evpn.enable "bgpl2vpn";
      disabledCollectors = [ "ospf" ] ++ lib.optional (!lib.any (p: p.bfd) cfg.bgp.peers) "bfd";
    };
    smartctl.enable = has "smartctl";
    # Reads the UPS from upsd on loopback (reading needs no login).
    nut.enable = has "nut";
  };
  services.kea.dhcp4.settings.control-sockets = lib.mkIf (has "kea") [
    {
      socket-type = "unix";
      socket-name = keaSocket "4";
    }
  ];
  services.kea.dhcp6.settings.control-sockets = lib.mkIf (has "kea") [
    {
      socket-type = "unix";
      socket-name = keaSocket "6";
    }
  ];
  # CrowdSec serves its own metrics (127.0.0.1 by default).
  services.crowdsec.settings.general.prometheus = lib.mkIf (has "crowdsec") {
    listen_addr = "0.0.0.0";
    listen_port = crowdsecPort;
  };

  router.firewall.services.metrics = {
    enable = lib.mkDefault prom.enable;
    proto = lib.mkDefault "tcp";
    ports = lib.mkDefault ports;
    from = lib.mkDefault [
      "lan"
      "trusted"
    ];
  };
}
