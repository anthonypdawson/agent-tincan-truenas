# agent-tincan-truenas

Agent Tincan as a TrueNAS SCALE app: one Docker image, relay mode by
default, agent mode as an option.

Agent Tincan (upstream: https://github.com/mvanhorn/agent-tincan) lets
your AI agents ask each other for help, over Tailscale. A small relay
runs on your Tailscale network and every agent dials out to it, so
nothing needs an open port. This repo packages that relay as a TrueNAS
SCALE app, because the relay is the piece that wants an always-on home
and a NAS is the most always-on box most people own.

This is a community package, not upstream. Upstream ships release
binaries only; there is no Dockerfile or image there. This repo builds
the image from the upstream release binary and provides the TrueNAS
packaging.

## Relay vs agent mode

- **Relay (default).** The always-on hub every agent connects to. It
  joins your tailnet as `tincan-relay` (tsnet is built into the binary)
  and agents reach it at `http://tincan-relay`. This is what most people
  want on a NAS.
- **Agent (option, phase two).** Run an agent on the NAS itself, for
  example a web agent or a local agent that lives next to the relay.
  Same image, different command, its own state volume. Join is a
  two-step process with a short-lived invite code.

## Quick start (Route A)

TrueNAS SCALE 24.10+ → Apps → Discover Apps → Install via YAML, paste
`deploy/truenas/docker-compose.yaml`, and edit the three placeholders
(TS_AUTHKEY, `--admin`, and the state dataset path). Full runbook:
[deploy/truenas/TRUENAS.md](deploy/truenas/TRUENAS.md).

You need a Tailscale tailnet and a one-time auth key
(https://login.tailscale.com/admin/settings/keys). The relay's state
(relay.db, relay.key, invite-pepper, Tailscale node state) lives on a
mounted dataset so it survives app updates and restarts.

## Layout

```
Dockerfile                        Multi-arch image from the upstream release binary
.github/workflows/docker.yml      Build and publish the image to GHCR
deploy/truenas/
  docker-compose.yaml             Route A: plain compose, paste into Install via YAML
  TRUENAS.md                      Runbook: install, migration, agent mode, upgrades
  catalog/
    app.yaml                      Route B: catalog metadata
    questions.yaml                Route B: install wizard (mode, admin, auth key, state)
    ix_values.yaml                Route B: defaults the wizard can override
    templates/docker-compose.yaml Route B: Jinja2 + ix-lib template
```

`deploy/truenas/` is structured so the whole directory can lift into a
PR upstream (mvanhorn/agent-tincan) as `deploy/truenas/` later, once the
package is proven on a real NAS.

## Migrating an existing relay

If you already run a relay in a hand-rolled container, you can move it
to this app without re-joining agents, as long as the new app reuses
the existing relay state dir. See the migration section in
[deploy/truenas/TRUENAS.md](deploy/truenas/TRUENAS.md). Step 0 is
finding where the state lives; if it is container-local, pull the whole
state dir out with `docker cp` BEFORE stopping the old relay.

## Image

`ghcr.io/anthonypdawson/agent-tincan`, multi-arch linux/amd64 and
linux/arm64, built from the upstream release binary and verified against
that release's checksums.txt. Tags track upstream releases (`v0.28.2`,
`latest`). Build with `--build-arg TINCAN_VERSION=vX.Y.Z` to pin a
release.
