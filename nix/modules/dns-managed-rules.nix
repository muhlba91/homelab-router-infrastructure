# The ExecStartPre script of AdGuard Home (imported by dns.nix, not a module): writes the
# managed block into user_rules and the `admin` user into the config.
{
  pkgs,
  rules, # the managed block's rules, in order
  passwordHashFile, # file with the bcrypt hash of the `admin` password
}:
let
  # Managed block in user_rules, delimited by comment rules (`!`): replaced before every
  # start, everything outside it is kept (external-dns owns only its own rules). A changed
  # rule list changes the unit, so a deploy restarts AdGuard and applies it.
  block = pkgs.writeText "adguard-managed-rules.json" (
    builtins.toJSON (
      [ "! BEGIN managed by nix (modules/dns.nix), edits inside are overwritten" ]
      ++ rules
      ++ [ "! END managed by nix" ]
    )
  );
  # Old block out, new block in at the end; copies of managed rules outside the block are
  # dropped (e.g. the unmarked ones of a migrated config). An unclosed BEGIN keeps its rules.
  filter = pkgs.writeText "adguard-managed-rules.jq" ''
    $blk[0] as $new | $new[0] as $b | $new[-1] as $e
    | reduce .[] as $l ({o: [], k: [], in: false};
        if $l == $b then .in = true | .k = []
        elif $l == $e then .in = false | .k = []
        elif .in then .k += [$l]
        else .o += [$l] end)
    | (.o + .k | map(select(. as $x | any($new[]; . == $x) | not))) + $new
  '';
in
pkgs.writeShellApplication {
  name = "adguardhome-managed-rules";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.yq-go
    pkgs.jq
  ];
  text = ''
    conf="$STATE_DIRECTORY/AdGuardHome.yaml"
    export RULES="$RUNTIME_DIRECTORY/managed-rules.json" NEW="$conf.new" HASH
    # A failure below must not keep AdGuard from starting: every step is a condition.
    HASH=$(cat ${passwordHashFile}) || HASH=""
    if (yq -o json '.user_rules // []' "$conf" | jq --slurpfile blk ${block} -f ${filter} > "$RULES") \
      && [ -s "$RULES" ] && [ -n "$HASH" ] && cp "$conf" "$NEW" \
      && yq -i '.user_rules = load(strenv(RULES)) | .user_rules style="" | .users = [{"name": "admin", "password": strenv(HASH)}]' "$NEW" \
      && chown --reference="$conf" "$NEW" && chmod --reference="$conf" "$NEW" \
      && mv "$NEW" "$conf"; then
      echo "managed rules and user applied"
    else
      echo "managed rules and user NOT applied, config left unchanged" >&2
    fi
    rm -f "$RULES" "$NEW"
  '';
}
