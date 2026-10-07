# Flake checks (`nix flake check`, ./router check), offline and without capabilities, with
# the tools of the checking system (the configurations are only evaluated, never built):
#   lint          nixfmt (same as `nix fmt`), deadnix (unused code), statix (statix.toml),
#                 shellcheck (router, nx, secrets-sync.sh)
#   deploy-schema the deploy-rs nodes against deploy-rs' schema (its own check would build
#                 every system: the profile paths are store paths of the routers)
#   site-<name>   the site evaluates; its nftables ruleset passes `nft --check` inside a
#                 user-space kernel (LKL, as the NixOS build-time check does), radvd -c,
#                 kea-dhcp4/6 -t (without interface names: the LAN NIC does not exist here),
#                 vtysh -C (FRR itself only logs a bad line)
#   eval          tests/eval.nix on the fixtures (lib.runTests; prints the failing tests)
{
  pkgs,
  lib,
  src,
  configurations,
  fixtures,
  deploy,
  deploySchema,
}:
let
  # A file with text of the evaluated configuration, without its store paths: they belong
  # to the routers' system and must not become build inputs of the check.
  file = name: text: pkgs.writeText name (builtins.unsafeDiscardStringContext text);

  ruleset =
    c:
    lib.concatMapStrings (t: ''
      table ${t.family} ${t.name} {
      ${t.content}
      }
    '') (lib.attrValues (lib.filterAttrs (_: t: t.enable) c.networking.nftables.tables));

  kea =
    family: settings:
    builtins.toJSON {
      ${family} =
        settings
        // {
          interfaces-config = settings.interfaces-config // {
            interfaces = [ ];
          };
        }
        // lib.optionalAttrs (settings ? subnet6) {
          subnet6 = map (s: removeAttrs s [ "interface" ]) settings.subnet6;
        };
    };

  # nft --check needs a kernel: LKL provides one in the process, libredirect the /etc
  # files nft reads (as in nixpkgs' nftables module).
  nftCheck = ''
    NIX_REDIRECTS=/etc/protocols=${pkgs.iana-etc}/etc/protocols:/etc/services=${pkgs.iana-etc}/etc/services \
    LD_PRELOAD="${pkgs.libredirect}/lib/libredirect.so ${pkgs.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
      nft --check --file'';

  siteCheck =
    name: system:
    let
      c = system.config;
    in
    pkgs.runCommand "check-site-${name}"
      {
        nativeBuildInputs = [
          pkgs.nftables
          pkgs.radvd
          pkgs.kea
          pkgs.frr
        ];
      }
      ''
        echo "ok   evaluates (${builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath})"
        ${nftCheck} ${file "ruleset.nft" (ruleset c)}
        echo "ok   nft --check"
        radvd -c -C ${file "radvd.conf" c.services.radvd.config}
        echo "ok   radvd -c"
        kea-dhcp4 -t ${file "kea4.json" (kea "Dhcp4" c.services.kea.dhcp4.settings)} > kea4.log || { cat kea4.log; exit 1; }
        echo "ok   kea-dhcp4 -t"
        kea-dhcp6 -t ${file "kea6.json" (kea "Dhcp6" c.services.kea.dhcp6.settings)} > kea6.log || { cat kea6.log; exit 1; }
        echo "ok   kea-dhcp6 -t"
        mkdir frr && cp ${file "frr.conf" c.services.frr.config} frr/frr.conf && touch frr/vtysh.conf
        vtysh --config_dir frr -C
        echo "ok   vtysh -C"
        touch $out
      '';

  evalFailures = import ./eval.nix { inherit lib fixtures; };
in
{
  eval = pkgs.runCommand "check-eval" { } (
    if evalFailures == [ ] then
      "echo 'ok   eval tests'; touch $out"
    else
      "cat ${file "failures.json" (builtins.toJSON evalFailures)}; exit 1"
  );

  deploy-schema =
    pkgs.runCommand "check-deploy-schema"
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      "check-jsonschema --schemafile ${deploySchema} ${file "deploy.json" (builtins.toJSON deploy)} && touch $out";

  lint =
    pkgs.runCommand "check-lint"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.deadnix
          pkgs.statix
          pkgs.shellcheck
        ];
      }
      ''
        cd ${src}
        nixfmt --check $(find . -name '*.nix')
        echo "ok   nixfmt"
        deadnix --fail -- .
        echo "ok   deadnix"
        statix check .
        echo "ok   statix"
        shellcheck router nx secrets-sync.sh
        echo "ok   shellcheck"
        touch $out
      '';
}
// lib.mapAttrs' (
  name: system: lib.nameValuePair "site-${name}" (siteCheck name system)
) configurations
