# `router-health` (./router health, after every deploy): BGP established, no failed unit, a pending
# reboot is a warning; on server-zfs the pool `rpool` over 75% full or not ONLINE is a warning,
# an unreadable one a failure. Exits 1 on a failure.
{
  config,
  lib,
  pkgs,
  rlib,
  ...
}:
let
  bgp = config.services.frr.bgpd.enable;
  # Appended to `rc=0`, so that the script of sites without the pool is unchanged.
  poolCheck = lib.optionalString (config.router.hardware.profile == "server-zfs") (
    let
      pool = "rpool";
    in
    ''

      cap=$(zpool list -H -o capacity ${pool} 2>/dev/null | tr -d %) || cap=""
      if [ -z "$cap" ]; then echo "FAIL zfs pool ${pool}: not readable"; rc=1
      elif [ "$cap" -gt 75 ]; then echo "warn zfs pool ${pool} is $cap% full"
      else echo "ok   zfs pool ${pool}: $cap% used"; fi
      state=$(zpool list -H -o health ${pool} 2>/dev/null) || state=UNAVAILABLE
      [ "$state" = ONLINE ] || echo "warn zfs pool ${pool} is $state"''
  );
in
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "router-health";
      runtimeInputs = [ pkgs.jq ] ++ lib.optional (poolCheck != "") config.boot.zfs.package;
      text = ''
        rc=0${poolCheck}
        ${lib.optionalString bgp ''
          up=""; total=""
          for _ in $(seq 12); do
            # No answer (FRR restarting) = not ready yet.
            read -r up total < <(vtysh -c "show bgp summary json" 2>/dev/null |
              jq -r '[.[] | .peers? // {} | .[].state] | "\(map(select(. == "Established")) | length) \(length)"') || true
            [ -n "$total" ] && [ "$up" = "$total" ] && break
            sleep 5
          done
          if [ -n "$total" ] && [ "$up" = "$total" ]; then echo "ok   bgp: $up/$total established"; else echo "FAIL bgp: ''${up:-?}/''${total:-?} established"; rc=1; fi
        ''}
        failed=$(systemctl --failed --no-legend --plain)
        if [ -z "$failed" ]; then echo "ok   failed units: 0"; else echo "$failed"; echo "FAIL failed units"; rc=1; fi
        for p in ${toString rlib.bootFiles}; do
          if [ "$(readlink /run/booted-system/$p)" != "$(readlink /run/current-system/$p)" ]; then
            echo "warn reboot required: the booted $p is not the current one"
            break
          fi
        done
        exit "$rc"
      '';
    })
  ];
}
