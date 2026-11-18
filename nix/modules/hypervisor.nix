# Hypervisor (router.hypervisor): libvirtd with QEMU/KVM; see the option for guest access,
# networks and pools.
{ config, lib, ... }:
let
  cfg = config.router;
  hv = cfg.hypervisor;
  inherit (config.virtualisation.libvirtd) package;
  isoDir = "/var/lib/libvirt/iso";
in
lib.mkIf hv.enable {
  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";
    shutdownTimeout = 300;
  };

  boot.kernelModules = [ "kvm-intel" ]; # all routers are Intel

  users.users.virt = {
    isNormalUser = true;
    extraGroups = [ "libvirtd" ];
    openssh.authorizedKeys.keys = cfg.mgmt.sshKeys;
  };
  # virsh and virt-ssh-helper, which `qemu+ssh` runs on the router.
  environment.systemPackages = [ package ];

  # The guests' network comes from the router's services: start after them, so a guest's DHCP
  # request is answered and the mesh is up when it boots.
  systemd.services.libvirtd.after = [
    "frr.service"
    "${cfg.derived.netbirdUnit}.service"
    "kea-dhcp4-server.service"
    "kea-dhcp6-server.service"
  ];

  # The host keeps its share under load: guests live in machine.slice (the default weight is 100).
  systemd.slices.machine.sliceConfig.CPUWeight = 50;

  # NixOS copies libvirt's default network (not autostarted) on every start: remove it, so that
  # libvirt manages no network. Then the storage pools, created once (a changed dataset needs a
  # manual pool-undefine).
  systemd.services.libvirt-setup = {
    description = "libvirt: no networks, storage pools";
    wantedBy = [ "multi-user.target" ];
    requires = [ "libvirtd.service" ];
    after = [ "libvirtd.service" ];
    path = [ package ];
    environment.LIBVIRT_DEFAULT_URI = "qemu:///system";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for net in $(virsh net-list --all --name); do
        virsh net-destroy "$net" || true
        virsh net-undefine "$net"
      done
    ''
    + lib.optionalString (hv.zfsDataset != null) ''
      mkdir -p ${isoDir}
      virsh pool-info guests >/dev/null 2>&1 || virsh pool-define-as guests zfs --source-name ${hv.zfsDataset}
      virsh pool-info iso >/dev/null 2>&1 || virsh pool-define-as iso dir --target ${isoDir}
      for pool in guests iso; do
        virsh pool-autostart "$pool"
        virsh pool-info "$pool" | grep -q '^State: *running' || virsh pool-start "$pool"
      done
    '';
  };
}
