# Time: chrony, also the NTP server of the LAN.
_: {
  services.chrony = {
    enable = true;
    servers = [
      "0.pool.ntp.org"
      "1.pool.ntp.org"
      "2.pool.ntp.org"
      "3.pool.ntp.org"
    ];
    # Serve every client: the firewall decides who reaches it (router.firewall.services.ntp).
    extraConfig = "allow all";
  };
}
