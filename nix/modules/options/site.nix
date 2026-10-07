# Vars schema: the site itself (identity, management, trusted networks), its hardware and
# system settings.
{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./types.nix { inherit lib; })
    str
    strD
    bool
    nullable
    strList
    typedD
    cidr4
    cidr6
    ;

  # Hardware profiles are the files in ../../hardware (one source of truth for the flake too).
  hardwareProfiles = map (lib.removeSuffix ".nix") (
    builtins.attrNames (builtins.readDir ../../hardware)
  );
in
{
  options.router = {
    meta.deployable = bool true ''
      Whether this site may be deployed. Example/evaluation-only sites set this to
      false; they get a nixosConfiguration (for CI) but no deploy-rs node.
    '';
    meta.deployOrder = nullable types.ints.unsigned ''
      Position in the deploy order (from the site file's name, `<order>-<name>.yml`): the sites
      are deployed in ascending order, sites without one last (by name). Read by the deploy
      tooling only, never by the router's configuration.
    '';

    site = {
      name = str "Short site name (also the flake output name).";
      hostname = str "Host name.";
      domain = str "DNS domain of the site (DHCP domain/search, radvd DNSSL).";
      timezone = strD "Etc/UTC" "Time zone.";
    };

    mgmt = {
      address = str "Address (or name) deploy-rs/SSH use. Prefer one that is routed through the mesh (symmetric return path).";
      sshKeys = strList [ ] "Public keys allowed for the `deploy` user.";
      hostKey = nullable types.str ''
        The router's public SSH host key (`<type> <base64>`): sshd uses the matching private key
        from the secret `ssh-host-key`, and ./router accepts only this key for the site.
        null = sshd's own generated keys, accepted on first use.
      '';
    };

    trusted = {
      v4 = typedD (types.listOf cidr4) [ "10.0.0.0/8" ] ''
        Our other networks (zone `trusted`): may reach the router services that allow
        `trusted` (router.firewall.services) from the LAN and the mesh (the WAN only with
        trusted.onWan, which also lets them open connections into the LAN), and are routed,
        never NATed.
      '';
      v6 = typedD (types.listOf cidr6) [
        "fc00::/7"
        "2001:678:dc0::/48"
      ] "IPv6 counterpart of trusted.v4.";
      onWan = bool false ''
        Accept the trusted networks on the WAN interface too (services and WAN -> LAN). Only
        for a WAN that is itself a private network of ours (e.g. a transfer net to a
        hypervisor or another site's LAN); on an internet WAN these sources could be spoofed.
      '';
    };

    hardware = {
      profile = mkOption {
        type = types.enum hardwareProfiles;
        default = "qemu";
        description = "Hand-written hardware/boot profile: hardware/<profile>.nix (`qemu`: any x86_64 VM, BIOS or UEFI).";
      };
      disk = strD "/dev/sda" "Install disk (disko).";
      ups = {
        enable = bool false ''
          A UPS on this router (NUT): the router reads it, serves it to the LAN (upsd on TCP
          3493, user `upsmon` with the secret `nut-password`, e.g. for Home Assistant) and
          shuts itself down when the battery runs low, then has the UPS cut its power.
        '';
        name = strD "ups" "Name of the UPS in NUT (what clients ask for, e.g. `ups@<router>`).";
        driver = strD "usbhid-ups" "NUT driver of the UPS.";
        port = strD "auto" "Port of the UPS for the driver (`auto` for USB).";
      };
    };

    system = {
      watchdog = typedD (types.strMatching "[0-9]+[smh]") "60s" ''
        Hardware watchdog timeout (`<n>s`, `<n>m`, `<n>h`; `0s` = off): systemd pets the watchdog
        device, and if the system hangs for this long, the hardware resets it. Needs a watchdog
        device (a Proxmox VM: q35 has one built in; without one, e.g. a cloud VM: `0s`).
      '';
      gc = {
        olderThan = typedD (types.strMatching "[0-9]+d") "7d" ''
          Garbage collection (daily) deletes system generations older than this (`<n>d`).
        '';
        keep = typedD types.ints.positive 3 ''
          Garbage collection keeps at most this many system generations (the newest, the
          current one included), even if they are younger than gc.olderThan; also the number
          of boot entries.
        '';
      };
    };
  };
}
