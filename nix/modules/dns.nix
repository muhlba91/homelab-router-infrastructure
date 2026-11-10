# DNS (AdGuard Home) for the LAN, other sites and the router itself. mutableSettings: Nix
# owns only the keys under `settings`, a marked block inside the custom filtering rules
# (user_rules, dns-managed-rules.nix) and the user `admin` (password: secret adguard-password-hash).
# Everything else stays runtime state: the rules external-dns writes through the API (it only
# manages its own), manual rules, rewrites.
# Who may query or open the UI is decided by the firewall (router.firewall.services).
{
  config,
  lib,
  pkgs,
  rlib,
  ...
}:
let
  cfg = config.router;

  # The site's own domain is answered by this router's AdGuard (its rewrites, so CNAME targets
  # inside the domain resolve too), like the other sites' domains by theirs.
  ownDomain = "[/${cfg.site.domain}/]${cfg.derived.lanAddr4}";

  # Filter exceptions for every site (services that break behind the blocklists).
  allowRules = [
    "@@||apps.apple.com^$important"
    "@@||itunes.apple.com^$important"
    "@@||adobe.com^$important"
    "@@||fonts.gstatic.com^$important"
    "@@||smartclip.net^$important"
    "@@||prod.http1.netflix.com^$important"
    "@@||collector.github.com^$important"
    "@@||backblazeb2.com^$important"
    "@@||flutter.dev^$important"
    "@@||firebaseinstallations.googleapis.com^$important"
    "@@||firebaselogging-pa.googleapis.com^$important"
    "@@||analytics.console.aws.a2z.com^$important"
    "@@||sentry.io^$important"
    "@@||sentry-cdn.com^$important"
    "@@||newrelic.com^$important"
    "@@||segment.io^$important"
    "@@||revenuecat.com^$important"
    "@@||onesignal.com^$important"
    "@@||privacy-mgmt.com^$important"
    "@@||events.launchdarkly.com^$important"
    "@@||gemini.google.com^$important"
    "@@/^data-[0-9a-f]{10}\\./$important"
  ];

  hash = config.router.secrets.adguard-password-hash.path;

  # Blocklists: AdGuard's own, plus broader tracker/ad lists for what it misses.
  blocklists = [
    {
      name = "AdGuard DNS filter";
      url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
    }
    {
      name = "NoTracking";
      url = "https://raw.githubusercontent.com/notracking/hosts-blocklists/master/adblock/adblock.txt";
    }
    {
      name = "OISD";
      url = "https://abp.oisd.nl";
    }
    {
      name = "HaGeZi Multi PRO - Extended Protection";
      url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
    }
  ];

  managedRules = import ./dns-managed-rules.nix {
    inherit pkgs;
    rules = allowRules ++ cfg.dns.extraRules;
    passwordHashFile = hash;
  };
in
{
  router.secrets.adguard-password-hash.reload = "systemctl try-restart adguardhome.service";

  # Runs after the module's own preStart (settings merge). `+`: as root without the unit's
  # seccomp filter (yq-go dies with SIGSYS under it). The new file gets the old one's
  # owner/mode (AdGuard's dynamic user) and replaces it atomically (`mv`, same directory).
  # Fail-safe: the config is only rewritten when every step worked; otherwise it stays as
  # it was and AdGuard starts anyway.
  systemd.services.adguardhome.serviceConfig.ExecStartPre = lib.mkAfter [
    "+${lib.getExe managedRules}"
  ];

  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    host = "0.0.0.0";
    port = 3000;
    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "tls://dns10.quad9.net"
          ownDomain
        ]
        ++ lib.remove ownDomain cfg.dns.conditionalForwards;
        bootstrap_dns = rlib.quad9.v4 ++ rlib.quad9.v6;
        upstream_mode = "load_balance";
        enable_dnssec = true;
        refuse_any = true;
        ratelimit = 1000; # queries/s per client: far above normal use, stops a runaway client
        cache_enabled = true;
        cache_size = 4194304; # bytes (4 MiB)
        cache_optimistic = true;
        blocked_hosts = [
          "version.bind"
          "id.server"
          "hostname.bind"
        ];
        trusted_proxies = [
          "127.0.0.0/8"
          "::1/128"
        ];
      };
      querylog.interval = "7d";
      statistics.interval = "30d";
      filtering.blocking_mode = "nxdomain";
      filters = lib.imap1 (id: l: {
        inherit id;
        inherit (l) name url;
        enabled = true;
      }) blocklists;
    };
  };
}
