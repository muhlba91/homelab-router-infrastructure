# Golden dumps of the fixtures that the existing sites resemble: tests/dump.nix without `drv`,
# store-path hashes and versions stripped, as compact JSON; `golden-*` checks diff them against
# tests/golden/<fixture>.json (./router golden rewrites them).
{ lib, fixtures }:
let
  dump = import ./dump.nix;
  # "/nix/store/<hash>-name-1.2" -> "/nix/store/name": neither a rebuilt nor an updated package changes the dump.
  unversioned =
    name:
    let
      m = builtins.match "(.*[^-0-9.])-[0-9][0-9.]*" name;
    in
    if m == null then name else builtins.head m;
  stripStorePaths =
    text:
    lib.concatMapStrings (
      part: if lib.isList part then "/nix/store/${unversioned (lib.head part)}" else part
    ) (builtins.split "/nix/store/[0-9a-z]{32}-([^/\" ]*)" text);
in
lib.genAttrs
  [
    "fixture-home"
    "fixture-spoke"
  ]
  (
    name:
    stripStorePaths (
      builtins.unsafeDiscardStringContext (
        builtins.toJSON (removeAttrs (dump fixtures.${name}.config) [ "drv" ])
      )
    )
  )
