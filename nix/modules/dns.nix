# DNS (AdGuard Home) for the LAN, other sites and the router itself. mutableSettings: Nix
# owns only the keys under `settings`, a marked block inside the custom filtering rules
# (user_rules, below) and the user `admin` (password: secret adguard-password-hash).
# Everything else stays runtime state: the rules external-dns writes through the API (it only
# manages its own), manual rules, rewrites.
# Who may query or open the UI is decided by the firewall (router.firewall.services).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.router;

  # Filter exceptions for every site.
  commonRules = [
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
  ];

  # Managed block in user_rules, delimited by comment rules (`!`): replaced before every
  # start, everything outside it is kept (external-dns owns only its own rules). A changed
  # rule list changes the unit, so a deploy restarts AdGuard and applies it.
  block = pkgs.writeText "adguard-managed-rules.json" (
    builtins.toJSON (
      [ "! BEGIN managed by nix (modules/dns.nix), edits inside are overwritten" ]
      ++ commonRules
      ++ cfg.dns.extraRules
      ++ [ "! END managed by nix" ]
    )
  );
  # Old block out, new block in at the end; copies of managed rules outside the block are
  # dropped (e.g. the unmarked ones of a migrated config). An unclosed BEGIN keeps its rules.
  filter = pkgs.writeText "adguard-managed-rules.jq" ''
    $blk[0] as $new | $new[0] as $b | $new[-1] as $e
    | reduce .[] as $l ({o: [], k: [], in: false};
        if $l == $b then .in = true | .k = []
        elif $l == $e then .in = false | .k = []
        elif .in then .k += [$l]
        else .o += [$l] end)
    | (.o + .k | map(select(. as $x | any($new[]; . == $x) | not))) + $new
  '';
  hash = config.router.secrets.adguard-password-hash.path;
  yq = lib.getExe pkgs.yq-go;
  jq = lib.getExe pkgs.jq;
in
{
  router.secrets.adguard-password-hash.reload = "systemctl try-restart adguardhome.service";

  # Runs after the module's own preStart (settings merge). `+`: as root without the unit's
  # seccomp filter (yq-go dies with SIGSYS under it). The new file gets the old one's
  # owner/mode (AdGuard's dynamic user) and replaces it atomically (`mv`, same directory).
  # Fail-safe: the config is only rewritten when every step worked; otherwise it stays as
  # it was and AdGuard starts anyway.
  systemd.services.adguardhome.serviceConfig.ExecStartPre = lib.mkAfter [
    "+${pkgs.writeShellScript "adguardhome-managed-rules" ''
      conf="$STATE_DIRECTORY/AdGuardHome.yaml"
      export RULES="$RUNTIME_DIRECTORY/managed-rules.json" NEW="$conf.new" HASH
      HASH=$(cat ${hash})
      if (set -o pipefail; ${yq} -o json '.user_rules // []' "$conf" | ${jq} --slurpfile blk ${block} -f ${filter} > "$RULES") \
        && [ -s "$RULES" ] && [ -n "$HASH" ] && cp "$conf" "$NEW" \
        && ${yq} -i '.user_rules = load(strenv(RULES)) | .user_rules style="" | .users = [{"name": "admin", "password": strenv(HASH)}]' "$NEW" \
        && chown --reference="$conf" "$NEW" && chmod --reference="$conf" "$NEW" \
        && mv "$NEW" "$conf"; then
        echo "managed rules and user applied"
      else
        echo "managed rules and user NOT applied, config left unchanged" >&2
      fi
      rm -f "$RULES" "$NEW"
    ''}"
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
        upstream_dns = [ "tls://dns10.quad9.net" ] ++ cfg.dns.conditionalForwards;
        bootstrap_dns = [
          "9.9.9.10"
          "149.112.112.10"
          "2620:fe::10"
          "2620:fe::fe:10"
        ];
        upstream_mode = "load_balance";
        enable_dnssec = true;
        refuse_any = true;
        ratelimit = 1000;
        cache_enabled = true;
        cache_size = 4194304;
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
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = true;
          url = "https://raw.githubusercontent.com/notracking/hosts-blocklists/master/adblock/adblock.txt";
          name = "NoTracking";
          id = 2;
        }
        {
          enabled = true;
          url = "https://abp.oisd.nl";
          name = "OISD";
          id = 3;
        }
        {
          enabled = true;
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
          name = "HaGeZi Multi PRO - Extended Protection";
          id = 4;
        }
      ];
    };
  };
}
