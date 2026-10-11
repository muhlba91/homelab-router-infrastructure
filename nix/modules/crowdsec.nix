# CrowdSec (router.security.crowdsec): detects attacks (brute force, port scans) in sshd's
# log and the firewall's drop log and bans their sources, plus the community blocklist. The
# bouncer applies the bans in its own nftables tables (`crowdsec`, `crowdsec6`, before our
# filter), which our reloads leave alone. Local API 127.0.0.1:8080; state and API
# credentials (created on the first start) in /var/lib/crowdsec. Optionally enrolled once in
# the CrowdSec console (security.crowdsec.console).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.router;
  cs = cfg.security.crowdsec;
  state = "/var/lib/crowdsec/state";
  inherit (config.services.crowdsec) user group;
  # The console's sharing options: `cscli console enroll` rewrites this file, so it must not
  # live in the store. Seeded from the module's options (all sharing off).
  consoleConfig = "${state}/console.yaml";
  enrolled = "${state}/console-enrolled";
  # Never banned by a detection: our networks (a manual decision still applies).
  ownNets =
    cfg.trusted.v4
    ++ cfg.trusted.v6
    ++ [
      cfg.lan.v4Net
      cfg.lan.v6Net
    ]
    ++ map (p: p.prefix) cfg.publicV6;
  remediation = scope: {
    name = "default_${lib.toLower scope}_remediation";
    filters = [ "Alert.Remediation == true && Alert.GetScope() == '${scope}'" ];
    decisions = [
      {
        type = "ban";
        duration = cs.banDuration;
      }
    ];
    on_success = "break";
  };
  bouncerFamily = table: {
    enabled = true;
    set-only = false; # the bouncer owns its table and chains
    inherit table;
    chain = "crowdsec-chain";
    priority = -10;
  };
in
lib.mkMerge [
  {
    assertions = [
      {
        assertion = !cs.console.enable || cs.enable;
        message = "router.security.crowdsec.console.enable needs router.security.crowdsec.enable";
      }
    ];
  }
  (lib.mkIf cs.enable {
    services.crowdsec = {
      enable = true;
      hub.collections = [
        "crowdsecurity/linux" # sshd, syslog, whitelists of private ranges
        "crowdsecurity/iptables" # kernel firewall log lines (ours: nft-drop-*), port scans
      ];
      localConfig = {
        acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
            labels.type = "syslog";
          }
          {
            source = "journalctl";
            journalctl_filter = [ "_TRANSPORT=kernel" ];
            labels.type = "syslog";
          }
        ];
        parsers.s02Enrich = [
          {
            name = "router/own-networks";
            description = "Never ban our own networks";
            whitelist = {
              reason = "own network";
              cidr = ownNets;
            };
          }
        ];
        profiles = [
          (remediation "Ip")
          (remediation "Range")
        ];
      };
      settings = {
        general.api.server.enable = true;
        lapi.credentialsFile = "${state}/local_api_credentials.yaml";
        capi.credentialsFile = "${state}/online_api_credentials.yaml";
      };
    };

    # Workarounds for the NixOS modules:
    # * the online API's credentials file must exist (empty) before the first registration;
    # * the bouncer's registration runs a bare `cscli` (reads /etc/crowdsec/config.yaml) and,
    #   as a dynamic user, would move /var/lib/crowdsec to /var/lib/private;
    # * the bouncer must start after its registration (else it misses the API key);
    # * crowdsec.service needs its directories at start (a deploy creates them in parallel).
    systemd.tmpfiles.settings."11-crowdsec-capi"."${state}/online_api_credentials.yaml".f = {
      inherit user group;
      mode = "0600";
    };
    environment.etc."crowdsec/config.yaml".source =
      (pkgs.formats.yaml { }).generate "crowdsec.yaml"
        config.services.crowdsec.settings.general;

    systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
      DynamicUser = lib.mkForce false;
      StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
    };
    systemd.services.crowdsec-firewall-bouncer.after = [ "crowdsec-firewall-bouncer-register.service" ];
    systemd.services.crowdsec-dirs = {
      description = "Create the CrowdSec directories";
      before = [ "crowdsec.service" ];
      requiredBy = [ "crowdsec.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/var/lib/crowdsec --prefix=/etc/crowdsec";
      };
    };

    services.crowdsec-firewall-bouncer = {
      enable = true;
      createRulesets = false;
      settings = {
        nftables = {
          ipv4 = bouncerFamily "crowdsec";
          ipv6 = bouncerFamily "crowdsec6";
        };
        nftables_hooks = [
          "input"
          "forward"
        ];
      };
    };
  })

  (lib.mkIf (cs.enable && cs.console.enable) {
    router.secrets.crowdsec-enroll-key = {
      owner = user;
      inherit group;
    };

    services.crowdsec.settings.general.api.server.console_path = consoleConfig;
    # Installed (not by tmpfiles: it refuses to hand a root-created file in crowdsec's
    # directory over to crowdsec) when missing or not crowdsec's, before crowdsec starts.
    systemd.services.crowdsec-dirs.serviceConfig.ExecStartPost =
      let
        seed =
          (pkgs.formats.yaml { }).generate "console.yaml"
            config.services.crowdsec.settings.console.configuration;
      in
      pkgs.writeShellScript "crowdsec-console-config" ''
        [ "$(stat -c %U ${consoleConfig} 2>/dev/null)" = ${user} ] \
          || install -o ${user} -g ${group} -m 0600 ${seed} ${consoleConfig}
      '';

    # Once: the marker keeps it from asking the console again on every boot. All sharing
    # options stay off (`--disable all`); the router then waits for acceptance in the console.
    systemd.services.crowdsec-console-enroll = {
      description = "Enroll CrowdSec in the console";
      after = [
        "crowdsec.service"
        "network-online.target"
      ];
      wants = [
        "crowdsec.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = "!${enrolled}";
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        Restart = "on-failure";
        RestartSec = "5min";
      };
      script = ''
        ${lib.getExe' config.services.crowdsec.package "cscli"} -c /etc/crowdsec/config.yaml \
          console enroll --disable all --name ${config.networking.hostName} \
          "$(cat ${config.router.secrets.crowdsec-enroll-key.path})"
        touch ${enrolled}
      '';
    };
  })
]
