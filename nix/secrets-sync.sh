#!/bin/sh
# Runs as root on the router (./router push-secrets), the secrets as a tar stream on stdin:
# moves in only changed files (an unchanged one triggers no reload); `prune`, only after a
# successful deploy, also removes files no longer delivered. Files land 0600 root; the path
# units apply owner/mode.
set -eu
umask 077
d=$1
prune=${2:-}
mkdir -p "$d" && chmod 0711 "$d"
t=$(mktemp -d "$d.push.XXXXXX")
trap 'rm -f -- "$t"/*; rmdir -- "$t"' EXIT
tar -C "$t" --no-same-owner --no-same-permissions -xf -
[ -n "$(ls -A "$t")" ] || {
  echo "no secrets received" >&2
  exit 1
}
for f in "$d"/*; do
  n=${f##*/}
  if [ "$prune" = prune ] && [ -f "$f" ] && [ ! -e "$t/$n" ]; then
    rm -f -- "$d/$n"
    echo "removed $n"
  fi
done
for f in "$t"/*; do
  n=${f##*/}
  cmp -s "$f" "$d/$n" || {
    mv -- "$f" "$d/$n"
    echo "updated $n"
  }
done
