# Nix on the router: settings, garbage collection, store optimisation.
{ config, ... }:
let
  cfg = config.router;
in
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # deploy-rs copies/builds as `deploy` (in wheel); it must be trusted to push closures.
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
  # Age limit (nix-collect-garbage) plus a count limit, which runs first: many deploys in
  # a short time would otherwise keep every generation until it is old enough.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than ${cfg.system.gc.olderThan}";
  };
  systemd.services.nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +${toString cfg.system.gc.keep}";
  nix.optimise.automatic = true;
  # Flakes only: no channels and no NIX_PATH pointing at them.
  nix.channel.enable = false;
}
