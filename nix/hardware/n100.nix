# Hardware profile: Intel N100/N150 mini PC (Alder Lake-N, UEFI only, NVMe, Intel NICs).
# systemd-boot on the ESP, installed without EFI variables: the firmware boots the removable
# fallback path, so a cleared NVRAM or a swapped disk still boots.
# Selected by router.hardware.profile (= this file name); hand-written, never generated.
{ config, ... }:
{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  # The Intel PCH TCO watchdog (router.system.watchdog).
  boot.kernelModules = [ "iTCO_wdt" ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      # No kernel command line edits at the boot menu (init=/bin/sh would be a root shell).
      editor = false;
      configurationLimit = config.router.system.gc.keep;
    };
    efi.canTouchEfiVariables = false;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  disko.devices.disk.main = {
    type = "disk";
    device = config.router.hardware.disk;
    content = {
      type = "gpt";
      partitions = {
        # Kernels and initrds live here (one pair per kept generation).
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
