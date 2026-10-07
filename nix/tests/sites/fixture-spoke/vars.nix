# Fixture (documentation addresses only, never deployed): an EVPN spoke with a static WAN,
# a ULA LAN behind NAT66, IPv4 and IPv6 forwards, loopbacks and an announced WAN network.
# The flake's default `sites` input: what `nix flake check` checks without real site data.
{
  router = {
    meta.deployable = true;
    meta.deployOrder = 10;

    site = {
      name = "fixture-spoke";
      hostname = "fixture-spoke";
      domain = "spoke.example.org";
    };

    mgmt = {
      address = "10.71.0.1";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture"
      ];
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture";
    };
    trusted.onWan = true;

    hardware.profile = "qemu";

    wan = {
      mac = "02:00:00:71:00:01";
      v4 = {
        method = "static";
        address = "192.0.2.10/24";
        gateway = "192.0.2.1";
        announce = true;
      };
      v6 = {
        method = "static";
        address = "2001:db8:0:1::10/64";
        gateway = "2001:db8:0:1::1";
      };
    };

    lan = {
      mac = "02:00:00:71:00:02";
      v4 = "10.71.0.1/16";
      v4Net = "10.71.0.0/16";
      v6 = "fd71:0:0:1::1/64";
      v6Net = "fd71:0:0:1::/64";
      v6Supernet = "fd71::/48";
    };

    loopbacks = [
      { address = "10.71.255.1"; }
      {
        address = "fd71:0:0:ff::1";
        announce = false;
      }
    ];

    dhcp = {
      pool4 = "10.71.150.1 - 10.71.199.255";
      pool6 = "fd71:0:0:1:e000::1 - fd71:0:0:1:e000::ffff";
    };

    firewall.forwards = {
      v4 = [
        {
          proto = "tcp";
          ports = [ 443 ];
          to = "10.71.0.10";
          from = [ "198.51.100.0/24" ];
        }
      ];
      v6 = [
        {
          proto = "udp";
          ports = [ 51821 ];
          to = "fd71:0:0:1::10";
        }
      ];
    };

    dns.conditionalForwards = [ "[/home.example.org/]10.72.0.1" ];

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
      routerId = "10.71.0.1";
      originate4 = [ "10.71.0.0/16" ];
      originate6 = [ "fd71:0:0:1::/64" ];
    };
  };
}
