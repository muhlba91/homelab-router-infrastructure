# `./router dump <site>` (flake output `routerDump.<site>`): the evaluated parts of a site
# that matter for behaviour, as JSON. Diff two dumps to prove a refactor changes nothing
# (or exactly what was intended). `drv` alone answers "identical or not".
c:
let
  l = builtins;
in
{
  drv = c.system.build.toplevel.drvPath;
  frr = c.services.frr.config;
  nft = l.mapAttrs (_: t: t.family + "\n" + t.content) c.networking.nftables.tables;
  networkd = l.mapAttrs (_: u: u.text) c.systemd.network.units;
  networkdConf = c.environment.etc."systemd/networkd.conf".text or "";
  kea4 = c.services.kea.dhcp4.settings;
  kea6 = c.services.kea.dhcp6.settings;
  radvd = c.services.radvd.config;
  adguard = c.services.adguardhome.settings;
  adguardStartPre = map toString c.systemd.services.adguardhome.serviceConfig.ExecStartPre;
  sysctl = c.boot.kernel.sysctl;
  secrets = c.router.secrets;
  secretsActivation = c.system.activationScripts.routerSecrets.text or "";
}
