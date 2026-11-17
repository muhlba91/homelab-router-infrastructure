#!/bin/sh
# The SSH client setup of ./nx, run where ssh runs. NX_KEY: the deploy key there; NX_KNOWN_HOSTS:
# the pinned host key as a known_hosts line. Only the pinned host key is known; without one
# (an installer), the first key is accepted.
set -eu
[ -n "${NX_KEY:-}" ] || exit 0
mkdir -p ~/.ssh
chmod 700 ~/.ssh
install -m 600 "$NX_KEY" ~/.ssh/id_deploy
printf '%s\n' "${NX_KNOWN_HOSTS:-}" > ~/.ssh/known_hosts
if [ -n "${NX_KNOWN_HOSTS:-}" ]; then mode=yes; else mode=accept-new; fi
printf 'Host *\n  IdentityFile ~/.ssh/id_deploy\n  IdentitiesOnly yes\n  StrictHostKeyChecking %s\n' "$mode" > ~/.ssh/config
