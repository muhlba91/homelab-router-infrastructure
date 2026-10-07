# Shared helpers and validated types of the vars schema (a function, not a module: the
# files next to it import it).
{ lib }:
let
  inherit (lib) mkOption types;

  str =
    description:
    mkOption {
      type = types.str;
      inherit description;
    };
  strD =
    default: description:
    mkOption {
      type = types.str;
      inherit default description;
    };
  bool =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };
  nullable =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
  strList =
    default: description:
    mkOption {
      type = types.listOf types.str;
      inherit default description;
    };
  # Typed options: `typed T "…"` is required, `typedD T default "…"` has a default.
  typed =
    type: description:
    mkOption {
      inherit type description;
    };
  typedD =
    type: default: description:
    mkOption {
      inherit type default description;
    };

  # Syntax checks (catch typos in generated data early): IPv4 octets 0-255, prefix lengths
  # 0-32 / 0-128, IPv6 addresses by nixpkgs' parser (no embedded IPv4, no zone index);
  # semantics stay with the tools.
  octet = "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])";
  ip4Re = "(${octet}\\.){3}${octet}";
  ip6Re = "[0-9a-fA-F:]*:[0-9a-fA-F:]*";
  # The parser throws on an invalid address; it also accepts a prefix length (cidr6).
  parses6 = s: (builtins.tryEval (builtins.deepSeq (lib.network.ipv6.fromString s) true)).success;
  checked6 =
    re: description: types.addCheck (types.strMatching re) parses6 // { inherit description; };
  ip4 = types.strMatching ip4Re;
  ip6 = checked6 ip6Re "IPv6 address";
  cidr4 = types.strMatching "${ip4Re}/(3[0-2]|[12]?[0-9])";
  cidr6 = checked6 "${ip6Re}/(12[0-8]|1[01][0-9]|[1-9]?[0-9])" "IPv6 address with prefix length";
  mac = types.strMatching "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}";
  mtu = types.ints.between 1280 9000;
in
{
  inherit
    str
    strD
    bool
    nullable
    strList
    typed
    typedD
    ip4
    ip6
    cidr4
    cidr6
    mac
    mtu
    ;
}
