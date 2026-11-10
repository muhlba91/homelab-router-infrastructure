# Recovery of a NetBird client that stays in `Connecting` after its server was down: it
# keeps sending offers and never reconnects. The hub session lost for `after` minutes
# while the hub's overlay address does not answer means the tunnel is dead (a ping that
# works with BGP down is not NetBird's fault: no restart). State lives in the runtime
# directory (/run), so a reboot starts clean.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.router;
  ev = cfg.evpn;
  inherit (cfg.derived) netbirdUnit;
  script = pkgs.writeShellApplication {
    name = "evpn-recovery";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.frr
      pkgs.iputils
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      dir=$RUNTIME_DIRECTORY
      now=$(date +%s)
      state=$(vtysh -c "show bgp neighbors ${ev.hubVtep} json" 2>/dev/null \
        | jq -r '[.[] | .bgpState?][0] // empty' || true)
      # FRR not answering is not a NetBird problem.
      [ -n "$state" ] || exit 0
      if [ "$state" = Established ] || ping -c 2 -W 2 ${ev.hubVtep} >/dev/null 2>&1; then
        rm -f "$dir/down"
        exit 0
      fi
      [ -e "$dir/down" ] || echo "$now" > "$dir/down"
      down=$(cat "$dir/down")
      [ $((now - down)) -ge ${toString (ev.recovery.after * 60)} ] || exit 0
      last=$(cat "$dir/restart" 2>/dev/null || echo 0)
      [ $((now - last)) -ge ${toString (ev.recovery.cooldown * 60)} ] || exit 0
      echo "hub ${ev.hubVtep} ($state) lost for $(( (now - down) / 60 )) min, no ping answer: restarting ${netbirdUnit}"
      echo "$now" > "$dir/restart"
      systemctl restart ${netbirdUnit}.service
    '';
  };
in
{
  config = lib.mkIf (ev.enable && ev.recovery.enable) {
    systemd.services.evpn-recovery = {
      description = "Restart the NetBird client when the hub stays unreachable";
      after = [ "frr.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe script;
        RuntimeDirectory = "evpn-recovery";
        RuntimeDirectoryPreserve = "yes";
      };
    };
    systemd.timers.evpn-recovery = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min"; # NetBird and the BGP session get time to come up first
        OnUnitActiveSec = "1min";
      };
    };
  };
}
