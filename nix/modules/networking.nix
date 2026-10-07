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
  # WAN gateways for the reply-to table (networkd fills _dhcp4/_ipv6ra from DHCP/RA).
  wanGateways =
    lib.optional (v4Static && wan.v4.gateway != null) wan.v4.gateway
    ++ lib.optional (wan.v4.method == "dhcp") "_dhcp4"
    ++ lib.optional (v6Static && wan.v6.gateway != null) wan.v6.gateway
    ++ lib.optional v6Dhcp "_ipv6ra";

  wanNetwork = {
    matchConfig.Name = d.wanIf;
    address = lib.optional v4Static wan.v4.address ++ lib.optional v6Static wan.v6.address;
    routes =
      lib.optional (v4Static && wan.v4.gateway != null) { Gateway = wan.v4.gateway; }
      ++ lib.optional (v6Static && wan.v6.gateway != null) { Gateway = wan.v6.gateway; }
      # Reply-to: connections that arrived on the WAN are answered through it, even if the
      # mesh knows a shorter path to the source (else the upstream drops the asymmetric
      # replies). Marks: modules/firewall.nix.
      ++ map (gw: {
        Gateway = gw;
        Table = d.wanReply.table;
      }) wanGateways;
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
  ];

  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.firewall.enable = false; # replaced by modules/firewall.nix
  services.resolved.enable = false; # AdGuard owns :53
  # The router resolves through its own AdGuard, Quad9 as fallback while it is down
  # (openresolv drops non-local servers unless resolv_conf_local_only=NO; glibc reads 3).
  networking.nameservers = [
    "127.0.0.1"
    "9.9.9.10"
  ]
  ++ lib.optional (wan.v6.method != "none") "2620:fe::10";
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
    "net.ipv4.tcp_syncookies" = 1;
  };

  # NICs are renamed by MAC so names do not depend on PCI slot order.
  systemd.network.links."10-wan" = {
    matchConfig.MACAddress = wan.mac;
    linkConfig.Name = d.wanParent;
  };
  systemd.network.links."10-lan" = {
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
