# Secrets are files delivered outside Nix (./router push-secrets, or nixos-anywhere
# --extra-files on first install) into /var/lib/secrets. Nix declares only names, owners and
# modes: the store is world-readable. Three mechanisms:
#  1. activation guard: each declared file must exist and be non-empty, and gets its
#     owner/mode. A missing secret fails the activation, so deploy-rs rolls back (at boot a
#     failure is only logged: the router must still come up).
#  2. a path unit per secret re-applies owner/mode and runs its `reload` command when the
#     file changes (rotation by a plain push).
#  3. the directory is not listable (0711); file modes protect the content.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  dir = "/var/lib/secrets"; # also SECRETS_DIR in ./router
  secrets = config.router.secrets;
  # Owner and mode only when they differ: PathChanged also fires on attribute changes, so
  # an unconditional chown/chmod would run every secret's reload on every activation.
  applyPerms =
    s:
    let
      mode = builtins.head (builtins.match "0*([0-7]+)" s.mode); # as `stat -c %a` prints it
    in
    ''
      [ "$(stat -c %U:%G:%a ${s.path})" = "${s.owner}:${s.group}:${mode}" ] \
        || { chown ${s.owner}:${s.group} ${s.path} && chmod ${s.mode} ${s.path}; }
    '';

  secretType = types.submodule (
    { name, ... }:
    {
      options = {
        path = mkOption {
          type = types.str;
          readOnly = true;
          default = "${dir}/${name}";
          description = "Where the file lives on the router.";
        };
        owner = mkOption {
          type = types.str;
          default = "root";
          description = "File owner.";
        };
        group = mkOption {
          type = types.str;
          default = "root";
          description = "File group.";
        };
        mode = mkOption {
          type = types.strMatching "0*[0-7]+";
          default = "0400";
          description = "File mode.";
        };
        reload = mkOption {
          type = types.str;
          default = "";
          description = "Shell command run when the file changes (e.g. `networkctl reload`).";
        };
      };
    }
  );
in
{
  options.router.secrets = mkOption {
    type = types.attrsOf secretType;
    default = { };
    description = "Secret files the router needs (declared by modules; values are delivered out of band).";
  };

  config = lib.mkIf (secrets != { }) {
    system.activationScripts.routerSecrets = {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        install -d -m 0711 -o root -g root ${dir}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (_: s: ''
            if [ ! -s ${s.path} ]; then
              echo "router-secrets: ${s.path} is missing or empty (deliver it: ./router push-secrets <site>)" >&2
              false
            else
              ${applyPerms s}
            fi
          '') secrets
        )}
      '';
    };

    systemd.paths = lib.mapAttrs' (
      n: s:
      lib.nameValuePair "router-secret-${n}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = s.path;
      }
    ) secrets;

    systemd.services = lib.mapAttrs' (
      n: s:
      lib.nameValuePair "router-secret-${n}" {
        description = "Apply permissions and reload after ${s.path} changed";
        serviceConfig.Type = "oneshot";
        path = [
          pkgs.coreutils
          pkgs.systemd
        ];
        script = ''
          ${applyPerms s}
          ${s.reload}
        '';
      }
    ) secrets;
  };
}
