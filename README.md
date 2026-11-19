# Homelab: Router Infrastructure

[![Build status](https://img.shields.io/github/actions/workflow/status/muhlba91/homelab-router-infrastructure/pipeline.yml?style=for-the-badge)](https://github.com/muhlba91/homelab-router-infrastructure/actions/workflows/pipeline.yml)
[![License](https://img.shields.io/github/license/muhlba91/homelab-router-infrastructure?style=for-the-badge)](LICENSE.md)
[![](https://api.scorecard.dev/projects/github.com/muhlba91/homelab-router-infrastructure/badge?style=for-the-badge)](https://scorecard.dev/viewer/?uri=github.com/muhlba91/homelab-router-infrastructure)

This repository contains the automation for the [NixOS](https://nixos.org) homelab routers (sites) connected via an
optional [NetBird](https://netbird.io) underlay using [Pulumi](https://www.pulumi.com).

For each enabled site, it creates the deploy SSH key, the router's SSH host key, the AdGuard Home password, the NetBird
setup key if the site uses NetBird and the NUT password if it has a UPS, and renders the site's `vars.nix` which the NixOS router configuration
consumes.

---

## Repository Layout

- [infrastructure/](infrastructure/): the Pulumi program (Go) that creates the per-site resources and renders the site data
- [nix/](nix/): the NixOS router configuration (a flake): `modules/` (one module set for every site; the vars schema in
  `modules/options/`), `hardware/`, `libvirt/` (the VM template and apply script), `tests/` (checks, eval tests,
  fixtures), and the `router` and `nx` scripts
- [docs/](docs/): [troubleshooting](docs/troubleshooting.md), [Proxmox](docs/proxmox.md) (host, router VM, first
  install), [physical router](docs/physical.md) (bench install and swap), [dedicated server](docs/server.md),
  [VMs on a server](docs/libvirt.md), [router validation](docs/validation.md) and the move from a public LAN IPv6 prefix to [ULA + NAT66](docs/ula-nat66.md)

---

## Requirements

- [mise](https://mise.jdx.dev) for Go, golangci-lint, Pulumi, fnox and Vault
- [podman](https://podman.io) for the NixOS routers in [nix/](nix/) (or a local [Nix](https://nixos.org/download/))

## Deploying the Infrastructure

A [Pulumi Stack](https://www.pulumi.com/docs/concepts/stack/) with the [configuration](#configuration) below must exist.
It reads the NetBird connection from the output `netbird` of the `muehlbachler-core-infrastructure` stack with the same
name, which must exist (also if no site uses NetBird).

Deploy it with:

```bash
cd infrastructure
pulumi up
```

The generated files are written to `infrastructure/outputs/` and uploaded to the configured bucket under the same paths:

- `sites/<site>/vars.nix`: the site's data for the NixOS router configuration (no secrets; `sites/` is the Nix input
  and must never hold anything else)
- `keys/<site>/deploy-key`: the private SSH key of the `deploy` user (enabled sites only)
- `keys/<site>/secrets/ssh-host-key`: the router's SSH host key (enabled sites only; its public key is pinned in
  `vars.nix`, so `./router` accepts no other key)
- `keys/<site>/adguard-password`: the password of the AdGuard Home user `admin` (enabled sites only; not pushed)
- `keys/<site>/secrets/adguard-password-hash`: its bcrypt hash, which the router configures (enabled sites only)
- `keys/<site>/secrets/netbird-setup-key`: the NetBird setup key (enabled sites using NetBird only)
- `keys/<site>/secrets/nut-password`: the password of the NUT user `upsmon` (enabled sites with a UPS only)
- `keys/<site>/secrets/crowdsec-enroll-key`: the CrowdSec console enroll key (enabled sites with
  `security.crowdsec.console.enabled` only)

`pulumi destroy` (in `infrastructure/`) removes everything again.

## Environment Variables

The credentials come from Vault through [fnox](https://fnox.jdx.dev) (installed by mise; CI and local profiles in
[fnox.toml](fnox.toml); locally `FNOX_PROFILE=dev`):

- Google Cloud credentials (secrets encryption: Cloud KMS) and a Pulumi token
- `SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_ORGANIZATION_ID`, `SCW_PROJECT_ID`, `SCW_DEFAULT_REGION`, `SCW_DEFAULT_ZONE`:
  Scaleway

```bash
cd infrastructure
fnox exec -- pulumi preview --stack prod
```

`fnox.local.toml` (git-ignored) overrides values for experiments.

---

## Configuration

The following section describes the configuration which must be set in the Pulumi Stack.

> [!IMPORTANT]
> Use [Secrets Encryption](https://www.pulumi.com/docs/concepts/secrets/) provided by Pulumi for secret values!

### Bucket

The bucket to upload the generated files to.

```yaml
bucketId: the ID of the Scaleway bucket
```

### CrowdSec Console

Optional. `enrollKey` is the enroll key of the CrowdSec console account (one for all sites). Sites with
`security.crowdsec.console.enabled` enroll once under their hostname (accept them in the console afterwards); without
the key their enrollment is turned off with a warning.

```yaml
crowdsec:
  enrollKey: the enroll key (secret: pulumi config set --secret --path crowdsec.enrollKey)
```

### NetBird

NetBird connection configuration. The values will be retrieved from the output `netbird` of the corresponding core
infrastructure stack: `address`, `pat`, `client.ipv4` (the hub's NetBird IP) and `backboneGroup` (the group every setup
key assigns).

> [!IMPORTANT]
> The output and all its values are required, even if no site uses NetBird.

### Site YAML

Sites are defined in YAML format. For each site to create a YAML file must be created in
[infrastructure/assets/sites/](infrastructure/assets/sites/), named after the site (`<name>.yml`, also its hostname),
optionally prefixed with its deploy order (`<order>-<name>.yml`, e.g. `000-lab-router-001.yml`): the routers are
deployed in ascending order, sites without one last. The hundreds are categories: `0xx` test systems, `1xx` OVH, `2xx`
Hetzner, `9xx` physical sites (deployed last).

A site must be enabled explicitly (`enabled: true`); a disabled site is rendered but not deployable, and gets none of
the generated keys and secrets above. Disabling a deployed site deletes them: the router keeps the old ones, so it is
not reachable by `./router` again until it is reinstalled (or the new keys are handed over by hand). CI deploys an
enabled site only with `deploy.automated: true`; without it the site keeps its keys and is deployed by hand (e.g. while
its router is installed, until the cutover).

The format is described in the [template](infrastructure/assets/templates/site.yml).

> [!WARNING]
> Values are rendered into Nix strings without escaping. A backslash must be doubled (e.g. the DNS filter rule
> `/ads\\d+\\.example/`), and values must not contain `"` or `${` (nor `''` in the raw firewall rules).

### SSH Keys

The static public SSH keys of the `deploy` user (the same for every site) are defined as `*.pub` files in
[infrastructure/assets/ssh/](infrastructure/assets/ssh/), one key per line. The site's generated deploy key is added to
them.

---

## NixOS Routers

The routers are built from [nix/](nix/), using the site data Pulumi rendered. All commands run from `nix/`; Nix runs in a
[podman](https://podman.io) container (nothing to install but podman), or directly if `nix` is on the `PATH` (CI).
Hardware profiles (`nix/hardware/`): `qemu` for every VM router (BIOS or UEFI), `n100` for an Intel N100/N150 mini PC
(UEFI, systemd-boot; its disk by `/dev/disk/by-id/`), `server-zfs` for a dedicated server with two NVMe disks in a ZFS
mirror that is router and hypervisor. The first install: [docs/proxmox.md](docs/proxmox.md) (a VM),
[docs/physical.md](docs/physical.md) or [docs/server.md](docs/server.md); the checks after an install or migration:
[docs/validation.md](docs/validation.md).

The site data is read from `OUTPUTS` (default `../infrastructure/outputs`): `sites/` becomes the flake's `sites` input
(copied into the Nix store, so nothing but `<site>/vars.nix` is allowed there), `keys/` is only used by the commands that
connect to a router. Without site data, the fixtures in [nix/tests/sites/](nix/tests/sites/) (documentation addresses
only) are used.

`./router` without arguments lists the commands: `sites`, `check`, `fmt`, `dump`, `golden` (rewrites the stored dumps
of the shared fixtures, which a flake check compares), `push-secrets`, `deploy` (with magic rollback; skipped if
current), `health` (failed units, BGP, a server's ZFS pool), `install` (nixos-anywhere; wipes the disk), `ssh`,
`virsh` (on a server's host), `libvirt-render` and `libvirt-deploy` (a VM from a spec), all run from `nix/`.

Secrets are never part of the configuration: they are files pushed to `/var/lib/secrets` on the router, where the
configuration only declares their names, owners and modes.

---

## Addressing

IPv4 addresses are allocated in blocks of ten /16s inside `10.0.0.0/8`. A site owns a block, and its LAN is the
block's first /16. New sites take the next free block. The Hetzner LAN moves to its block when the router is
reinstalled.

| Block | Purpose | LAN |
| --- | --- | --- |
| `10.0`-`10.9` | `vie` | `10.0.0.0/16` |
| `10.10`-`10.19` | Spare | |
| `10.20`-`10.29` | Cloud and core | `10.21.0.0/16` core network |
| `10.30`-`10.39` | Next server site | |
| `10.40`-`10.49` | Hetzner | `10.40.0.0/16` |
| `10.50`-`10.59` | OVH | `10.50.0.0/16` |
| `10.60`-`10.69` | Lab and test | `10.60.0.0/16` |
| `10.70`-`10.99` | Spare (examples in templates and fixtures) | |
| `10.100`-`10.199` | Kubernetes services and load balancer pools | |
| `10.244`-`10.249` | Kubernetes pod CIDRs | |
| `10.250`-`10.255` | Overlay and mesh (NetBird, client NAT) | |

The host part of the LAN is the same on every site:

| Host part | Use |
| --- | --- |
| `.0.1` | Router |
| `.50.x` | Kubernetes nodes |
| `.60.x` | Dev hosts |
| `.70.1`-`.79.255` | Cilium L2 load balancer pool |
| `.150.1`-`.199.255` | DHCPv4 pool |

IPv6 follows the same host parts inside the site's prefix (`::1` router, `::1:1:1` node, `::3:x:y` load balancer,
`::60:1` dev host).

---

## Testing

- `make test` (in `infrastructure/`): the Go tests, including a render of every site file and of the site template
  (as the site `site`) under Pulumi mocks; `RENDER_DIR=<dir>` keeps the rendered files.
- `./router check` (in `nix/`): the flake checks, see [checks.nix](nix/tests/checks.nix): lint, eval tests on the
  fixtures, stored dumps of the shared fixtures and the VM domain XML (`golden-*`; `./router golden` rewrites them after
  an intended change),
  and per site the tools' own checks of its nftables, radvd, Kea and FRR configuration.
- Both together check the whole chain from the site files to the router configuration:

```bash
cd infrastructure && RENDER_DIR=/tmp/render go test -run TestRunEnabled ./pkg/program/
cd ../nix && OUTPUTS=/tmp/render/outputs ./router check
```

---

## Router Ports

The ports a router accepts connections on. Everything else is dropped. Sources are zones: `lan` (the site's LAN), `mesh`
(the other sites, routed through the EVPN overlay), `trusted` (the trusted networks of the site file; on the WAN only if
allowed there) and `wan`.

The services of a site can be overridden in its site file (`firewall.services`); optional features open their ports only
when enabled. The source of truth is [firewall.nix](nix/modules/options/firewall.nix): keep this table in sync.

| Port | Protocol | From | Function |
| --- | --- | --- | --- |
| 22 | TCP | lan, trusted (wan: per site, set on the servers) | SSH (keys only) |
| 53 | TCP, UDP | lan, mesh, trusted | DNS (AdGuard Home) |
| 67, 547 | UDP | lan | DHCPv4, DHCPv6 (Kea) |
| 123 | UDP | lan | NTP (chrony) |
| 3000 | TCP | lan, trusted | AdGuard Home web interface and API |
| 9100 | TCP | lan, trusted | Prometheus: node exporter (system metrics; with monitoring) |
| 9547 | TCP | lan, trusted | Prometheus: Kea exporter (DHCP leases and pools; with monitoring) |
| 9342 | TCP | lan, trusted | Prometheus: FRR exporter (BGP sessions and routes; with monitoring) |
| 9633 | TCP | lan, trusted | Prometheus: smartctl exporter (disk health; with monitoring) |
| 6060 | TCP | lan, trusted | Prometheus: CrowdSec metrics (with monitoring and CrowdSec) |
| 9199 | TCP | lan, trusted | Prometheus: NUT exporter (UPS status; with monitoring and a UPS) |
| 3493 | TCP | lan | NUT server (UPS status for other hosts, e.g. Home Assistant; login `upsmon`; with a UPS) |
| 51820 | UDP | any but the mesh | NetBird (WireGuard) underlay (with NetBird; the port is configurable; never sent into the mesh either) |
| 179 | TCP | BGP neighbors | BGP (only from the configured neighbors) |
| 3784, 4784 | UDP | BGP neighbors | BFD (only with a neighbor using it) |
| 4789 | UDP | NetBird overlay | VXLAN of the EVPN overlay (with EVPN; only from the overlay range on the NetBird interface) |
| 546 | UDP | wan | DHCPv6 client replies (with DHCPv6 on the WAN) |

ICMP and ICMPv6 are accepted from everywhere; echo requests from the WAN are limited per source (`firewall.icmpEchoRate`).

Outgoing only (no port opened): logs to the central Vector (`observability.logging.vector`), CrowdSec's hub and
community blocklist, NetBird's management service.

---

## Development

The tools are managed with [mise](https://mise.jdx.dev):

```bash
mise trust && mise install   # once
make lint && make test       # in infrastructure/
./router check               # in nix/
```

---

## Continuous Integration and Automations

- [GitHub Actions](https://docs.github.com/en/actions):
  - pull requests: the Go lint and tests; every Nix flake check as its own job (on the fixtures); the Pulumi preview,
    commented on the pull request with the diff of every router's `vars.nix`; the Nix checks of every site on the
    rendered site files; a complete build of every rendered router system (`Nix Build`, a matrix of sites);
  - `main`: the preview and the Nix checks gate `pulumi up`; then every router with `deploy.automated` is deployed in deploy order
    (`./router deploy`, one at a time, a failure stops the rest, a current router is skipped) and checked with
    `./router health`. The runner reaches the routers through Tailscale (`tag:github-actions` needs SSH to their
    management addresses).
- [Renovate](https://github.com/renovatebot/renovate):
  - Go modules, GitHub Actions, pre-commit hooks and the `nx` image (`nix/Containerfile`): patch, minor and digest
    updates are automerged;
  - `nix/flake.lock`: every Sunday 8-12 (Europe/Vienna), automerged, so the routers are deployed right after;
  - a new NixOS release (the `nixpkgs` input of `nix/flake.nix`): a pull request only.
