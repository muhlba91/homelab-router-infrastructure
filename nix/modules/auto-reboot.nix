# router.system.autoReboot: a timer that reboots the router when a boot file of the system it
# would boot (the system profile) differs from the booted one.
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router.system.autoReboot;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.router-auto-reboot = {
      description = "Reboot when a boot file of the system changed";
      serviceConfig.Type = "oneshot";
      script = ''
        for p in ${toString rlib.bootFiles}; do
          if [ "$(readlink /run/booted-system/$p)" != "$(readlink /nix/var/nix/profiles/system/$p)" ]; then
            echo "the $p changed: rebooting"
            exec systemctl reboot
          fi
        done
      '';
    };
    systemd.timers.router-auto-reboot = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.window;
    };
  };
}
