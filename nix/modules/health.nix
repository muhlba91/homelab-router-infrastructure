# `router-health` (./router health, after every deploy): the BGP sessions are established
# (given a minute: a deploy may restart FRR), no unit has failed; a pending reboot (the
# booted kernel, initrd or modules are not the current system's) is a warning. Exits 1 on
# a failure.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  bgp = config.services.frr.bgpd.enable;
in
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "router-health";
      runtimeInputs = [ pkgs.jq ];
      text = ''
        rc=0
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
        for p in kernel initrd kernel-modules; do
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
