# Homelab: Router Infrastructure

[![Build status](https://img.shields.io/github/actions/workflow/status/muhlba91/homelab-router-infrastructure/pipeline.yml?style=for-the-badge)](https://github.com/muhlba91/homelab-router-infrastructure/actions/workflows/pipeline.yml)
[![License](https://img.shields.io/github/license/muhlba91/homelab-router-infrastructure?style=for-the-badge)](LICENSE.md)
[![](https://api.scorecard.dev/projects/github.com/muhlba91/homelab-router-infrastructure/badge?style=for-the-badge)](https://scorecard.dev/viewer/?uri=github.com/muhlba91/homelab-router-infrastructure)

This repository contains the automation for the [NixOS](https://nixos.org) homelab routers (sites) connected via an optional [NetBird](https://netbird.io) underlay using [Pulumi](http://pulumi.com).

For each enabled site, it creates the deploy SSH key, the router's SSH host key, the AdGuard Home password, the NetBird
setup key if the site uses NetBird and the NUT password if it has a UPS, and renders the site's `vars.nix` which the NixOS router configuration
consumes.

---

## Repository Layout

- [infrastructure/](infrastructure/): the Pulumi program (Go) that creates the per-site resources and renders the site data
- [nix/](nix/): the NixOS router configuration (a flake): `modules/` (one module set for every site; the vars schema in
  `modules/options/`), `hardware/` (hardware profiles), `tests/` (checks, eval tests, fixtures), `router`, `nx` and
  its image (`Containerfile`)
- [docs/](docs/): [Proxmox](docs/proxmox.md) (host, router VM, first install) and [router validation](docs/validation.md)

---

## Requirements

- [Go](https://golang.org/dl/)
- [Pulumi](https://www.pulumi.com/docs/install/)
- [podman](https://podman.io) for the NixOS routers in [nix/](nix/) (or a local [Nix](https://nixos.org/download/))

## Creating the Infrastructure

To create the services, a [Pulumi Stack](https://www.pulumi.com/docs/concepts/stack/) with the correct configuration needs to exist.

The stack reads the NetBird connection from the output `netbird` of the `muehlbachler-core-infrastructure` stack with the same name, which must exist (also if no site uses NetBird).

The stack can be deployed via:

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

## Destroying the Infrastructure

The entire infrastructure can be destroyed via:

```bash
cd infrastructure
pulumi destroy
```

## Environment Variables

To successfully run, and configure the Pulumi plugins, you need to set a list of environment variables. Alternatively, refer to the used Pulumi provider's configuration documentation.

- `GOOGLE_APPLICATION_CREDENTIALS`: reference to a file containing the Google Cloud (GCP) service account credentials (secrets encryption)
- `SCW_ACCESS_KEY`: the Scaleway access key
- `SCW_SECRET_KEY`: the Scaleway secret key
- `SCW_ORGANIZATION_ID`: the Scaleway organization ID
- `SCW_PROJECT_ID`: the Scaleway project ID
- `SCW_DEFAULT_REGION`: the Scaleway default region
- `SCW_DEFAULT_ZONE`: the Scaleway default zone
- `PULUMI_ACCESS_TOKEN`: the Pulumi access token

---

## Configuration

The following section describes the configuration which must be set in the Pulumi Stack.

***Attention:*** do use
[Secrets Encryption](https://www.pulumi.com/docs/concepts/secrets/#:~:text=Pulumi%20never%20sends%20authentication%20secrets,“secrets”%20for%20extra%20protection.)
provided by Pulumi for secret values!

### Bucket

The bucket to upload the generated files to.

```yaml
bucketId: the ID of the Scaleway bucket
```

### NetBird

NetBird connection configuration. The values will be retrieved from the output `netbird` of the corresponding core
infrastructure stack: `address`, `pat`, `client.ipv4` (the hub's NetBird IP) and `backboneGroup` (the group every setup
key assigns).

Attention: the output and all its values are required, even if no site uses NetBird.

### Site YAML

Sites are defined in YAML format. For each site to create a YAML file must be created in
[infrastructure/assets/sites/](infrastructure/assets/sites/), named after the site (`<name>.yml`, also its hostname),
optionally prefixed with its deploy order (`<order>-<name>.yml`, e.g. `000-test-router.yml`): the routers are
deployed in ascending order, sites without one last. The hundreds are categories: `0xx` test systems, `1xx` OVH, `2xx`
Hetzner, `9xx` physical sites (deployed last).

A site must be enabled explicitly (`enabled: true`); a disabled site is rendered but not deployable, and gets none of
the generated keys and secrets above. Disabling a deployed site deletes them: the router keeps the old ones, so it is
not reachable by `./router` again until it is reinstalled (or the new keys are handed over by hand).

The format is described in the [template](infrastructure/assets/templates/site.yml).

Attention: values are rendered into Nix strings without escaping. A backslash must be doubled (e.g. the DNS filter rule
`/ads\\d+\\.example/`), and values must not contain `"` or `${` (nor `''` in the raw firewall rules).

### SSH Keys

The static public SSH keys of the `deploy` user (the same for every site) are defined as `*.pub` files in
[infrastructure/assets/ssh/](infrastructure/assets/ssh/), one key per line. The site's generated deploy key is added to
them.

---

## NixOS Routers

The routers are built from [nix/](nix/), using the site data Pulumi rendered. All commands run from `nix/`; Nix runs in a
[podman](https://podman.io) container (nothing to install but podman), or directly if `nix` is on the `PATH` (CI).
Every VM router uses the hardware profile `qemu` (BIOS or UEFI); the settings of a Proxmox VM and its first install are
in [docs/proxmox.md](docs/proxmox.md), the checks after an install or migration in [docs/validation.md](docs/validation.md).

The site data is read from `OUTPUTS` (default `../infrastructure/outputs`): `sites/` becomes the flake's `sites` input
(copied into the Nix store, so nothing but `<site>/vars.nix` is allowed there), `keys/` is only used by the commands that
connect to a router. Without site data, the fixtures in [nix/tests/sites/](nix/tests/sites/) (documentation addresses
only) are used.

```bash
cd nix
./router sites                   # the sites (in deploy order) and whether they are deployable
./router check                   # all checks (see Testing)
./router fmt                     # format all .nix files
./router dump <site>             # the evaluated configuration as JSON (diff before/after a change)
./router push-secrets <site>     # deliver the site's secrets to the router
./router deploy <site>           # push the secrets, then deploy-rs (with magic rollback); skipped if current
./router health <site>           # failed units, BGP sessions, and whether a reboot is pending
./router install <site> <ip>     # first install of a new box with nixos-anywhere (wipes the disk)
./router ssh <site> [command]    # SSH as the deploy user
```

Secrets are never part of the configuration: they are files pushed to `/var/lib/secrets` on the router, where the
configuration only declares their names, owners and modes.

---

## Testing

- `make test` (in `infrastructure/`): the Go tests, including a render of every site file and of the site template
  (as the site `site`) under Pulumi mocks; `RENDER_DIR=<dir>` keeps the rendered files.
- `./router check` (in `nix/`): the flake checks: formatting and linting of the Nix code and shellcheck of the scripts,
  the deploy-rs schema, eval tests on the fixtures (derived values, and invalid vars that must fail), and per site:
  the system evaluates, its nftables ruleset, radvd, Kea and FRR configurations pass the tools' own checks.
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

The services of a site can be overridden in its site file (`firewall.services`); optional features open their ports only when enabled.

| Port | Protocol | From | Function |
| --- | --- | --- | --- |
| 22 | TCP | lan, trusted | SSH (keys only) |
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
| 51820 | UDP | any but the mesh | NetBird (WireGuard) underlay (with NetBird; the port is configurable) |
| 179 | TCP | BGP neighbors | BGP (only from the configured neighbors) |
| 3784, 4784 | UDP | BGP neighbors | BFD (only with a neighbor using it) |
| 4789 | UDP | NetBird overlay | VXLAN of the EVPN overlay (with EVPN; only from the overlay range on the NetBird interface) |
| 546 | UDP | wan | DHCPv6 client replies (with DHCPv6 on the WAN) |

Outgoing only (no port opened): logs to the central Vector (`observability.logging.vector`), CrowdSec's hub and community blocklist, NetBird's management service.

---

## Continuous Integration and Automations

- [GitHub Actions](https://docs.github.com/en/actions):
  - pull requests: the Go lint and tests; every Nix flake check as its own job (on the fixtures); the Pulumi preview,
    commented on the pull request with the diff of every router's `vars.nix`; the Nix checks of every site on the
    rendered site files; a complete build of selected router systems (`Nix Build`, a matrix of sites);
  - `main`: the preview and the Nix checks gate `pulumi up`; then every deployable router is deployed in deploy order
    (`./router deploy`, one at a time, a failure stops the rest, a current router is skipped) and checked with
    `./router health`. The runner reaches the routers through Tailscale (`tag:github-actions` needs SSH to their
    management addresses).
- [Renovate](https://github.com/renovatebot/renovate):
  - Go modules, GitHub Actions, pre-commit hooks and the `nx` image (`nix/Containerfile`): patch, minor and digest
    updates are automerged;
  - `nix/flake.lock`: every Sunday 8-12 (Europe/Vienna), automerged, so the routers are deployed right after;
  - a new NixOS release (`nixos-26.05` in `nix/flake.nix`): a pull request only.
