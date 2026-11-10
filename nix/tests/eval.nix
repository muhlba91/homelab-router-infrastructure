# Eval tests (flake check `eval`, lib.runTests) on the fixtures in tests/sites, independent
# of the site data ./router injects: what the modules derive from the vars, and that invalid
# vars fail evaluation (the assertions and the typed options). Empty result = all pass.
{ lib, fixtures }:
let
  spoke = fixtures.fixture-spoke;
  home = fixtures.fixture-home;

  # Whether a fixture still evaluates with one more module (a failed assertion or a wrong
  # option value throws).
  evaluates =
    system: module:
    (builtins.tryEval
      (system.extendModules { modules = [ module ]; }).config.system.build.toplevel.drvPath
    ).success;
  fails = system: module: !(evaluates system module);
  # The messages of the failed assertions of a fixture with one more module (without
  # forcing the system: tells which assertion fired, not just that something threw).
  violations =
    system: module:
    map (a: a.message) (
      lib.filter (a: !a.assertion) (system.extendModules { modules = [ module ]; }).config.assertions
    );
  with' = system: module: system.extendModules { modules = [ module ]; };
  rules = s: s.config.networking.nftables.tables.router.content;
  nat4 = s: s.config.networking.nftables.tables.nat4.content;
  has = text: lib.hasInfix text;
  peer = name: address: {
    inherit name address;
    remoteAs = 64511;
  };
  multihopPeer = name: address: {
    inherit name address;
    remoteAs = 64511;
    multihop = 2;
  };
in
lib.runTests {
  # Derived values.
  # site.hostname defaults to site.name (fixture-home sets none) and can be overridden.
  testHostnames = {
    expr = {
      default = home.config.networking.hostName;
      override = (with' home { router.site.hostname = "gw"; }).config.networking.hostName;
    };
    expected = {
      default = "fixture-home";
      override = "gw";
    };
  };
  testNat66OnlyForUla = {
    expr =
      lib.mapAttrs (_: s: s.config.networking.nftables.tables ? nat6 && s.config.router.nat66.enable)
        {
          inherit spoke home;
        };
    expected = {
      spoke = true;
      home = false;
    };
  };
  # The qemu profile boots with either firmware: GRUB on the disk (BIOS) and on the ESP's
  # removable path (UEFI).
  testBootLoader = {
    expr =
      let
        inherit (spoke.config.boot.loader) grub;
      in
      {
        inherit (grub)
          enable
          efiSupport
          efiInstallAsRemovable
          devices
          ;
        boot = spoke.config.fileSystems."/boot".fsType;
      };
    expected = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      devices = [ spoke.config.router.hardware.disk ];
      boot = "vfat";
    };
  };
  # The n100 profile: systemd-boot on the ESP (no EFI variables), no GRUB, the TCO watchdog.
  testBootLoaderN100 = {
    expr = {
      systemdBoot = home.config.boot.loader.systemd-boot.enable;
      grub = home.config.boot.loader.grub.enable;
      efiVariables = home.config.boot.loader.efi.canTouchEfiVariables;
      watchdog = lib.elem "iTCO_wdt" home.config.boot.kernelModules;
      disk = home.config.disko.devices.disk.main.device;
      boot = home.config.fileSystems."/boot".fsType;
    };
    expected = {
      systemdBoot = true;
      grub = false;
      efiVariables = false;
      watchdog = true;
      disk = "/dev/disk/by-id/nvme-EXAMPLE_0000";
      boot = "vfat";
    };
  };
  # A pinned host key: sshd offers only the secret's key and does not generate one; without
  # a pin, its own keys.
  testHostKey = {
    expr = lib.mapAttrs (_: s: {
      keys = map (k: "${k.type} ${k.path}") s.config.services.openssh.hostKeys;
      secret = s.config.router.secrets ? ssh-host-key;
      keygen = s.config.systemd.services.sshd-keygen.enable;
    }) { inherit spoke home; };
    expected = {
      spoke = {
        keys = [ "ed25519 /var/lib/secrets/ssh-host-key" ];
        secret = true;
        keygen = false;
      };
      home = {
        keys = [
          "rsa /etc/ssh/ssh_host_rsa_key"
          "ed25519 /etc/ssh/ssh_host_ed25519_key"
        ];
        secret = false;
        keygen = true;
      };
    };
  };
  # Key-only login for the deploy user and nobody else.
  testSshAllowUsers = {
    expr = spoke.config.services.openssh.settings.AllowUsers;
    expected = [ spoke.config.users.users.deploy.name ];
  };
  testUpsService = {
    expr = lib.mapAttrs (_: s: s.config.router.firewall.services ? nut) { inherit spoke home; };
    expected = {
      spoke = false;
      home = true;
    };
  };
  # DHCPv6 on the WAN: solicit without an RA; replies accepted from any source (some servers
  # answer from ::).
  testWanDhcp6 = {
    expr =
      let
        net = home.config.systemd.network.networks."11-wan";
        rules = home.config.networking.nftables.tables.router.content;
      in
      {
        withoutRa = net.dhcpV6Config.WithoutRA;
        reply = lib.hasInfix ''iifname "wan0.31" udp sport 547 udp dport 546 accept'' rules;
      };
    expected = {
      withoutRa = "solicit";
      reply = true;
    };
  };
  # CrowdSec console: the enroll key is a secret, enrollment a once-only unit, the console
  # config writable outside the store.
  testCrowdsecConsole = {
    expr =
      let
        c =
          (spoke.extendModules { modules = [ { router.security.crowdsec.console.enable = true; } ]; }).config;
      in
      {
        secret = c.router.secrets ? crowdsec-enroll-key;
        unit = c.systemd.services ? crowdsec-console-enroll;
        consolePath = c.services.crowdsec.settings.general.api.server.console_path;
        off = spoke.config.systemd.services ? crowdsec-console-enroll;
      };
    expected = {
      secret = true;
      unit = true;
      consolePath = "/var/lib/crowdsec/state/console.yaml";
      off = false;
    };
  };
  # The Vector sink names its scheme (the default of a scheme-less address changes upstream).
  testVectorAddress = {
    expr = lib.hasPrefix "http://" home.config.services.vector.settings.sinks.central.address;
    expected = true;
  };
  # The site's own domain is forwarded to the router's LAN address, next to the configured forwards.
  testDnsOwnDomain = {
    expr = home.config.services.adguardhome.settings.dns.upstream_dns;
    expected = [
      "tls://dns10.quad9.net"
      "[/home.example.org/]${home.config.router.derived.lanAddr4}"
      "[/spoke.example.org/]10.71.0.1"
    ];
  };
  testMetricsPorts = {
    expr = lib.sort lib.lessThan home.config.router.firewall.services.metrics.ports;
    expected = [
      6060
      9100
      9199
      9342
      9547
      9633
    ];
  };
  # The router's own IPv4 traffic to other sites is sourced from its LAN address (IPv6: the
  # kernel refuses a source outside the VRF, every leaked route would fail to install).
  testMeshSource = {
    expr =
      let
        frr = spoke.config.services.frr.config;
      in
      {
        v4Source = has "set src ${spoke.config.router.derived.lanAddr4}" frr;
        v4Protocol = has "ip protocol bgp route-map SRC4" frr;
        v6Protocol = has "ipv6 protocol bgp" frr;
      };
    expected = {
      v4Source = true;
      v4Protocol = true;
      v6Protocol = false;
    };
  };
  testTransitMarker = {
    expr = lib.hasInfix "64500:0:1" home.config.services.frr.config;
    expected = true;
  };

  # LAN -> LAN hairpin is accepted before the conntrack check (asymmetric replies).
  testFirewallHairpin = {
    expr =
      let
        chain = lib.last (lib.splitString "chain forward {" (rules home));
        before = lib.head (lib.splitString "ct state vmap" chain);
      in
      has "oifname \"${home.config.router.derived.lanIf}\" accept" before;
    expected = true;
  };

  # Firewall exposure: the defaults of every site.
  testFirewallDefaultDrop = {
    expr = lib.mapAttrs (
      _: s:
      lib.genAttrs [ "input" "forward" ] (
        h: has "type filter hook ${h} priority filter; policy drop;" (rules s)
      )
    ) { inherit spoke home; };
    expected = {
      spoke = {
        input = true;
        forward = true;
      };
      home = {
        input = true;
        forward = true;
      };
    };
  };
  testFirewallDefaultServices = {
    expr = lib.mapAttrs (_: v: v.from) (
      lib.filterAttrs (_: v: v.enable) spoke.config.router.firewall.services
    );
    expected = {
      dhcp = [ "lan" ];
      dns = [
        "lan"
        "mesh"
        "trusted"
      ];
      dns-ui = [
        "lan"
        "trusted"
      ];
      ntp = [ "lan" ];
      ssh = [
        "lan"
        "trusted"
      ];
    };
  };
  # The underlay: WireGuard not from the mesh, never out through it (no tunnel inside
  # itself), VXLAN only from the overlay range on wt0.
  testFirewallUnderlay = {
    expr = lib.mapAttrs (_: r: has r (rules spoke)) {
      wireguardIn = ''iifname != { "br50001", "mesh" } udp dport 51820 accept'';
      wireguardOut = ''oifname { "br50001", "mesh" } udp sport 51820 drop'';
      vxlan = ''iifname "wt0" ip saddr 10.253.0.0/16 udp dport 4789 accept'';
    };
    expected = {
      wireguardIn = true;
      wireguardOut = true;
      vxlan = true;
    };
  };
  # BGP and BFD from a peer bound to an interface are accepted from that interface only;
  # peers without one stay in the sets.
  testFirewallBgpPeers =
    let
      c = with' home {
        router.bgp.peers = [
          (peer "hub" "2001:db8:ffff::2")
          (peer "hub4" "198.51.100.2")
        ];
      };
      bfd = with' home {
        router.bgp.peers = lib.mkForce (map (p: p // { bfd = true; }) home.config.router.bgp.peers);
      };
      r = rules c;
      bound = "iifname \"lan0\" ip6 saddr 2001:db8:72:1:1000::1";
    in
    {
      expr = {
        bgpBound = has "${bound} tcp dport 179 accept" r;
        bgpSet6 = has "set bgp_peers6 { type ipv6_addr; elements = { 2001:db8:ffff::2 } }" r;
        bgpSet4 = has "set bgp_peers4 { type ipv4_addr; elements = { 198.51.100.2 } }" r;
        bgpUnbound = has "ip6 saddr @bgp_peers6 tcp dport 179 accept" r;
        bfdOff = has "3784" r;
        bfdBound = has "${bound} udp dport { 3784, 4784 } accept # BFD" (rules bfd);
        # a bound peer alone needs no set at all
        bfdNoSet = has "bgp_peers" (rules bfd);
      };
      expected = {
        bgpBound = true;
        bgpSet6 = true;
        bgpSet4 = true;
        bgpUnbound = true;
        bfdOff = false;
        bfdBound = true;
        bfdNoSet = false;
      };
    };
  # Echo requests from the WAN are limited per source (icmp and icmpv6 only), every other
  # ICMP type stays accepted.
  testIcmpEchoRate =
    let
      r = rules (with' spoke { router.firewall.icmpEchoRate = "5/minute"; });
    in
    {
      expr = {
        v4 = has ''iifname "wan0" icmp type echo-request meter icmp_echo4 { ip saddr limit rate over 5/minute } drop'' r;
        v6 = has ''iifname "wan0" icmpv6 type echo-request meter icmp_echo6 { ip6 saddr limit rate over 5/minute } drop'' r;
        default = has "limit rate over 10/second" (rules spoke);
        otherTypesAccepted = has "ip protocol icmp accept" r && has "ip6 nexthdr icmpv6 accept" r;
        invalid = fails spoke { router.firewall.icmpEchoRate = "fast"; };
      };
      expected = {
        v4 = true;
        v6 = true;
        default = true;
        otherTypesAccepted = true;
        invalid = true;
      };
    };
  # Trusted networks reach the router's services and the LAN from the WAN only with onWan.
  testTrustedOnWan =
    let
      off = with' spoke { router.trusted.onWan = lib.mkForce false; };
      state = s: {
        inputOnWan = !has ''iifname != "wan0" ip saddr @trusted4'' (rules s);
        forwardToLan = has ''iifname "wan0" oifname "lan0" ip saddr @trusted4 accept'' (rules s);
      };
    in
    {
      expr = {
        on = state spoke;
        off = state off;
      };
      expected = {
        on = {
          inputOnWan = true;
          forwardToLan = true;
        };
        off = {
          inputOnWan = false;
          forwardToLan = false;
        };
      };
    };
  # DNAT of a v4 forward: restricted to its sources when it has them, from the WAN only.
  testDnatForwards = {
    expr = {
      restricted = has ''iifname "wan0" ip saddr { 198.51.100.0/24 } tcp dport { 443 } dnat to 10.71.0.10'' (
        nat4 spoke
      );
      open = has ''iifname "wan0.31" tcp dport { 80, 443 } dnat to 10.72.72.2'' (nat4 home);
    };
    expected = {
      restricted = true;
      open = true;
    };
  };
  # The drop log (input and forward) can be switched off.
  testLogDrops = {
    expr = map (c: has "nft-drop-" (rules c)) [
      spoke
      (with' spoke { router.firewall.logDrops.enable = false; })
    ];
    expected = [
      true
      false
    ];
  };
  # Announcing the WAN net needs a static address; the IPv6 one a ULA.
  testWanAnnounce =
    let
      v6 = module: violations spoke ({ router.wan.v6.announce = true; } // module);
    in
    {
      expr = {
        v4Dhcp = violations home { router.wan.v4.announce = true; };
        v6Global = v6 { };
        v6Ula = v6 { router.wan.v6.address = lib.mkForce "fd00:1::10/64"; };
      };
      expected = {
        v4Dhcp = [ "router.wan.v4.announce needs a static WAN IPv4 address" ];
        v6Global = [ "router.wan.v6.announce needs a static WAN IPv6 ULA address (fc00::/7)" ];
        v6Ula = [ ];
      };
    };
  # The LAN addressing must be consistent: the router address, the supernet and the DHCP
  # pools inside the networks they belong to.
  testLanValidation = {
    expr =
      lib.mapAttrs (_: module: map (m: lib.head (lib.splitString " " m)) (violations spoke module))
        {
          v4OutsideNet.router.lan.v4 = lib.mkForce "10.99.0.1/16";
          v6OutsideNet.router.lan.v6 = lib.mkForce "fd99::1/64";
          netOutsideSupernet.router.lan.v6Net = lib.mkForce "fd72:0:0:1::/64";
          pool4Outside.router.dhcp.pool4 = lib.mkForce "10.99.150.1 - 10.99.199.255";
          pool6Outside.router.dhcp.pool6 = lib.mkForce "fd99::1 - fd99::ffff";
          pool4Half.router.dhcp.pool4 = lib.mkForce "10.71.150.1 - 10.99.199.255";
          valid.router.dhcp.pool4 = lib.mkForce "10.71.1.1 - 10.71.1.9";
        };
    expected = {
      v4OutsideNet = [ "router.lan.v4" ];
      v6OutsideNet = [ "router.lan.v6" ];
      # (the moved network also takes the router address and the pool out of it)
      netOutsideSupernet = [
        "router.lan.v6"
        "router.lan.v6Net"
        "router.dhcp.pool6"
      ];
      pool4Outside = [ "router.dhcp.pool4" ];
      pool6Outside = [ "router.dhcp.pool6" ];
      pool4Half = [ "router.dhcp.pool4" ];
      valid = [ ];
    };
  };
  # Secrets: a path unit and a service per declared secret (permissions re-applied and the
  # reload run when the file changes); a malformed mode is rejected.
  testSecrets =
    let
      c = with' spoke {
        router.secrets.demo = {
          owner = "deploy";
          mode = "0640";
          reload = "systemctl reload demo.service";
        };
      };
    in
    {
      expr = {
        path = c.config.router.secrets.demo.path;
        watched = c.config.systemd.paths.router-secret-demo.pathConfig.PathChanged;
        ownerAndMode = has "deploy:root:640" c.config.systemd.services.router-secret-demo.script;
        reload = has "systemctl reload demo.service" c.config.systemd.services.router-secret-demo.script;
        bad = map (mode: fails spoke { router.secrets.demo.mode = mode; }) [
          "rw"
          "u+r"
          "0999"
        ];
        defaultMode = spoke.config.router.secrets.ssh-host-key.mode;
      };
      expected = {
        path = "/var/lib/secrets/demo";
        watched = "/var/lib/secrets/demo";
        ownerAndMode = true;
        reload = true;
        bad = [
          true
          true
          true
        ];
        defaultMode = "0400";
      };
    };
  # The watchdog is armed with the timeout, `0s` (any unit) leaves it off.
  testWatchdog = {
    expr =
      map
        (
          w:
          (with' spoke { router.system.watchdog = w; }).config.systemd.settings.Manager ? RuntimeWatchdogSec
        )
        [
          "60s"
          "0s"
          "0m"
        ];
    expected = [
      true
      false
      false
    ];
  };
  # BGP policy: strict neighbors use the PEER-IN/-OUT maps (own prefixes out, accept lists
  # in); allow-all / deny-all neighbors get their own maps, which strict-only sites omit.
  testBgpPolicy =
    let
      frr = s: s.config.services.frr.config;
      mixed = with' spoke {
        router.bgp.peers = [
          (peer "strict" "198.51.100.1")
          (
            (peer "open" "198.51.100.2")
            // {
              inPolicy = "allow-all";
              outPolicy = "deny-all";
            }
          )
        ];
      };
      f = frr mixed;
    in
    {
      expr = {
        maps = map (m: has m f) [
          "route-map PEER-IN permit 10"
          "route-map PEER-OUT permit 10"
          "route-map PEER-IN6 permit 10"
          "route-map PEER-OUT6 permit 10"
        ];
        strict = map (m: has m f) [
          "neighbor 198.51.100.1 route-map PEER-IN in"
          "neighbor 198.51.100.1 route-map PEER-OUT out"
        ];
        open = map (m: has m f) [
          "neighbor 198.51.100.2 route-map ALLOW-ALL in"
          "neighbor 198.51.100.2 route-map DENY-ALL out"
          "route-map ALLOW-ALL permit 100"
          "route-map DENY-ALL deny 100"
        ];
        strictOnly = has "ALLOW-ALL" (frr spoke);
        # the NetBird underlay is never accepted from a neighbor (EVPN)
        underlayDenied = has "ip prefix-list IN4 seq 5 deny ${spoke.config.router.evpn.underlay4} le 32" f;
      };
      expected = {
        maps = [
          true
          true
          true
          true
        ];
        strict = [
          true
          true
        ];
        open = [
          true
          true
          true
          true
        ];
        strictOnly = false;
        underlayDenied = true;
      };
    };

  # Invalid vars must fail; the control proves `fails` can be false.
  testControlEvaluates = {
    expr = evaluates spoke { router.dns.extraRules = [ "||control.example^" ]; };
    expected = true;
  };
  testDeployableNeedsKeys = {
    expr = fails spoke { router.mgmt.sshKeys = lib.mkForce [ ]; };
    expected = true;
  };
  testEvpnNeedsBgp = {
    expr = fails spoke { router.bgp.enable = lib.mkForce false; };
    expected = true;
  };
  testForwards6NeedNat66 = {
    expr = fails spoke { router.nat66.enable = lib.mkForce false; };
    expected = true;
  };
  testNutExporterNeedsUps = {
    expr = fails home { router.hardware.ups.enable = lib.mkForce false; };
    expected = true;
  };
  testCrowdsecConsoleNeedsCrowdsec = {
    expr = fails spoke {
      router.security.crowdsec = {
        enable = lib.mkForce false;
        console.enable = true;
      };
    };
    expected = true;
  };
  testVectorAddressWithoutScheme = {
    expr = fails home {
      router.observability.logging.vector.address = lib.mkForce "http://10.72.200.1:6000";
    };
    expected = true;
  };
  testTransitNeedsStrict = {
    expr = fails home {
      router.bgp.peers = lib.mkForce (
        map (p: p // { inPolicy = "allow-all"; }) home.config.router.bgp.peers
      );
    };
    expected = true;
  };
  testSiteNameIsDirectory = {
    expr = fails spoke { router.site.name = lib.mkForce "other"; };
    expected = true;
  };
  testInvalidAddress = {
    expr = fails spoke { router.lan.v4 = lib.mkForce "10.71.0.300/16"; };
    expected = true;
  };
  testInvalidPrefixLength = {
    expr = map (v: fails spoke v) [
      { router.lan.v4Net = lib.mkForce "10.71.0.0/33"; }
      { router.lan.v6Net = lib.mkForce "fd71:0:0:1::/129"; }
    ];
    expected = [
      true
      true
    ];
  };
  testInvalidIpv6 = {
    expr = map (v: fails spoke { router.lan.v6 = lib.mkForce v; }) [
      ":/64"
      "fd71::1::1/64"
      "fd71:0:0:1::1/64"
    ];
    expected = [
      true
      true
      false
    ];
  };
  # A multihop peer starts its session from the static WAN address of its own family; a site
  # without one (DHCP) cannot have one.
  testMultihopUpdateSource = {
    expr =
      let
        frr =
          (spoke.extendModules {
            modules = [
              {
                router.bgp.peers = [
                  (multihopPeer "upstream4" "198.51.100.1")
                  (multihopPeer "upstream6" "2001:db8:ffff::1")
                ];
              }
            ];
          }).config.services.frr.config;
      in
      map (l: lib.hasInfix l frr) [
        "neighbor 198.51.100.1 update-source 192.0.2.10"
        "neighbor 2001:db8:ffff::1 update-source 2001:db8:0:1::10"
      ];
    expected = [
      true
      true
    ];
  };
  testMultihopNeedsStaticWan = {
    expr = fails home { router.bgp.peers = [ (multihopPeer "upstream6" "2001:db8:ffff::1") ]; };
    expected = true;
  };
  # The VXLAN MTU follows the NetBird MTU (50 bytes overhead) and may not exceed it.
  testEvpnMtu = {
    expr = [
      spoke.config.router.evpn.mtu
      (spoke.extendModules { modules = [ { router.transport.netbird.mtu = lib.mkForce 1400; } ]; })
      .config.router.evpn.mtu
    ]
    ++ [ (fails spoke { router.evpn.mtu = lib.mkForce 1400; }) ];
    expected = [
      1370
      1350
      true
    ];
  };
  # A hub lost for good restarts the NetBird client (timer + unit); switched off, neither exists.
  # The two Kea servers share a runtime directory and must not start at the same moment.
  testKeaStartOrder = {
    expr = lib.mapAttrs (
      _: s: lib.elem "kea-dhcp4-server.service" s.config.systemd.services.kea-dhcp6-server.after
    ) { inherit spoke home; };
    expected = {
      spoke = true;
      home = true;
    };
  };
  testEvpnRecovery = {
    expr =
      let
        units = s: [
          (s.config.systemd.timers ? evpn-recovery)
          (s.config.systemd.services ? evpn-recovery)
        ];
      in
      [
        (units spoke)
        (units (spoke.extendModules { modules = [ { router.evpn.recovery.enable = false; } ]; }))
      ];
    expected = [
      [
        true
        true
      ]
      [
        false
        false
      ]
    ];
  };
  # The egress sends sources of the public prefixes to the mesh table after the main table's
  # specific routes; they must lie inside the site's own prefixes.
  testEvpnEgress =
    let
      egress = home.extendModules { modules = [ { router.evpn.egress.enable = true; } ]; };
      rules = s: s.config.systemd.network.networks."40-mesh".routingPolicyRules;
    in
    {
      expr = [
        (rules home)
        (map (r: [
          r.From
          r.Table
        ]) (rules egress))
        (fails egress { router.evpn.egress.sources = lib.mkForce [ "2001:db8:7201::/56" ]; })
        (fails spoke { router.evpn.egress.enable = true; })
        (fails egress { router.bgp.accept6 = lib.mkForce [ "::/0" ]; })
      ];
      expected = [
        [ ]
        [
          [
            "2001:db8:7200::/56"
            "main"
          ]
          [
            "2001:db8:7200::/56"
            1001
          ]
        ]
        true
        true
        true
      ];
    };
  testInvalidMac = {
    expr = fails spoke { router.wan.mac = lib.mkForce "02:00:00:71:00"; };
    expected = true;
  };
}
