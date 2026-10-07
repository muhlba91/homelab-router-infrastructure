# Logging (router.observability.logging.vector): Vector ships the journal to a central
# Vector (its `vector` source, e.g. the cluster's in front of VictoriaLogs). A disk buffer
# keeps the logs while the receiver is unreachable (up to its size, then the newest are
# dropped). Vector's own log stays local (it would feed back its own sink errors).
{ config, lib, ... }:
let
  lv = config.router.observability.logging.vector;
in
{
  assertions = [
    {
      assertion = !lv.enable || lv.address != null;
      message = "router.observability.logging.vector needs an address (host:port of the receiving Vector)";
    }
  ];

  services.vector = lib.mkIf lv.enable {
    enable = true;
    journaldAccess = true;
    settings = {
      data_dir = "/var/lib/vector";
      sources.journald = {
        type = "journald";
        exclude_units = [ "vector.service" ];
      };
      sinks.central = {
        type = "vector";
        inputs = [ "journald" ];
        inherit (lv) address;
        buffer = {
          type = "disk";
          max_size = 268435488; # Vector's minimum for a disk buffer (256 MiB)
          when_full = "drop_newest";
        };
      };
    };
  };
}
