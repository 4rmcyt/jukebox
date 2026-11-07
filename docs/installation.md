# Installation

End-to-end setup of the jukebox on a Lenovo ThinkCentre Tiny: network on the FTD, the host itself, Music Assistant, and the Microsoft 365 side of the Teams bridge. Every step is run by the administrator; nothing here is automated.

Read [security.md](security.md) first — most steps below exist to satisfy it. Items marked ⚠ name a UI path or setting that was not checked against the live console; confirm on first use and fix this document.

## 0. Prerequisites

**Hardware**

- Lenovo ThinkCentre Tiny with a single NVMe disk, Bluetooth, TPM 2.0.
- Bluetooth speaker; TV/monitor for the kiosk.
- USB stick with the NixOS minimal installer (unstable ISO).
- Temporary USB keyboard (installer, firmware, one kiosk login).

**Accounts**

- Dedicated Google account with YouTube Music Premium, 2FA on, recovery to a corporate mailbox.
- Microsoft 365: Teams administrator + Entra role able to register applications (only for the Teams bridge, §13).
- A licensed Microsoft 365 service account for the Workflows flow (§13.5).

**Admin workstation** (in the admin segment)

- `git`, `sops`, `ssh`, `mkpasswd`, `openssl`; your age key in `~/.config/sops/age/keys.txt`; your SSH key.
- Both repos checked out side by side:
  ```
  ~/src/jukebox            public: code
  ~/src/jukebox-private    private: office.nix, facter.json, .sops.yaml, secrets/
  ```

## 1. Network: FTD / FMC

Implements [security.md §2](security.md#2-network). Names below are suggestions; keep whatever convention the FMC already uses.

### 1.1 VLAN and interface

1. Pick a VLAN ID and a small subnet (a /29 is enough) for the jukebox; trunk the VLAN to the switch port where the Tiny sits.
2. FMC → **Devices → Device Management** → edit the FTD → **Interfaces** → add a **subinterface** on the inside trunk with that VLAN ID, gateway IP, and a new security zone `jukebox-zone`.
3. DHCP: reserve one address for the Tiny's NIC MAC on whatever serves DHCP for that VLAN (the host keeps its real MAC — random MAC is disabled in `modules/hardening.nix`). The MAC is known after §4 (`facter.json` or the installer's `ip link`); until then a temporary lease is fine.

### 1.2 Objects

FMC → **Objects → Object Management**:

| Type | Name | Value |
|---|---|---|
| Network (host) | `jukebox-host` | the reserved IP |
| Network (group) | `jukebox-staff-nets` | staff client subnets (wired + staff Wi-Fi) |
| Network (group) | `jukebox-admin-net` | admin segment |
| Network (group) | `corp-dns` / `corp-ntp` | corporate resolvers / NTP servers |
| Network (group) | `internal-nets` | all internal ranges (RFC 1918 + any internal public space) |
| Port | `tcp-443` | TCP 443 (Caddy: MA web UI, Party guest view, MCP) |
| Port | `tcp-22` | TCP 22 |

### 1.3 Access control rules

FMC → **Policies → Access Control** → edit the policy applied to the FTD → add rules in this order (more specific first), all with **Log at End of Connection**:

| # | Action | Source | Destination | Port | Purpose |
|---|---|---|---|---|---|
| 1 | Allow | `jukebox-staff-nets` | `jukebox-host` | `tcp-443` | Party guest view from phones/laptops |
| 2 | Allow | `jukebox-admin-net` | `jukebox-host` | `tcp-22`, `tcp-443` | SSH (deploys), MA admin UI, MCP |
| 3 | Allow | `jukebox-host` | `corp-dns` | DNS (TCP/UDP 53) | name resolution |
| 4 | Allow | `jukebox-host` | `corp-ntp` | NTP (UDP 123) | time (TPM, TLS, work hours) |
| 5 | Block | `jukebox-zone` | `internal-nets` | any | no lateral movement |
| 6 | Allow | `jukebox-host` | outside zone | HTTPS (TCP 443) | YouTube/Google, Microsoft Graph + login, Workflows, Nix caches, GitHub, Docker Hub |
| 7 | Block | `jukebox-zone` | any | any | everything else, incl. QUIC (UDP 443) — clients fall back to TCP |

Nothing inbound from outside: **no NAT/port-forward to the jukebox**. Outbound only needs the existing dynamic PAT on the outside interface — check that `jukebox-host` (or the VLAN subnet) is covered by it under **Devices → NAT**.

Then **Deploy → Deployment** → select the FTD → **Deploy**.

### 1.4 Tightening (after a week)

Rule 6 allows any HTTPS destination. Once the jukebox has run for a week, review **Analysis → Connections → Events** filtered on `jukebox-host`, and replace the destination of rule 6 with URL/SNI conditions for the domains actually used (YouTube/googlevideo, Microsoft login/Graph/Workflows host, cache.nixos.org, GitHub, Docker Hub, lyrics/metadata providers). Expect breakage when a provider adds a domain — check the block events first.

### 1.5 Verify

- From a staff host: `nmap -Pn -p 22,80,443,8095 <jukebox-ip>` → only 443 open.
- From the admin segment: 22 and 443 open.

### 1.6 DNS name and Cloudflare token

The web UI is served by Caddy over HTTPS with a Let's Encrypt certificate obtained via DNS-01 on Cloudflare — no inbound port, and personal phones trust it.

1. **Name:** pick `jukebox.<company domain>`. It will appear in public Certificate Transparency logs — no office or location in the name.
2. **Internal DNS:** A record `jukebox.<company domain>` → the reserved IP, on the corporate resolvers staff devices use. No public A record is needed.
3. **Cloudflare API token:** dashboard → **My Profile → API Tokens → Create Token** → template **Edit zone DNS**:
   - Permissions: **Zone → DNS → Edit** (nothing else);
   - Zone Resources: **Include → Specific zone →** the company zone only;
   - Client IP Address Filtering: **Is in →** the office's public egress IP;
   - TTL: end date ≤ 12 months (calendar reminder to rotate).
   This token can rewrite every record in the zone — treat it like a domain admin password ([security.md §4](security.md#4-secrets)).
4. `office.nix`: set `fqdn`, `acmeEmail` (IT mailbox for Let's Encrypt notices), `adminNets` (admin segment CIDRs — the only sources allowed to reach `/mcp/*`).
5. The token goes into sops in §6.
- From the jukebox (after §6): `curl -sI https://cache.nixos.org` succeeds; `curl -m5 http://<any internal host>` times out.

## 2. Prepare the private repo

In `jukebox-private/office.nix` set `timeZone` (IANA name, e.g. `America/Edmonton` — not a Windows name), `adminKeys`, `workDays`. Leave `speakerMac = null` and `bridge.enable = false` for now.

In `.sops.yaml` replace `age1REPLACE_ADMIN` with your admin age public key. The host key is added in §6.

## 3. Firmware

1. Update the firmware to the latest release first — a later update changes Secure Boot state and forces a TPM re-enrollment (see Troubleshooting).
2. Set a supervisor/admin password.
3. Security: TPM enabled; Secure Boot **off** for now.
4. Power: "After Power Loss" → Power On, so the box comes back after an outage. ⚠
5. Boot from the USB stick.

## 4. Installer session

On the Tiny (installer console):

```sh
passwd                 # temporary password for the nixos user, enables SSH login
ip -br a               # note the IP
ip link                # note the NIC MAC for the DHCP reservation (§1.1)
```

From the workstation copy both repos over and log in:

```sh
scp -r ~/src/jukebox ~/src/jukebox-private nixos@<installer-ip>:
ssh nixos@<installer-ip>
```

All remaining installer commands run in that SSH session. Flakes may not be enabled on the ISO, so enable them for the session:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
```

## 5. Hardware report and partitioning

```sh
sudo nix-shell -p nixos-facter --run nixos-facter > ~/jukebox-private/facter.json
```

`facter.json` contains MACs and serial numbers, which is why it lives in the private repo.

Point the public flake at the local private copy (this edits `flake.lock` on the installer only — never commit it):

```sh
cd ~/jukebox
nix flake lock --override-input private path:/home/nixos/jukebox-private
```

Partition, encrypt and mount. disko asks for the LUKS passphrase — this is the **recovery passphrase**; store it offline (password manager / sealed envelope):

```sh
sudo -E nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake .#jukebox
```

## 6. Secure Boot keys, SSH host key, secrets

Secure Boot signing keys (lanzaboote signs during `nixos-install`, so they must exist before it):

```sh
sudo nix-shell -p sbctl --run "sbctl create-keys"
sudo mkdir -p /mnt/var/lib && sudo cp -a /var/lib/sbctl /mnt/var/lib/
```

SSH host key — also the host's sops identity:

```sh
sudo mkdir -p /mnt/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
nix-shell -p ssh-to-age --run "ssh-to-age < /mnt/etc/ssh/ssh_host_ed25519_key.pub"
```

On the **workstation**, in `jukebox-private`:

1. Put the printed `age1…` recipient into `.sops.yaml` in place of `age1REPLACE_HOST`.
2. Create the secrets file:
   ```sh
   mkpasswd -m yescrypt            # admin sudo password → hash
   sops secrets/jukebox.yaml
   ```
   ```yaml
   admin-password: <yescrypt hash>
   cloudflare-dns-env: CLOUDFLARE_DNS_API_TOKEN=<token from §1.6>
   ```
   Both keys must exist before install — sops-nix fails activation on a missing key.
3. Copy `facter.json` back from the installer, commit and push:
   ```sh
   scp nixos@<installer-ip>:jukebox-private/facter.json .
   git add -A && git commit -m "feat: jukebox host key, admin password, hardware report" && git push
   ```
4. Re-sync the private repo to the installer:
   ```sh
   scp -r ~/src/jukebox-private nixos@<installer-ip>:
   ```

## 7. Install

**Caddy plugin hash (once):** `modules/caddy.nix` ships `hash = lib.fakeHash` for the Cloudflare plugin build. Build once on the workstation, take the `got: sha256-…` value from the hash-mismatch error, put it into `modules/caddy.nix`, commit:

```sh
nix build .#nixosConfigurations.jukebox.config.services.caddy.package --override-input private path:../jukebox-private
```

Back on the installer (re-copy the public repo if you just changed it):

```sh
cd ~/jukebox
nix flake lock --override-input private path:/home/nixos/jukebox-private
sudo -E nixos-install --flake .#jukebox --no-root-passwd
sudo reboot
```

Remove the USB stick. The first boot asks for the LUKS recovery passphrase on the console — TPM is not enrolled yet.

## 8. First boot checks

From the workstation:

```sh
ssh admin@jukebox
systemctl --failed
sudo sbctl verify          # lanzaboote images signed; kernel-* files unsigned is expected
```

Then pin the real private input on the workstation, in `jukebox`:

```sh
nix flake update private
git commit -am "chore: lock private input"
```

From here on the host is managed only by remote deploys (see [Deploy](#deploy)).

## 9. Secure Boot

1. Reboot into firmware: Security → Secure Boot → **Enabled**, then **Reset to Setup Mode**. Do not use "Clear All Secure Boot Keys" (drops the dbx).
2. Boot (recovery passphrase again), then:
   ```sh
   sudo sbctl enroll-keys --microsoft
   sudo reboot
   ```
3. Verify:
   ```sh
   bootctl status             # Secure Boot: enabled (user)
   ```
4. Firmware: disable USB boot, boot order = internal NVMe only.

## 10. TPM2 unlock

Bind the LUKS volume to the TPM with PCR 7 (Secure Boot state), and add a recovery key next to the passphrase:

```sh
LUKS=/dev/disk/by-partlabel/disk-main-luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 $LUKS
sudo systemd-cryptenroll --recovery-key $LUKS     # prints a key; store it offline with the passphrase
sudo reboot
```

The box should now boot unattended. Verify the negative case once: with Secure Boot disabled in firmware, boot must stop at the passphrase prompt. Re-enable Secure Boot afterwards.

## 11. Bluetooth speaker

Put the speaker into pairing mode, then on the host:

```sh
bluetoothctl
  power on
  pairable on
  scan on
  pair <MAC>
  trust <MAC>
  connect <MAC>
  scan off
  quit
```

Set `speakerMac = "<MAC>"` (upper case) in `jukebox-private/office.nix`, push, `nix flake update private`, deploy. `bt-reconnect.timer` then reconnects every minute; pairable/discoverable fall back to off after 180 s.

## 12. Music Assistant

Check the certificate first: `journalctl -u caddy` shows `certificate obtained successfully` for the fqdn. Then open `https://<fqdn>` from the admin segment.

1. Create the admin account (store the password in the team password manager).
2. Settings → disable **Remote Access**.
3. Settings → Core → Webserver (advanced toggle on): **Internal URL** = `https://<fqdn>` (Party QR codes and links use it), **Bind to IP/Interface** = `127.0.0.1`. Restart MA when asked; the UI stays reachable through Caddy.
4. Music sources → **YouTube Music**: username = the dedicated Google account, Login Cookie per the [MA guide](https://www.music-assistant.io/music-providers/youtube-music), PO Token server `http://127.0.0.1:4416`.
5. Plugins → **Party**: Venue mode, player = Jukebox. Set add/boost/skip token limits and refill rates explicitly ([security.md §8.2](security.md#8-music-assistant)); keep Skip off unless decided otherwise.
6. Plugins → **Music Quiz**: Venue mode, player = Jukebox.
7. Plugins → **FastMCP Server** (only if MCP is used): keep "Require authentication" and "Confirm destructive operations" on; enable only query, control and queue permissions ([§8.6](security.md#8-music-assistant)).
8. **Kiosk:** plug the keyboard into the Tiny, log in to MA in the kiosk browser, open the Party dashboard full-screen, unplug the keyboard.

Play a track during work hours and confirm it comes out of the speaker.

## 13. Microsoft 365: Teams bridge (optional)

Commands in the channel: a bare YouTube Music / YouTube track link, `!dj play <song or link>`, `!dj skip` (vote), `!dj np`, `!dj stats` (last 7 days), `!dj stats optout|optin`, `!dj help`; admins also `!dj stop`. The bridge reads the channel through Graph with an app-only RSC permission and replies through a Workflows webhook — Graph has no app-only channel posting outside migration ([security.md §5](security.md#5-accounts)).

### 13.1 Team

1. Create a dedicated **private** team "Jukebox" with a single channel. RSC is granted per team, so the team boundary is what limits the bridge to that one channel.
2. Owners: you + the service account. Members: whoever may use the bot.
3. Channel description: state that the bot reads messages addressed to it and messages with YouTube Music / YouTube track links (posting such a link queues the track); that each request (who, what, when) and each played track is recorded for `retentionDays` (default 90); that weekly stats with the top requesters (name + count, no tracks) are posted in the channel; and that `!dj stats optout` hides you from that list ([§9.7–9.8](security.md#9-teams-bridge)).
4. IDs: channel `…` → **Get link to channel**. The link contains `groupId=<teamId>` and the channel ID `19:…@thread.tacv2` (URL-decode it).

### 13.2 Entra app registration

Entra admin center → **App registrations → New registration**:

1. Name `jukebox-bridge`, **single tenant**, no redirect URI.
2. **API permissions:** remove the default `User.Read`; add nothing. Channel access comes only from RSC in the Teams app (§13.3) — never grant `ChannelMessage.Read.All` or other tenant-wide Graph permissions.
3. **Certificates & secrets → Certificates → Upload** — certificate only, no client secret:
   ```sh
   openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=jukebox-bridge" -keyout bridge.key -out bridge.crt
   openssl x509 -in bridge.crt -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :
   ```
   Upload `bridge.crt`; the second command prints the thumbprint (must match the one Entra shows).
4. Note **Application (client) ID** and **Directory (tenant) ID** from Overview.
5. Calendar reminder 2 weeks before the certificate expires (rotation per [§4](security.md#4-secrets)).

### 13.3 Teams app with RSC

Teams **Developer Portal** → Apps → New app:

1. Basic information: name, descriptions (say what data the bot reads), developer info.
2. **Single sign-on / App registration:** bind it to the `jukebox-bridge` client ID (this fills `webApplicationInfo`). ⚠
3. **Permissions → Team permissions → Application:** `ChannelMessage.Read.Group` only.
4. Download the app package (zip).

### 13.4 Teams admin center

1. **Teams apps → Manage apps → Org-wide app settings:** custom apps must be allowed for the organization.
2. **Teams apps → Manage apps → Upload new app:** upload the package to the org catalog (admins can always upload; users don't need "Upload custom apps").
3. Restrict who can add it: **Teams apps → Permission policies** — allow the app only for you/the service account; everyone else keeps it blocked. ⚠ (some tenants use app-centric management instead: app → **Users and groups**.)
4. Install the app into the Jukebox team (as team owner). The consent dialog lists `ChannelMessage.Read.Group` — this is the only grant the bridge gets.
5. Verify: **Teams apps → Manage apps** → the app → **Permissions** tab shows the RSC permission.

### 13.5 Workflows webhook

Signed in as the **service account**, in the Jukebox channel → **Workflows** → template **"Post to a channel when a webhook request is received"** → target the Jukebox channel → copy the URL.

- The flow is owned by the service account, not a person — it stops if its owner is disabled ([§5.4](security.md#5-accounts)).
- The bridge posts without Entra auth, so the trigger must accept anonymous callers; the URL itself is the secret. ⚠ check the trigger's "who can trigger" setting.

### 13.6 Secrets and config

1. MA web UI → profile → **Long-lived access tokens** → create `teams-bridge`.
2. `sops secrets/jukebox.yaml` in the private repo, then delete `bridge.key` / `bridge.crt` locally:
   ```yaml
   bridge:
     graph-key: <contents of bridge.key>
     graph-thumbprint: <thumbprint>
     ma-token: <token>
     workflows-url: <url>
   ```
3. `office.nix`:
   ```nix
   bridge = {
     enable = true;
     tenantId = "<directory id>";
     clientId = "<application id>";
     teamId = "<groupId>";
     channelId = "19:...@thread.tacv2";
     adminIds = ["<your Entra object id>"];
   };
   ```
4. Push, `nix flake update private`, deploy.
5. Post `!dj help` in the channel — the reply arrives via Workflows within a few seconds. `journalctl -u teams-bridge` shows `author=<id> command=help`.
6. Reports: `!dj stats` in the channel; full per-person log at `https://<fqdn>/stats` (admin nets only, `?days=1|7|30|90`); weekly summary posted automatically on the last work day at the end of work hours (`systemctl list-timers teams-bridge-report`). Retention: `bridge.retentionDays` in `office.nix`.

## 14. MCP clients (optional)

From the admin segment (Caddy answers 403 on `/mcp/*` for any other source):

MA → Plugins → FastMCP Server → Open Connect Wizard → pick the client. It mints a per-client token and prints a config block with the URL `https://<fqdn>/mcp/v1` — use it as is.

## 15. Acceptance

Run the checklist in [security.md §14](security.md#14-acceptance-checklist), including the FTD checks from §1.5. Re-audit `kernel-modules.disable` in `modules/hardening.nix` against `facter.json` (Thunderbolt and Intel ME vary by Tiny model).

## Deploy

All later changes, from the admin segment:

```sh
nixos-rebuild switch --flake .#jukebox --target-host admin@jukebox --ask-sudo-password
```

After changing the private repo: push it, then `nix flake update private` here first.

## Troubleshooting

| Symptom | Check |
|---|---|
| Boot stops at the passphrase prompt after a firmware update | PCR 7 changed. Unlock with the recovery passphrase, then re-bind: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-main-luks` |
| No certificate / Caddy fails to start | `journalctl -u caddy`. `403` from Cloudflare → token scope or client IP filter. Propagation check timing out → corporate DNS is split-horizon for the zone; add `propagation_timeout -1` and `propagation_delay 60s` inside the `tls` block |
| Install/deploy can't fetch from GitHub or caches | FTD rule 6 / PAT; FMC **Analysis → Connections → Events** for `jukebox-host` |
| Phones can't open the Party QR link | Phone not in `jukebox-staff-nets` (guest Wi-Fi?) — FTD rule 1 |
| No sound | Outside `workHours` this is expected. Otherwise: `bluetoothctl info <MAC>`, `journalctl -u bt-reconnect`, `sudo journalctl _SYSTEMD_USER_UNIT=squeezelite.service` |
| Speaker never connects | `journalctl -u bluetooth` — bluetoothd runs with extra sandboxing (`modules/hardening.nix`) |
| YouTube Music stops, `401` or PO Token errors in MA log | Cookie expired: redo §12.4. Check `systemctl status podman-bgutil-pot` |
| Chromium, MA or the PO Token container crash on start | Suspect nix-mineral `proc-mem-force` (left at default) |
| Bridge: `401/403` from Graph | RSC app not installed in the team, certificate expired, or thumbprint mismatch |
| Bridge: commands seen in the log, no reply in the channel | Workflows flow disabled/owner disabled, or URL rotated without updating sops |
| Deploy fails with "Failed to run activate script" | Compare `readlink -f /nix/var/nix/profiles/system` with `/run/current-system` |
