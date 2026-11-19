# The libvirt domain of a VM on a server (docs/libvirt.md): spec in, XML and the
# volumes to create out. The conventions of every VM are here, nowhere else.
{ lib, spec }:
let
  inherit (lib) mkOption types;
  # The spec is checked like module options (a wrong value fails with the option path); all of
  # it is forced, so that a value that the XML does not use is checked as well.
  checked =
    (lib.evalModules {
      modules = [
        {
          options = {
            name = mkOption {
              type = types.strMatching "[a-z][a-z0-9-]*";
              description = "domain name; prefix of the volume names";
            };
            vcpu = mkOption {
              type = types.ints.positive;
              description = "virtual CPUs";
            };
            memory = mkOption {
              type = types.ints.positive;
              description = "fixed memory in GiB";
            };
            mac = mkOption {
              type = types.strMatching "[0-9a-f][02468ace](:[0-9a-f]{2}){5}";
              description = "unicast MAC of the NIC on the bridge lan0 (lowercase); unique on the bridge";
            };
            disks = mkOption {
              type = types.listOf (
                types.submodule {
                  options.size = mkOption {
                    type = types.ints.positive;
                    description = "size in GiB";
                  };
                }
              );
              description = "1 to 20 disks; the first one boots; the guest sees them as sda, sdb, ...";
            };
            iso = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    url = mkOption {
                      type = types.strMatching "https://[^ '\"<>&]+";
                      description = "download URL of the installer image";
                    };
                    name = mkOption {
                      type = types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
                      description = "volume name in the pool iso (include the version: images change)";
                    };
                    sha256 = mkOption {
                      type = types.nullOr (types.strMatching "[0-9a-f]{64}");
                      default = null;
                      description = "checksum of the image; null = not checked";
                    };
                  };
                }
              );
              default = null;
              description = "installer image, attached as a CD-ROM behind the disks; null = none";
            };
          };
        }
        { config = spec; }
      ];
    }).config;
  cfg = builtins.deepSeq checked (
    assert lib.assertMsg (
      checked.disks != [ ] && lib.length checked.disks <= 20
    ) "disks: 1 to 20 entries (the guest names them sda to sdt)";
    checked
  );

  letters = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz";
  letter = lib.elemAt letters;
  volume = i: "${cfg.name}-disk${toString i}";
  indent = n: map (l: lib.concatStrings (lib.genList (_: " ") n) + l);

  disk =
    i: _:
    [
      "<disk type='volume' device='disk'>"
      "  <driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>"
      "  <source pool='guests' volume='${volume i}'/>"
      "  <target dev='sd${letter i}' bus='scsi'/>"
      "  <serial>drive-scsi${toString i}</serial>"
    ]
    ++ lib.optional (i == 0) "  <boot order='1'/>"
    ++ [ "</disk>" ];

  # SATA, boot order after the first disk: the image never takes sda.
  # The unit is set explicitly: libvirt derives it from the name sdz, which is out of range for SATA.
  cdrom = iso: [
    "<disk type='volume' device='cdrom'>"
    "  <driver name='qemu' type='raw'/>"
    "  <source pool='iso' volume='${iso.name}'/>"
    "  <target dev='sdz' bus='sata'/>"
    "  <address type='drive' controller='0' bus='0' target='0' unit='0'/>"
    "  <readonly/>"
    "  <boot order='2'/>"
    "</disk>"
  ];

  devices = [
    "<controller type='scsi' model='virtio-scsi'/>"
  ]
  ++ lib.concatLists (lib.imap0 disk cfg.disks)
  ++ lib.optionals (cfg.iso != null) (cdrom cfg.iso)
  ++ [
    "<interface type='bridge'>"
    "  <mac address='${cfg.mac}'/>"
    "  <source bridge='lan0'/>"
    "  <model type='virtio'/>"
    "</interface>"
    "<channel type='unix'>"
    "  <target type='virtio' name='org.qemu.guest_agent.0'/>"
    "</channel>"
    "<graphics type='vnc' autoport='yes' listen='127.0.0.1'>"
    "  <listen type='address' address='127.0.0.1'/>"
    "</graphics>"
    "<video>"
    "  <model type='vga'/>"
    "</video>"
    "<memballoon model='none'/>"
  ];
in
{
  inherit (cfg) name iso;
  volumes = lib.imap0 (i: d: {
    name = volume i;
    inherit (d) size;
  }) cfg.disks;

  xml = lib.concatMapStrings (l: l + "\n") (
    [
      "<domain type='kvm'>"
      "  <name>${cfg.name}</name>"
      "  <memory unit='GiB'>${toString cfg.memory}</memory>"
      "  <vcpu placement='static'>${toString cfg.vcpu}</vcpu>"
      "  <os firmware='efi'>"
      "    <type arch='x86_64' machine='q35'>hvm</type>"
      "    <firmware>"
      "      <feature enabled='no' name='enrolled-keys'/>"
      "      <feature enabled='no' name='secure-boot'/>"
      "    </firmware>"
      "  </os>"
      "  <features>"
      "    <acpi/>"
      "    <apic/>"
      "  </features>"
      "  <cpu mode='host-passthrough'/>"
      "  <on_poweroff>destroy</on_poweroff>"
      "  <on_reboot>restart</on_reboot>"
      "  <on_crash>restart</on_crash>"
      "  <devices>"
    ]
    ++ indent 4 devices
    ++ [
      "  </devices>"
      "</domain>"
    ]
  );
}
