# UPS (NUT, router.hardware.ups): the driver reads the UPS, upsd serves it on loopback and
# the LAN address (TCP 3493; the firewall service `nut` opens it to the LAN), and upsmon
# as the primary shuts the router down when the battery runs low, after its secondaries
# (other hosts logged in as `upsmon`), then the UPS cuts its power. The password of
# `upsmon` is the secret `nut-password`.
{ config, lib, ... }:
let
  cfg = config.router;
  ups = cfg.hardware.ups;
  user = "upsmon";
  port = 3493;
  secret = config.router.secrets.nut-password.path;
in
lib.mkIf ups.enable {
  router.secrets.nut-password.reload = "systemctl try-restart upsd.service upsmon.service";

  power.ups = {
    enable = true;
    mode = "netserver";
    ups.${ups.name} = {
      inherit (ups) driver port;
    };
    upsd.listen = map (address: { inherit address port; }) [
      "127.0.0.1"
      "::1"
      cfg.derived.lanAddr4
    ];
    users.${user} = {
      passwordFile = secret;
      upsmon = "primary";
    };
    upsmon.monitor.${ups.name} = {
      system = "${ups.name}@localhost";
      type = "primary";
      inherit user;
    };
  };
  # upsd binds the LAN address, which must exist first.
  systemd.services.upsd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  router.firewall.services.nut = {
    enable = lib.mkDefault true;
    proto = lib.mkDefault "tcp";
    ports = lib.mkDefault [ port ];
    from = lib.mkDefault [ "lan" ];
  };
}
