# Base system: identity, nix (settings, garbage collection), the hardware watchdog, users,
# SSH, tools. Hardware-independent.
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
  system.stateVersion = "26.05";
  assertions = [
    {
      assertion = !cfg.meta.deployable || cfg.mgmt.sshKeys != [ ];
      message = "router.mgmt.sshKeys is empty: deploy-rs (user `deploy`) could not log in after this deploy";
    }
  ];

  networking.hostName = cfg.site.hostname;
  networking.domain = cfg.site.domain;
  time.timeZone = cfg.site.timezone;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # deploy-rs copies/builds as `deploy`; it must be trusted to push closures.
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
  # Hardware watchdog: systemd pets it; a hung system is reset by the hardware.
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkIf (
    builtins.match "0+[smh]" cfg.system.watchdog == null
  ) cfg.system.watchdog;
  nix.optimise.automatic = true;
  services.journald.extraConfig = "SystemMaxUse=500M";

  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.mgmt.sshKeys;
  };
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
  security.sudo.wheelNeedsPassword = false;
  # Users exist only as declared here: nobody has a password (SSH keys only), and nothing
  # created or changed on the router survives the next activation.
  users.mutableUsers = false;

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
    };
  };

  # Man pages stay; the NixOS manual (built with every system) is not needed on a router.
  documentation.nixos.enable = false;
  # Flakes only: no channels and no NIX_PATH pointing at them.
  nix.channel.enable = false;

  environment.enableAllTerminfo = true; # ssh from ghostty/kitty/etc. without "unknown terminal type"

  environment.systemPackages = with pkgs; [
    tcpdump
    mtr
    dig
    ethtool
    conntrack-tools
    iperf3
    wireguard-tools # `wg show wt0` (NetBird's kernel WireGuard)
    htop
    vim
  ];
}
