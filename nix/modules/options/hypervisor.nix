# Vars schema: the hypervisor (libvirt/QEMU) on the router.
{ lib, ... }:
let
  inherit (import ./types.nix { inherit lib; }) bool nullable;
in
{
  options.router.hypervisor = {
    enable = bool false ''
      libvirt/QEMU on the router. The guests belong to their own repositories (`virsh` over
      `qemu+ssh` as the user `virt`, same keys as `deploy`); the router provides libvirtd, that
      user and, with `zfsDataset`, the storage pools. libvirt manages no networks: guests attach
      to the LAN bridge (`lan.bridge`).
    '';
    zfsDataset = nullable lib.types.str ''
      ZFS dataset for the guests' disks (zvols): libvirt storage pool `guests`, next to the
      directory pool `iso`. Set by the hardware profile (server-zfs); null: no storage pools.
    '';
  };
}
