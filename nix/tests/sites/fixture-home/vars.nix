# Fixture (documentation addresses only, never deployed): a home site with a VLAN-tagged
# DHCP/DHCPv6 WAN, a routable LAN (no NAT66), a public /56, reservations, a transit BGP
# neighbor on the LAN, a UPS, monitoring, central logging and upload shaping.
{
  router = {
    meta.deployable = false;

    site = {
      name = "fixture-home";
      hostname = "fixture-home";
      domain = "home.example.org";
    };

    mgmt = {
      address = "10.72.0.1";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture"
      ];
    };

    hardware.profile = "qemu";
    hardware.ups = {
      enable = true;
      name = "rack";
    };
    observability = {
      monitoring.prometheus = {
        enable = true;
        exporters = [
          "node"
          "kea"
          "frr"
          "smartctl"
          "crowdsec"
          "nut"
        ];
      };
      logging.vector = {
        enable = true;
        address = "10.72.200.1:6000";
      };
    };

    wan = {
      mac = "02:00:00:72:00:01";
      vlan = 31;
      v4.method = "dhcp";
      v6.method = "dhcp6";
      shaping.upload = "45M";
    };

    lan = {
      mac = "02:00:00:72:00:02";
      v4 = "10.72.0.1/16";
      v4Net = "10.72.0.0/16";
      v6 = "2001:db8:72:1::1/64";
      v6Net = "2001:db8:72:1::/64";
      v6Supernet = "2001:db8:72:1::/64";
    };

    nat66.enable = false;

    publicV6 = [
      {
        prefix = "2001:db8:7200::/56";
        anchor = "2001:db8:7200::1";
      }
    ];

    dhcp = {
      pool4 = "10.72.150.1 - 10.72.199.255";
      pool6 = "2001:db8:72:1:e000::1 - 2001:db8:72:1:e000::ffff";
      reservations4 = [
        {
          ip = "10.72.21.11";
          mac = "02:00:00:72:21:11";
          hostname = "ap-1";
        }
      ];
      reservations6 = [
        {
          ip = "2001:db8:72:1:2000::1";
          duid = "00:02:00:00:ab:11:00:00:00:00:00:00:00:01";
          hostname = "workstation";
        }
      ];
    };

    firewall.forwards.v4 = [
      {
        proto = "tcp";
        ports = [
          80
          443
        ];
        to = "10.72.72.2";
      }
    ];

    dns = {
      conditionalForwards = [ "[/spoke.example.org/]10.71.0.1" ];
      extraRules = [ "||ads.example.net^" ];
    };

    transport.netbird = {
      enable = true;
      managementUrl = "https://netbird.example.org:443";
    };
    evpn = {
      enable = true;
      hubVtep = "10.253.0.1";
    };

    bgp = {
      asn = 64500;
      routerId = "10.72.0.1";
      originate4 = [ "10.72.0.0/16" ];
      originate6 = [ ];
      peers = [
        {
          name = "cluster";
          address = "2001:db8:72:1:1000::1";
          remoteAs = 64551;
          iface = "lan0";
          disableConnectedCheck = true;
          nextHopSelf = true;
          outPolicy = "deny-all";
          transit = true;
        }
      ];
    };
  };
}
