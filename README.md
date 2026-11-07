# Jukebox

Office jukebox on a Lenovo ThinkCentre Tiny: [Music Assistant](https://www.music-assistant.io) plays YouTube Music to a Bluetooth speaker, guests queue songs from their phones via the Party plugin, and a TV shows the Party dashboard / Music Quiz. Optional: a Teams channel bridge and MCP access for AI clients.

- Install: [docs/installation.md](docs/installation.md)
- Security requirements: [docs/security.md](docs/security.md) — read before changing anything.

## Layout

```
flake.nix                  nixosConfigurations.jukebox, packages.teams-bridge
hosts/jukebox/             host wiring: values from the private input
modules/
  options.nix              jukebox.* options
  disk.nix                 disko: ESP + LUKS2 (TPM2) + ext4 on /dev/nvme0n1
  boot.nix                 lanzaboote (Secure Boot), systemd initrd with TPM2
  secrets.nix              sops-nix (host age key from the SSH host key), admin password
  base.nix                 nix, admin user, sshd, firewall, journald
  hardening.nix            nix-mineral (audited overrides), sysctl, nscd/sshd/bluetoothd sandboxing
  audio.nix                BlueZ, PipeWire, squeezelite (user unit), speaker reconnect timer
  work-hours.nix           squeezelite runs only within jukebox.workHours
  music-assistant.nix      Music Assistant + providers
  caddy.nix                HTTPS on 443 (Let's Encrypt via Cloudflare DNS-01) -> MA on loopback
  po-token.nix             bgutil PO Token server (podman, loopback only)
  kiosk.nix                cage + Chromium kiosk with enterprise policies
  teams-bridge.nix         Teams bridge + weekly report timer + /stats route (off until jukebox.bridge.enable)
bridge/                    Teams bridge: Graph polling -> Music Assistant -> Workflows replies; request/play log + reports
docs/private-example.nix   schema of the private input
```

Office-specific values (time zone, admin keys, speaker MAC, work days, Entra/Teams IDs), the hardware report and the sops secrets live in the private repo `jukebox-private`, consumed as the `private` flake input. Nothing office-specific goes into this repo.

To work on an unpushed private checkout: `--override-input private path:../jukebox-private`.

```
phones ──443──► Caddy ──► Music Assistant ──slimproto (lo)──► squeezelite ──► PipeWire ──► BT speaker
TV ◄── cage/Chromium ◄──────┘  └──► bgutil PO Token (127.0.0.1:4416) ──► YouTube
Teams ◄─Workflows── teams-bridge ──Graph poll──► Teams
```

## Work hours

`jukebox.workHours` (`days` from the private `workDays`, `start` 07:00, `end` 17:00, local time). Outside the window squeezelite is stopped and Music Assistant has no player; guests can still queue, playback resumes when the window opens.

## Deploy

From the admin segment:

```sh
nixos-rebuild switch --flake .#jukebox --target-host admin@jukebox --ask-sudo-password
```

After changing the private repo: push it, then `nix flake update private` here first.
