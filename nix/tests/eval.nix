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
  fixtures' = [
    spoke
    home
  ];
  multihopPeer = name: address: {
    inherit name address;
    remoteAs = 64511;
    multihop = 2;
  };
in
lib.runTests {
  # Derived values.
  testHostnames = {
    expr = lib.mapAttrs (_: s: s.config.networking.hostName) fixtures;
    expected = {
      fixture-home = "fixture-home";
      fixture-spoke = "fixture-spoke";
    };
  };
  testWanDevice = {
    expr = map (s: s.config.router.derived.wanIf) [
      spoke
      home
    ];
    expected = [
      "wan0"
      "wan0.31"
    ];
  };
  testNat66OnlyForUla = {
    expr = map (s: s.config.networking.nftables.tables ? nat6 && s.config.router.nat66.enable) [
      spoke
      home
    ];
    expected = [
      true
      false
    ];
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
  # A pinned host key: sshd offers only the secret's key; without one, its own keys.
  testHostKey = {
    expr =
      map
        (s: {
          keys = map (k: "${k.type} ${k.path}") s.config.services.openssh.hostKeys;
          secret = s.config.router.secrets ? ssh-host-key;
        })
        [
          spoke
          home
        ];
    expected = [
      {
        keys = [ "ed25519 /var/lib/secrets/ssh-host-key" ];
        secret = true;
      }
      {
        keys = [
          "rsa /etc/ssh/ssh_host_rsa_key"
          "ed25519 /etc/ssh/ssh_host_ed25519_key"
        ];
        secret = false;
      }
    ];
  };
  testUpsService = {
    expr = map (s: s.config.router.firewall.services ? nut) [
      spoke
      home
    ];
    expected = [
      false
      true
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
      map (s: lib.hasInfix s frr) [
        "set src ${spoke.config.router.derived.lanAddr4}"
        "ip protocol bgp route-map SRC4"
        "ipv6 protocol bgp"
      ];
    expected = [
      true
      true
      false
    ];
  };
  testTransitMarker = {
    expr = lib.hasInfix "64500:0:1" home.config.services.frr.config;
    expected = true;
  };

  # Firewall exposure: the defaults of every site.
  testFirewallDefaultDrop = {
    expr = map (
      s:
      let
        rules = s.config.networking.nftables.tables.router.content;
      in
      map (h: lib.hasInfix "type filter hook ${h} priority filter; policy drop;" rules) [
        "input"
        "forward"
      ]
    ) fixtures';
    expected = [
      [
        true
        true
      ]
      [
        true
        true
      ]
    ];
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
  # The underlay: WireGuard not from the mesh, VXLAN only from the overlay range on wt0.
  testFirewallUnderlay = {
    expr =
      let
        rules = spoke.config.networking.nftables.tables.router.content;
      in
      map (r: lib.hasInfix r rules) [
        ''iifname != { "br50001", "mesh" } udp dport 51820 accept''
        ''iifname "wt0" ip saddr 10.253.0.0/16 udp dport 4789 accept''
      ];
    expected = [
      true
      true
    ];
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
  testInvalidMac = {
    expr = fails spoke { router.wan.mac = lib.mkForce "02:00:00:71:00"; };
    expected = true;
  };
}
