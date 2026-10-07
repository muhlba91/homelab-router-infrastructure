# Hardware profile: x86_64 QEMU/KVM guest (Proxmox, a cloud VM), one virtio disk. Boots with
# either firmware: GRUB is installed for legacy BIOS (BIOS boot partition) and for UEFI (the
# removable fallback path on the ESP, so no EFI variables are needed), so a VM can switch
# between SeaBIOS and OVMF without a reinstall.
# Selected by router.hardware.profile (= this file name); hand-written, never generated.
{ config, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # disko adds the disk to boot.loader.grub.devices (it has an EF02 partition).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = config.router.system.gc.keep;
  };
  services.qemuGuest.enable = true;

  disko.devices.disk.main = {
    type = "disk";
    device = config.router.hardware.disk;
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "512M";
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
