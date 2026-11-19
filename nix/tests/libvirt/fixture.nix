# The spec of the golden domain XML (tests/golden/libvirt-fixture.xml): every option set.
{
  name = "fixture-vm";
  vcpu = 8;
  memory = 16;
  mac = "bc:24:11:00:00:01";
  disks = [
    { size = 64; }
    { size = 128; }
    { size = 128; }
  ];
  iso = {
    url = "https://example.org/installer-1.0.iso";
    name = "installer-1.0.iso";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
}
