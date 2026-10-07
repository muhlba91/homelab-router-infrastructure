# Small pure helpers shared by the modules (`rlib` module argument).
{ lib, ... }:
{
  _module.args.rlib = rec {
    addr = cidr: builtins.head (lib.splitString "/" cidr);
    quote = map (s: ''"${s}"'');
    nftSet = l: "{ ${lib.concatStringsSep ", " l} }";
    isV6 = a: lib.hasInfix ":" a;
    # Powers of two (nixpkgs lib has no pow).
    pow2 = n: lib.foldl (a: _: a * 2) 1 (lib.genList (x: x) n);
    # Network of an IPv4 CIDR ("10.50.0.1/31" -> "10.50.0.0/31").
    network4 =
      cidr:
      let
        parts = lib.splitString "/" cidr;
        len = lib.toInt (builtins.elemAt parts 1);
        ip = lib.foldl (acc: o: acc * 256 + lib.toInt o) 0 (lib.splitString "." (builtins.head parts));
        net = ip - lib.mod ip (pow2 (32 - len));
        octet = i: toString (lib.mod (net / pow2 (8 * (3 - i))) 256);
      in
      "${lib.concatMapStringsSep "." octet (lib.range 0 3)}/${toString len}";
    # Network of an IPv6 CIDR, uncompressed ("fd80:8a2:fd5a::1/127" -> "fd80:8a2:fd5a:0:0:0:0:0/127").
    network6 =
      cidr:
      let
        p = lib.network.ipv6.fromString cidr;
        group =
          i: g:
          let
            host = 16 - lib.min 16 (lib.max 0 (p.prefixLength - 16 * i));
            v = lib.fromHexString g;
          in
          lib.toLower (lib.toHexString (v - lib.mod v (pow2 host)));
      in
      "${lib.concatStringsSep ":" (lib.imap0 group (lib.splitString ":" p.address))}/${toString p.prefixLength}";
  };
}
