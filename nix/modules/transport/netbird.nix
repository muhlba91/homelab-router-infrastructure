# Transport: the NetBird client, the encrypted underlay. Routers only use it to reach each
# other's overlay IPs (VXLAN and BGP to the hub run on top, modules/evpn.nix), so NetBird
# does no routing or DNS here. With enforcePolicies its firewall (own nft tables) filters
# the traffic arriving on wt0, and our nftables are the fallback while it is down.
# The setup key is a file (router.secrets), only used for the first login: the client
# keeps its identity in its state directory afterwards.
# The client is nixpkgs' package and may be older than the hub's server (0.71.4 against a
# 0.80.0 server works); test a server upgrade on the lab first.
{
  config,
  lib,
  ...
}:
let
  cfg = config.router;
  nb = cfg.transport.netbird;
in
{
  config = lib.mkIf nb.enable {
    # root 0400, read via systemd LoadCredential. A pushed key re-runs the login unit: it
    # only calls `netbird up` when the daemon says NeedsLogin (e.g. after a NetBird server
    # reinstall), so routine pushes leave a connected client alone.
    router.secrets."netbird-setup-key".reload = "systemctl restart netbird-backbone-login.service";

    services.netbird.clients.backbone = {
      interface = nb.iface;
      inherit (nb) port;
      openFirewall = false; # modules/firewall.nix
      openInternalFirewall = false;
      login = {
        enable = true;
        setupKeyFile = cfg.secrets."netbird-setup-key".path;
      };
      # Read by `netbird up` at the first login (the URL is then kept in the state).
      environment.NB_MANAGEMENT_URL = nb.managementUrl;
      # Merged into config.json before every start (survives re-logins and upgrades).
      config = {
        MTU = nb.mtu;
        DisableClientRoutes = true;
        DisableServerRoutes = true;
        DisableDNS = true;
        DisableFirewall = !nb.enforcePolicies;
      };
    };
    # The daemon reads that file only at start: a changed setting restarts it (brief overlay
    # outage; the EVPN devices follow wt0, see evpn.nix).
    systemd.services.netbird-backbone.restartTriggers = [
      config.environment.etc."netbird-backbone/config.d/50-nixos.json".source
    ];
  };
}
