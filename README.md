# Jukebox

Office jukebox on a Lenovo ThinkCentre Tiny: [Music Assistant](https://www.music-assistant.io) plays YouTube Music to a Bluetooth speaker, guests queue songs from their phones via the Party plugin, and a TV shows the Party dashboard / Music Quiz.

Security requirements: [docs/security.md](docs/security.md). Read them before changing anything.

## Layout

```
flake.nix                  nixosConfigurations.jukebox
hosts/jukebox/             host values (jukebox.* options), facter.json
modules/
  options.nix              jukebox.* options
  disk.nix                 disko: ESP + LUKS2 (TPM2) + ext4 on /dev/nvme0n1
  boot.nix                 lanzaboote (Secure Boot), systemd initrd with TPM2
  base.nix                 nix, admin user, sshd, firewall, journald
  secrets.nix              sops-nix (host age key from the SSH host key), admin password
  hardening.nix            nix-mineral (audited overrides), sysctl, nscd/sshd/bluetoothd sandboxing
  audio.nix                BlueZ, PipeWire, squeezelite (user unit), speaker reconnect timer
  work-hours.nix           squeezelite runs only within jukebox.workHours
  music-assistant.nix      Music Assistant + providers
  po-token.nix             bgutil PO Token server (podman, loopback only)
  kiosk.nix                cage + Chromium kiosk with enterprise policies
  teams-bridge.nix         Teams bridge service (off until jukebox.bridge.enable)
bridge/                    Teams bridge: Graph polling -> Music Assistant -> Workflows replies
secrets/jukebox.yaml       sops-encrypted secrets
```

```
phones ──8095──► Music Assistant ──slimproto (lo)──► squeezelite ──► PipeWire ──► BT speaker
TV ◄── cage/Chromium ◄──────┘  └──► bgutil PO Token (127.0.0.1:4416) ──► YouTube
```

## Install

1. **Firmware:** set an admin password, enable boot from USB for the install only, leave Secure Boot off for now.
2. Boot the NixOS installer and generate the hardware report:
   ```sh
   sudo nix-shell -p nixos-facter --run nixos-facter > facter.json
   ```
   Copy it to `hosts/jukebox/facter.json`.
3. Fill in `hosts/jukebox/default.nix`: `timeZone`, `adminKeys`. Leave `speakerMac = null` until the speaker is paired.
4. Partition (prompts for the LUKS recovery passphrase — store it offline):
   ```sh
   sudo nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake .#jukebox
   ```
5. Create Secure Boot keys and copy them into the target:
   ```sh
   sudo nix run nixpkgs#sbctl -- create-keys
   sudo mkdir -p /mnt/var/lib && sudo cp -a /var/lib/sbctl /mnt/var/lib/
   ```
6. Pre-generate the SSH host key (it is the host's sops identity) and get its age recipient:
   ```sh
   sudo mkdir -p /mnt/etc/ssh
   sudo ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
   nix run nixpkgs#ssh-to-age < /mnt/etc/ssh/ssh_host_ed25519_key.pub
   ```
   Put that recipient and your admin age key into `.sops.yaml`, then on the admin workstation:
   ```sh
   mkpasswd -m yescrypt          # admin sudo password hash
   sops secrets/jukebox.yaml     # admin-password: <hash>
   ```
7. Install and reboot:
   ```sh
   sudo nixos-install --flake .#jukebox --no-root-passwd
   ```
8. **Secure Boot:** firmware → Secure Boot → reset to Setup Mode (do not clear dbx), boot, then:
   ```sh
   sudo sbctl enroll-keys --microsoft
   ```
   Reboot, check `bootctl status` shows `Secure Boot: enabled (user)`. Disable USB boot in firmware.
9. **TPM2 unlock** bound to Secure Boot state (PCR 7):
   ```sh
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
   ```

## Speaker

```sh
bluetoothctl
  power on
  pairable on
  scan on
  pair <MAC>
  trust <MAC>
  connect <MAC>
```

Set `jukebox.speakerMac = "<MAC>"` and redeploy; `bt-reconnect.timer` then reconnects every minute. Pairable/discoverable fall back to off after 180 s.

## Music Assistant setup (web UI, `http://jukebox:8095`)

1. Create the admin account.
2. Settings → disable **Remote Access**.
3. Music sources → YouTube Music: Login Cookie from the dedicated Google account, PO Token server `http://127.0.0.1:4416`.
4. Plugins → Party: Venue mode, player = Jukebox; set add/boost/skip token limits (§8.2 of the security doc).
5. Plugins → Music Quiz: Venue mode, player = Jukebox.
6. Kiosk: attach a keyboard once, log in to MA in the kiosk browser, open the Party dashboard, detach the keyboard.

## Work hours

`jukebox.workHours` (`days`, `start`, `end`, local time). Outside the window squeezelite is stopped and Music Assistant has no player; guests can still queue, playback resumes when the window opens.

## Teams bridge

Commands in the jukebox channel: `!dj play <song or link>`, `!dj skip` (vote), `!dj np`, `!dj help`; admins also `!dj stop`. Replies are posted through a Workflows webhook (Graph has no app-only channel posting outside migration).

1. **Team:** a dedicated team "Jukebox" with one channel (RSC scope is the whole team).
2. **Entra app registration:** single tenant, certificate credential (no client secret):
   ```sh
   openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=jukebox-bridge" -keyout bridge.key -out bridge.crt
   openssl x509 -in bridge.crt -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :
   ```
   Upload `bridge.crt` to the app; the second command prints the thumbprint.
3. **RSC:** in Teams Developer Portal create an app bound to that registration, add RSC permission `ChannelMessage.Read.Group` (Application), install it into the Jukebox team.
4. **Workflows:** in the Jukebox channel create a flow from the template "Post to a channel when a webhook request is received", owned by a service account; copy the URL.
5. **MA token:** in the MA web UI, profile → create a long-lived token for the bridge.
6. Secrets (`sops secrets/jukebox.yaml`), then delete the local key files:
   ```yaml
   bridge:
     graph-key: <contents of bridge.key>
     graph-thumbprint: <thumbprint>
     ma-token: <token>
     workflows-url: <url>
   ```
7. Host config:
   ```nix
   jukebox.bridge = {
     enable = true;
     tenantId = "...";
     clientId = "...";
     teamId = "...";
     channelId = "...";
     adminIds = ["<entra object id>"];
   };
   ```

## Deploy

From the admin segment:

```sh
nixos-rebuild switch --flake .#jukebox --target-host admin@jukebox --ask-sudo-password
```

## Acceptance

Run the checklist in [docs/security.md §14](docs/security.md#14-acceptance-checklist) before go-live and after major changes.
