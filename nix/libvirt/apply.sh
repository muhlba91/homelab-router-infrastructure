#!/bin/sh
# Applies a VM to a host (./router libvirt-deploy, through ./nx): apply.sh <libvirt uri> <json>
# json: the flake's libvirtDomain (name, xml, volumes, iso). Idempotent; deletes no volume.
set -eu
uri=$1 info=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
v() { virsh -c "$uri" "$@" </dev/null; }
j() { printf '%s' "$info" | jq -r "$@"; }
name=$(j .name)

# a missing disk is created sparse: the pool is capped by the quota of rpool/guests
j '.volumes[] | "\(.name) \(.size)"' | while read -r vol size; do
  if v vol-info --pool guests "$vol" >/dev/null 2>&1; then
    echo "libvirt: volume $vol exists"
  else
    echo "libvirt: creating volume $vol (${size}G)"
    v vol-create-as guests "$vol" "${size}G" --allocation 0
  fi
done

iso=$(j '.iso.name // empty')
if [ -n "$iso" ]; then
  if v vol-info --pool iso "$iso" >/dev/null 2>&1; then
    echo "libvirt: image $iso exists"
  else
    echo "libvirt: downloading $iso"
    curl -fsSL --retry 3 -o "$tmp/iso" "$(j .iso.url)"
    sum=$(j '.iso.sha256 // empty')
    [ -z "$sum" ] || echo "$sum  $tmp/iso" | sha256sum -c -
    size=$(wc -c <"$tmp/iso" | tr -d ' ')
    v vol-create-as iso "$iso" "$size" --format raw
    # a half-written image must not count as present at the next run
    v vol-upload --pool iso "$iso" "$tmp/iso" || { v vol-delete --pool iso "$iso"; exit 1; }
  fi
fi

# libvirt redefines a domain by its UUID: an existing one keeps it
uuid=""
if v dominfo "$name" >/dev/null 2>&1; then uuid=$(v domuuid "$name"); fi
j .xml | awk -v u="$uuid" '{ print } u != "" && /^  <name>/ { print "  <uuid>" u "</uuid>" }' >"$tmp/domain.xml"
v define "$tmp/domain.xml"
v autostart "$name"
if [ "$(v domstate "$name")" = "running" ]; then
  echo "libvirt: $name runs: the definition applies at its next start"
else
  v start "$name"
fi
