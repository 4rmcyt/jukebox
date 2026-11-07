# Compose variant — design

Status: agreed design, not implemented. For other offices. NixOS stays the hardened reference variant; this one is a single `compose.yml` an office admin can run on any Linux host with Docker.

## Host requirements

- Linux with Docker Engine and the compose plugin. Docker Desktop on Windows/macOS is not supported: no host networking, no host audio.
- A user session with PipeWire (`pipewire-pulse`) running — any desktop Linux does this out of the box.
- The Bluetooth speaker paired and trusted on the host, once (desktop Bluetooth settings, or `bluetoothctl` `pair` / `trust` / `connect`). Pairing is not done from a container: that would need the host's system D-Bus and BlueZ.
- Inbound traffic limited to 443 by the office network (the containers only expose 443).
- A screen is any browser opening `https://<fqdn>/` (TV browser, mini PC, the host itself in full screen); it is not part of compose.

## Setup

```
git clone … && git checkout <tag>
cp .env.example .env            # office settings
# write secret files into ./secrets/ (0600)
docker compose up -d
```

Updates: `git checkout <new tag> && docker compose up -d --build`.

## Services

| Service | Image | Network | Notes |
|---|---|---|---|
| Music Assistant | official, pinned version | host | MA requires host networking ([docs](https://www.music-assistant.io/installation/)); bind to 127.0.0.1 in MA settings |
| PO Token (bgutil) | pinned digest | bridge, `127.0.0.1:4416` | |
| Squeezelite | built from `compose/squeezelite/Dockerfile` (Debian `squeezelite-pulseaudio`) | host | host PipeWire via the Pulse socket mount `/run/user/<uid>/pulse/native`, runs as that uid; **untested** |
| Caddy | built from `compose/caddy/Dockerfile` (`xcaddy` + Cloudflare DNS plugin, pinned) | host | 443; proxies MA, `/stats` and `/mcp` limited to admin nets |
| Bridge | built from `bridge/Dockerfile` | host | MA at `127.0.0.1:8095`, stats on `127.0.0.1:8096` |

All containers: `cap_drop: [ALL]` plus only what each needs, `security_opt: [no-new-privileges:true]`, `read_only: true` where the image allows it, `restart: unless-stopped`.

The bridge needs no code change: compose sets `CREDENTIALS_DIRECTORY=/run/secrets` and `STATE_DIRECTORY` to a data volume.

## Work hours

The squeezelite container's entrypoint runs squeezelite only inside work hours (same day/time check as `modules/work-hours.nix`) and stops it outside them. Outside hours the player is absent, so nothing can play — not the bridge, Party or the MA UI.

MA's `players/cmd/power` exists for squeezelite ([controller.py:920](https://github.com/music-assistant/server/blob/2.10.9/music_assistant/controllers/players/controller.py#L920)) but anyone with the MA UI can power the player back on, so it is not used for this.

## Speaker reconnect

To check during implementation: whether WirePlumber on the host reconnects the trusted speaker by itself. If not, the bridge reports a missing player to the channel; reconnecting stays a host task (NixOS has a timer for it).

## Settings and secrets

- `.env`: time zone, work days and hours, FQDN, ACME email, admin nets, bridge IDs (tenant, client, team, channel, admin IDs), allowed link domains, retention days.
- `./secrets/` (git-ignored), mounted as compose secrets: `graph-key`, `graph-thumbprint`, `ma-token`, `workflows-url` (owned by uid 10001, the bridge user, mode `0400`) and `cloudflare-token` (root, `0400`; Caddy reads it with `{file./run/secrets/cloudflare-token}`). Compose bind-mounts secret files with their host ownership.

## Open items

- Weekly Teams report: on NixOS a systemd timer runs `jukebox-bridge report`; compose has no scheduler yet (`!dj stats` and `/stats` work).
- Music Assistant is not `read_only`: which paths it writes besides `/data` is unverified.
- Docker has no `--userns=auto`; containers run without user-namespace remapping unless the host enables `userns-remap`.
- Caddy runs with `admin off`; config changes ship as a rebuilt image.

## Releases

`main` only; releases are tags with a `CHANGELOG.md` entry listing manual steps for breaking changes.

## Compared with NixOS

Kept: loopback-only services, TLS, secrets outside git, Graph RSC + Workflows, work hours, link verification.
Not in compose: host firewall, disk encryption and TPM unlock, Secure Boot, kernel/sysctl hardening, systemd sandboxing, kiosk lockdown, atomic rollback. Acceptable for an office jukebox holding a YT Music cookie, a Teams app certificate and a Cloudflare token; the office decides on disk encryption and host hardening.

## Layout

```
compose.yml, .env.example
compose/squeezelite/   Dockerfile, entrypoint (work hours)
compose/caddy/         Dockerfile, Caddyfile
bridge/Dockerfile
docs/installation-compose.md
```

## Order of work

1. Squeezelite container against host PipeWire — the riskiest part, test first.
2. `bridge/Dockerfile`, Caddy image, `compose.yml`.
3. `installation-compose.md` (host requirements, pairing, MA setup, Microsoft 365 part shared with `installation.md`).
