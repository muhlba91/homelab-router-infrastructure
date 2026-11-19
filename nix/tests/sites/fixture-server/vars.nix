# Fixture (documentation addresses only, never deployed): a server-zfs router and hypervisor with
# on-link WAN gateways, a ULA LAN on a bridge with hairpin NAT, SSH from the WAN, a serial
# console, no watchdog, automatic reboot.
{
  router = {
    meta.deployable = false;

    site = {
      name = "fixture-server";
      domain = "server.example.org";
    };

    mgmt = {
      address = "10.73.0.1";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture"
      ];
    };

    hardware = {
      profile = "server-zfs";
      disks = [
        "/dev/disk/by-id/nvme-EXAMPLE_0001"
        "/dev/disk/by-id/nvme-EXAMPLE_0002"
      ];
      kernelParams = [ "console=ttyS1,115200n8" ];
    };
    system = {
      watchdog = "0s";
      autoReboot.enable = true;
    };
    hypervisor.enable = true;

    wan = {
      mac = "02:00:00:73:00:01";
      v4 = {
        method = "static";
        address = "198.51.100.10/32";
        gateway = "198.51.100.1";
        onLink = true;
      };
      v6 = {
        method = "static";
        address = "2001:db8:73:1::1/128";
        gateway = "2001:db8:73:ff::1";
        onLink = true;
      };
    };

    lan = {
      mac = "02:00:00:73:00:02";
      bridge = true;
      v4 = "10.73.0.1/16";
      v4Net = "10.73.0.0/16";
      v6 = "fd73:7300:73::1/48";
      v6Net = "fd73:7300:73::/48";
      v6Supernet = "fd73:7300:73::/48";
    };

    dhcp = {
      pool4 = "10.73.150.1 - 10.73.199.255";
      pool6 = "fd73:7300:73:1::1 - fd73:7300:73:1::ffff";
    };

    firewall = {
      hairpin = true;
      services.ssh.from = [
        "lan"
        "trusted"
        "wan"
      ];
      forwards = {
        v4 = [
          {
            proto = "tcp";
            ports = [
              80
              443
            ];
            to = "10.73.72.2";
          }
        ];
        v6 = [
          {
            proto = "tcp";
            ports = [
              80
              443
            ];
            to = "fd73:7300:73::3:3:2";
          }
        ];
      };
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
      routerId = "10.73.0.1";
      originate4 = [ "10.73.0.0/16" ];
      originate6 = [ "fd73:7300:73::/48" ];
      peers = [
        {
          name = "cluster";
          address = "fd73:7300:73::1:1:1";
          remoteAs = 64552;
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
