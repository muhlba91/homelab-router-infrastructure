# Interfaces (systemd-networkd): WAN (static or DHCP, optional VLAN) with reply-to and optional
# upload shaping (CAKE), LAN, optional site-owned public prefix, the router's own resolver,
# kernel forwarding and hardening sysctls.
{
  config,
  lib,
  rlib,
  ...
}:
let
  cfg = config.router;
  d = cfg.derived;
  inherit (rlib) isV6;
  inherit (cfg) wan;
  v4Static = wan.v4.method == "static";
  v6Static = wan.v6.method == "static";
  v6Dhcp = wan.v6.method == "dhcp6";
  # A route through a WAN gateway, on-link where the gateway lies outside the address' subnet.
  viaGateway = gw: onLink: { Gateway = gw; } // lib.optionalAttrs onLink { GatewayOnLink = true; };
  # WAN gateway routes for the reply-to table (networkd fills _dhcp4/_ipv6ra from DHCP/RA).
  wanGateways =
    lib.optional (v4Static && wan.v4.gateway != null) (viaGateway wan.v4.gateway wan.v4.onLink)
    ++ lib.optional (wan.v4.method == "dhcp") { Gateway = "_dhcp4"; }
    ++ lib.optional (v6Static && wan.v6.gateway != null) (viaGateway wan.v6.gateway wan.v6.onLink)
    ++ lib.optional v6Dhcp { Gateway = "_ipv6ra"; };
  lanDummy = "${d.lanIf}-dummy";

  wanNetwork = {
    matchConfig.Name = d.wanIf;
    address = lib.optional v4Static wan.v4.address ++ lib.optional v6Static wan.v6.address;
    routes =
      lib.optional (v4Static && wan.v4.gateway != null) (viaGateway wan.v4.gateway wan.v4.onLink)
      ++ lib.optional (v6Static && wan.v6.gateway != null) (viaGateway wan.v6.gateway wan.v6.onLink)
      # Reply-to: connections that arrived on the WAN are answered through it, even if the
      # mesh knows a shorter path to the source (else the upstream drops the asymmetric
      # replies). Marks: modules/firewall.nix.
      ++ map (gw: gw // { Table = d.wanReply.table; }) wanGateways;
    routingPolicyRules = lib.optional (wanGateways != [ ]) {
      FirewallMark = "${toString d.wanReply.mark}/${toString d.wanReply.mark}";
      Table = d.wanReply.table;
      Priority = 900; # before the VRF rule (1000) and main
      Family = "both";
    };
    networkConfig = {
      # Static: RA would only interfere. dhcp6: the default route comes from RA.
      IPv6AcceptRA = v6Dhcp;
    }
    // lib.optionalAttrs (wan.v4.method == "dhcp" || v6Dhcp) {
      DHCP =
        if wan.v4.method == "dhcp" && v6Dhcp then
          "yes"
        else if v6Dhcp then
          "ipv6"
        else
          "ipv4";
    };
    linkConfig.RequiredForOnline = "routable";
  }
  // lib.optionalAttrs v6Dhcp {
    # Solicit without waiting for an RA: some ISPs send RAs only once a DHCPv6 binding exists.
    dhcpV6Config.WithoutRA = "solicit";
  }
  // lib.optionalAttrs (wan.shaping.upload != null) {
    # Upload shaping: CAKE as the root qdisc of the WAN device. `NAT` lets it see the LAN
    # hosts behind the masquerade, so the bandwidth is shared fairly per host.
    cakeConfig = {
      Bandwidth = wan.shaping.upload;
      NAT = true;
      FlowIsolationMode = "dual-src-host";
      PriorityQueueingPreset = "diffserv4";
    };
  };
in
{
  assertions = [
    {
      assertion = !v4Static || wan.v4.address != null;
      message = "router.wan.v4.method = static needs router.wan.v4.address";
    }
    {
      assertion = !v6Static || wan.v6.address != null;
      message = "router.wan.v6.method = static needs router.wan.v6.address";
    }
    {
      assertion = !wan.v4.onLink || (v4Static && wan.v4.gateway != null);
      message = "router.wan.v4.onLink needs a static router.wan.v4.gateway";
    }
    {
      assertion = !wan.v6.onLink || (v6Static && wan.v6.gateway != null);
      message = "router.wan.v6.onLink needs a static router.wan.v6.gateway";
    }
    {
      # The kernel limits interface names to 15 characters.
      assertion = !cfg.lan.bridge || lib.stringLength lanDummy <= 15;
      message = "router.lan.iface is too long for the bridge's dummy port (${lanDummy}: at most 15 characters)";
    }
  ];

  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.firewall.enable = false; # replaced by modules/firewall.nix
  services.resolved.enable = false; # AdGuard owns :53
  # The router resolves through its own AdGuard, Quad9 as fallback while it is down
  # (openresolv drops non-local servers unless resolv_conf_local_only=NO; glibc reads 3).
  networking.nameservers = [
    "127.0.0.1"
    (lib.head rlib.quad9.v4)
  ]
  ++ lib.optional (wan.v6.method != "none") (lib.head rlib.quad9.v6);
  networking.resolvconf.extraConfig = "resolv_conf_local_only=NO";

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # Loose reverse-path filter: routes learned by BGP make flows asymmetric.
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv4.tcp_syncookies" = 1;
  };

  # NICs are renamed by MAC so names do not depend on PCI slot order.
  systemd.network.links."10-wan" = {
    matchConfig.MACAddress = wan.mac;
    linkConfig.Name = d.wanParent;
  };
  systemd.network.links."10-lan" = lib.mkIf (!cfg.lan.bridge) {
    matchConfig.MACAddress = cfg.lan.mac;
    linkConfig.Name = d.lanIf;
  };

  # Without a VLAN the WAN NIC itself carries the configuration; with one, the
  # NIC only hosts the VLAN device and the configuration moves to that device.
  systemd.network.networks."10-wan" =
    if wan.vlan == null then
      wanNetwork
    else
      {
        matchConfig.Name = d.wanParent;
        networkConfig = {
          VLAN = [ d.wanIf ];
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "carrier";
      };
  systemd.network.netdevs."20-wan-vlan" = lib.mkIf (wan.vlan != null) {
    netdevConfig = {
      Kind = "vlan";
      Name = d.wanIf;
    };
    vlanConfig.Id = wan.vlan;
  };
  systemd.network.networks."11-wan" = lib.mkIf (wan.vlan != null) wanNetwork;

  # lan.bridge: the LAN device is a bridge with the LAN MAC. Its permanent dummy port gives it
  # carrier, so the LAN addresses leave the tentative state and Kea, radvd and AdGuard can bind
  # without a guest running; guests join the bridge as ports.
  systemd.network.netdevs."20-lan" = lib.mkIf cfg.lan.bridge {
    netdevConfig = {
      Kind = "bridge";
      Name = d.lanIf;
      MACAddress = cfg.lan.mac;
    };
  };
  systemd.network.netdevs."19-lan-dummy" = lib.mkIf cfg.lan.bridge {
    netdevConfig = {
      Kind = "dummy";
      Name = lanDummy;
    };
  };
  systemd.network.networks."19-lan-dummy" = lib.mkIf cfg.lan.bridge {
    matchConfig.Name = lanDummy;
    networkConfig.Bridge = d.lanIf;
    linkConfig.RequiredForOnline = "no";
  };

  systemd.network.networks."20-lan" = {
    matchConfig.Name = d.lanIf;
    address = [
      cfg.lan.v4
      cfg.lan.v6
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Loopback: site-owned public prefixes (an anchor address plus a blackhole route, so BGP
  # can originate the prefix; more-specifics from downstream win) and extra host addresses.
  systemd.network.networks."05-lo" = lib.mkIf (cfg.publicV6 != [ ] || cfg.loopbacks != [ ]) {
    matchConfig.Name = "lo";
    address =
      map (p: "${p.anchor}/128") cfg.publicV6
      ++ map (l: if isV6 l.address then "${l.address}/128" else "${l.address}/32") cfg.loopbacks;
    routes = map (p: {
      Destination = p.prefix;
      Type = "blackhole";
    }) cfg.publicV6;
  };
}
