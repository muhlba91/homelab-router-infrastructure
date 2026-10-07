# All router modules. Which ones do something is decided by router.* (vars).
{
  imports = [
    ./options
    ./helpers.nix
    ./derived.nix
    ./secrets.nix
    ./base.nix
    ./networking.nix
    ./firewall.nix
    ./crowdsec.nix
    ./dhcp.nix
    ./ra.nix
    ./dns.nix
    ./time.nix
    ./monitoring.nix
    ./logging.nix
    ./ups.nix
    ./bgp.nix
    ./evpn.nix
    ./transport/netbird.nix
    ./health.nix
  ];
}
