# Agent Tincan on TrueNAS SCALE

Run Agent Tincan on TrueNAS SCALE 24.10+ (Electric Eel, Docker Compose
app engine). One image, two modes. Relay is the default and what most
people want. Agent mode is a phase-two option.

Upstream project: https://github.com/mvanhorn/agent-tincan
This package: https://github.com/anthonypdawson/agent-tincan-truenas
(a community package, not upstream)

## Before you start

You need a Tailscale tailnet and a Tailscale auth key. Generate one at
https://login.tailscale.com/admin/settings/keys (reusable or single-use;
tag it if you tag agent machines). The key is only needed for the
relay's first join. After that, the relay's node identity lives in its
state dir and the key is no longer needed.

Create a dataset for the relay state, for example
`/mnt/tank/apps/tincan-relay`. This holds relay.db, relay.key,
invite-pepper, wake.json, approval.json, the attachments directory, and
the Tailscale node state. It MUST survive app updates and restarts.
TrueNAS wipes files inside a container on update, so the state dir must
be a mounted dataset, not container-local storage. Back it up like any
database.

## Route A: paste-compose (fast, start here)

1. Go to Apps → Discover Apps → Install via YAML.
2. Paste `deploy/truenas/docker-compose.yaml`.
3. Edit the three placeholders:
   - `TS_AUTHKEY`: your Tailscale auth key.
   - `--admin my-laptop`: your admin machine name(s) as shown by
     `tailscale status`. Repeat `--admin` for more than one. The relay
     host itself is always an admin with no flags.
   - `/mnt/tank/apps/tincan-relay`: your state dataset path.
4. Install. The relay joins your tailnet as `tincan-relay`, and agents
   reach it at `http://tincan-relay`.
5. Invite agents from the relay host or an admin device:
   `tincan invite <name> --kind <kind>`, then paste the join message
   into that agent. Check with `tincan agents`.

No ports are exposed on the LAN and no host Tailscale install is needed:
the relay brings its own Tailscale node (tsnet is built into the
binary). The container only needs outbound internet to reach the
Tailscale control plane.

## Route B: catalog app (formal, for discoverability)

The `deploy/truenas/catalog/` directory is the formal catalog app: an
install wizard instead of hand-edited YAML. It is published by PR to
the official truenas/apps repo; there is no third-party catalog
mechanism in TrueNAS SCALE 24.10+.

- `app.yaml`: catalog metadata (name, description,
  `min_scale_version: 24.10.2.2`).
- `questions.yaml`: the wizard (mode, admin machine, TS_AUTHKEY as a
  masked secret, state dataset).
- `ix_values.yaml`: defaults the wizard can override.
- `templates/docker-compose.yaml`: the Jinja2 + ix-lib template that
  renders the relay (or agent) service from the wizard values.

Before publishing, render-validate the template on the target TrueNAS
version: ix-lib is vendored by the catalog CI at build time and is not
committed here, and the schema dialect drifts between releases.

## Migrating an existing relay to the app

The migration works only if the new app reuses the existing relay
state. Point the new app at the same state dir and it starts as the
same relay, same `tincan-relay` node, same key. Agents do not re-join
and nothing is lost. The only downtime is the swap itself: the old
container stops, the new one starts, and agents retry in between.

### Step 0: find where the state lives

Before touching anything, work out whether the current relay's state
dir is on a persistent dataset or container-local. Check how the relay
was started: the container's command and volume mounts. The default
state dir is `~/.config/tincan-relay`, unless a `--state-dir` was
passed.

- If it is on a dataset, note the path. That is the volume the new app
  mounts. Nothing to pull.
- If it is container-local, the state only exists inside the running
  container. It must be pulled out before the container stops, or it is
  gone and the migration becomes a fresh relay.

### If the state is container-local: pull it out first

Do this while the old relay is still running. Do not stop it first.

From the TrueNAS shell (System Settings → Shell) or over SSH, find the
container and copy the whole state dir to a dataset:

```
docker ps | grep -i tincan
docker cp <container>:/root/.config/tincan-relay /mnt/<pool>/apps/tincan-relay-state
```

Adjust the source path if the relay runs as a different user or with a
custom `--state-dir`. Copy the entire directory, not individual files:
the Tailscale node state sits in there alongside relay.db and relay.key,
and a partial copy is a broken relay. Verify the copy has relay.db,
relay.key, and invite-pepper, then back that dataset up before going
further.

### The swap

1. Confirm the state is safely on a dataset (and backed up).
2. Stop the old relay container. The old and new containers cannot both
   be `tincan-relay` at once.
3. Install the new app and point its state volume at that dataset.
4. Start it. No new `TS_AUTHKEY` is needed: the node identity is already
   in the state dir, so the relay rejoins as the same node.
5. Verify: `tincan agents` lists the team, `tincan doctor` is clean,
   and the relay answers at `http://tincan-relay`.

### If the state is already gone

If the state dir cannot be recovered, the new app starts a fresh relay
with a new key and a new node. Every agent has to re-join with a fresh
invite, and queued requests and history are lost. That is the disruptive
path, and the reason step 0 comes before stopping anything.

## Agent mode (phase two)

Same image, different command, its own state volume. This runs an agent
on the NAS itself, for example a web agent or a local agent that lives
next to the relay. Join is a two-step process and the invite code is
short-lived (10 minutes), so it is not a one-shot install the way the
relay is. See the commented-out `agent` service in
`deploy/truenas/docker-compose.yaml` and the `agent` branch of the
catalog template. The agent's state must NOT share the relay's state
dir.

## Upgrading

The relay is started with `--dist` and `--release-url`, so from an admin
device run `tincan relay-upgrade --from-github <version>` to upgrade the
relay without a new image, then `tincan upgrade` on each agent machine.
Or pull a newer image tag and restart the app; the state dir carries the
relay across.
