# Hardware profile: a dedicated server with two NVMe disks in a ZFS mirror (docs/server.md).
# Each disk holds a BIOS boot partition, an ESP and a ZFS partition; GRUB is on both (BIOS and
# removable UEFI path), so either disk boots under either firmware.
{ config, lib, ... }:
let
  cfg = config.router;
  arcMax = 4 * 1024 * 1024 * 1024;
  # The ESPs: the first is /boot, the second /boot-fallback. `disks` is cut to their number so
  # that the assertion below can report a wrong count.
  esps = [
    "/boot"
    "/boot-fallback"
  ];
  disks = lib.take (lib.length esps) cfg.hardware.disks;
in
{
  assertions = [
    {
      assertion = lib.length cfg.hardware.disks == 2;
      message = "router.hardware.disks needs exactly two disks for the server-zfs profile";
    }
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = cfg.system.gc.keep;
    # The targets are the mirroredBoots'; disko's EF02 entries would list the disks again.
    devices = lib.mkForce [ ];
    mirroredBoots = lib.zipListsWith (path: device: {
      inherit path;
      devices = [ device ];
    }) esps disks;
  };

  # ZFS: the host id comes from the host name (renaming the host changes it: the root pool then
  # needs one `zpool import -f`); the ARC is capped, because the guests need the memory.
  networking.hostId = builtins.substring 0 8 (builtins.hashString "sha256" cfg.site.hostname);
  boot.kernelParams = [ "zfs.zfs_arc_max=${toString arcMax}" ];
  boot.zfs.forceImportRoot = false;
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
    };
    trim.enable = true;
  };

  # Reboot 10 s after a kernel panic. The box has no watchdog device: a site on this profile sets
  # router.system.watchdog = 0s.
  boot.kernel.sysctl."kernel.panic" = 10;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  router.hypervisor.zfsDataset = "rpool/guests";

  disko.devices = {
    disk = lib.listToAttrs (
      lib.imap0 (
        i: device:
        lib.nameValuePair "nvme${toString i}" {
          type = "disk";
          inherit device;
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02";
              };
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = lib.elemAt esps i;
                  # With a disk missing, the box must still boot from the other one: its ESP
                  # is not required, and the wait for the missing one is short.
                  mountOptions = [
                    "umask=0077"
                    "nofail"
                    "x-systemd.device-timeout=10s"
                  ];
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        }
      ) disks
    );

    zpool.rpool = {
      type = "zpool";
      mode = "mirror";
      options.ashift = "12";
      rootFsOptions = {
        compression = "lz4";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
        mountpoint = "none";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        var = {
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy";
        };
        # The pool behind router.hypervisor.zfsDataset: the quota keeps the guests' zvols off the
        # host's space, and the ARC caches metadata only (the guests cache their own data).
        guests = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            primarycache = "metadata";
            quota = "360G";
          };
        };
      };
    };
  };
}
