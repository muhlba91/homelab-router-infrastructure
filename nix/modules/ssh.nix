# SSH: key-only login for the deploy user, with the host key optionally pinned
# (router.mgmt.hostKey).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.router;
in
{
  router.secrets = lib.mkIf (cfg.mgmt.hostKey != null) {
    ssh-host-key.reload = "systemctl reload sshd.service";
  };
  # A pinned host key comes only from the secret: no generated fallback, and a key that does
  # not match mgmt.hostKey fails the activation (deploy-rs rolls back).
  systemd.services.sshd-keygen.enable = cfg.mgmt.hostKey == null;
  system.activationScripts.routerHostKey = lib.mkIf (cfg.mgmt.hostKey != null) {
    deps = [ "routerSecrets" ];
    text =
      let
        key = config.router.secrets.ssh-host-key.path;
        pinned = lib.concatStringsSep " " (lib.take 2 (lib.splitString " " cfg.mgmt.hostKey));
      in
      ''
        if [ -s ${key} ] && [ "$(${pkgs.openssh}/bin/ssh-keygen -y -f ${key} | cut -d' ' -f1,2)" != "${pinned}" ]; then
          echo "router-secrets: ${key} does not match router.mgmt.hostKey" >&2
          false
        fi
      '';
  };

  services.openssh = {
    enable = true;
    openFirewall = false; # nftables decides who may connect
    # A pinned host key (mgmt.hostKey) is the only key sshd offers. A reload re-reads it.
    hostKeys = lib.mkIf (cfg.mgmt.hostKey != null) [
      {
        inherit (config.router.secrets.ssh-host-key) path;
        type = lib.removePrefix "ssh-" (lib.head (lib.splitString " " cfg.mgmt.hostKey));
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ config.users.users.deploy.name ];
    };
  };
}
