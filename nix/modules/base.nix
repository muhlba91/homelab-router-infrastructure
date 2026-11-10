# Base system: identity, the hardware watchdog, users, tools. Hardware-independent.
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

  # Hardware watchdog: systemd pets it; a hung system is reset by the hardware.
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkIf (
    builtins.match "0+[smh]" cfg.system.watchdog == null
  ) cfg.system.watchdog;
  services.journald.extraConfig = "SystemMaxUse=500M";

  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.mgmt.sshKeys;
  };
  # Passwordless sudo: deploy-rs activates as root through `deploy`, which has no password.
  security.sudo.wheelNeedsPassword = false;
  # Users exist only as declared here: nobody has a password (SSH keys only), and nothing
  # created or changed on the router survives the next activation.
  users.mutableUsers = false;

  # Man pages stay; the NixOS manual (built with every system) is not needed on a router.
  documentation.nixos.enable = false;
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
