# Vars schema: DNS (AdGuard), observability (metrics, logs), security (CrowdSec).
{ lib, ... }:
let
  inherit (lib) types;
  inherit (import ./types.nix { inherit lib; })
    bool
    nullable
    strList
    typedD
    ;
in
{
  options.router = {
    observability.monitoring.prometheus = {
      enable = bool false ''
        Prometheus exporters, scraped from outside; the firewall service `metrics` (lan, trusted;
        overridable) opens their ports. vnstat runs regardless (local only).
      '';
      exporters =
        typedD
          (types.listOf (
            types.enum [
              "node"
              "kea"
              "frr"
              "smartctl"
              "crowdsec"
              "nut"
            ]
          ))
          [
            "node"
            "kea"
            "frr"
            "crowdsec"
          ]
          ''
            Exporters (ports): node (9100, the system), kea (9547, DHCP leases and pools), frr
            (9342, BGP/EVPN), smartctl (9633, disk health; physical disks only), crowdsec (6060,
            its own metrics; needs security.crowdsec), nut (9199, the UPS; needs hardware.ups).
          '';
    };

    observability.logging.vector = {
      enable = bool false "Ship the journal to a central Vector (its `vector` source).";
      address = nullable types.str "host:port of the receiving Vector, e.g. `10.0.0.10:6000`.";
    };

    security.crowdsec = {
      enable = bool true ''
        CrowdSec: bans the sources of attacks detected in sshd's log and the firewall's drop log
        (firewall.logDrops: without it no port scans are seen), plus the community blocklist.
        Our networks (trusted, LAN, publicV6) are never banned by a detection. Needs internet
        access when it starts (hub and online API).
      '';
      banDuration =
        typedD (types.strMatching "[0-9]+[smh]") "4h"
          "How long a detected source stays banned.";
    };

    dns.extraRules = strList [ ] ''
      AdGuard filtering rules of this site, added to the managed block after the common
      ones of modules/dns.nix. Rules outside the block (external-dns) are never touched.
    '';

    dns.conditionalForwards = strList [ ] ''
      AdGuard `[/domain/]server` conditional forwards; server = the other router's LAN address.
      For a site still on OPNsense use its tunnel address (its AdGuard would answer a query to
      its LAN address with the wrong source).
    '';
  };
}
