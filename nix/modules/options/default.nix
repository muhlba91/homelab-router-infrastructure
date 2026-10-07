# The vars schema (by area): everything a site's vars.nix can set, typed and validated at
# evaluation time; the modules only read `config.router`. No secret values here (copied to
# the Nix store): secrets are files (router.secrets, modules/secrets.nix).
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./site.nix
    ./network.nix
    ./firewall.nix
    ./services.nix
    ./routing.nix
  ];

  options.router = {
    derived = mkOption {
      type = types.attrs;
      internal = true;
      readOnly = true;
      description = "Derived values (see modules/derived.nix).";
    };
  };
}
