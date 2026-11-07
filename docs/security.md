# Jukebox — Security Requirements

Binding for every change in this repo. MUST / MUST NOT are absolute; any deviation is recorded under "Exceptions" with a reason and a date.
Items marked ⚠ are binding, but the exact mechanism has not yet been checked against upstream docs; check before implementing.

## 1. Threat model

**Assets**

| Asset | Impact if compromised |
|---|---|
| Corporate network | Tiny used as a foothold for lateral movement |
| Google account cookie (YT Music) | Full access to the Google account |
| Entra app credentials (Graph) | Reading the jukebox team's channel messages |
| Workflows webhook URL | Posting arbitrary content to the channel |
| Cloudflare DNS API token | Editing DNS records of the company zone — redirecting company hostnames, issuing certificates for them |
| Teams channel messages | Leak of employee conversations |
| Request/play log | Per-person record of employees' music requests |
| The device itself | Disk theft with secrets on it |

**Adversaries:** any user on the office network (incl. guest Wi-Fi), any member of the Teams team, someone with physical access, a compromised dependency (supply chain).

**Out of scope:** compromise of the M365 tenant, Google, or nixpkgs upstream as a whole.

## 2. Network

1. The Tiny MUST sit in a dedicated VLAN.
2. FTD ACL, inbound to the jukebox VLAN:
   - from staff segments — TCP 443 (Caddy, TLS) only;
   - from the admin segment — TCP 443 and SSH;
   - from the internet — nothing. NAT/port forwarding from outside MUST NOT exist.
3. FTD ACL, outbound from the jukebox VLAN:
   - TCP 443 to the internet (YouTube/Google, Microsoft Graph, Workflows endpoint, Nix caches);
   - DNS — corporate resolvers only; NTP — corporate or a chosen pool;
   - any other internal segment — denied.
4. Host firewall: default deny inbound; only the ports from §2.2 are open.
5. Internal links (MA ↔ squeezelite, MA ↔ PO Token server, bridge ↔ MA API) MUST bind to loopback where the service supports it; otherwise they are closed by the host firewall. ⚠ check MA and squeezelite bind options.
6. `services.music-assistant.openFirewall` MUST NOT be used (it opens high-port ranges for AirPlay/Spotify Connect). Ports are opened one by one.
7. No mDNS/UPnP/SSDP announcements leave the VLAN.
8. All client traffic is TLS: Caddy terminates HTTPS on 443 with a publicly trusted Let's Encrypt certificate (DNS-01, no inbound port) and proxies to MA on loopback. MA's webserver binds `127.0.0.1`; plain HTTP is never exposed. Port 80 and HTTP/3 stay closed. The hostname appears in public Certificate Transparency logs; it MUST NOT reveal more than "jukebox" (no office/location names).

## 3. Administrative access

1. SSH: keys only, no root login, password authentication disabled.
2. Remote access is SSH from the admin segment only, permitted by the FTD ACL (§2.2). Overlay VPNs on the host (tailscale, wireguard, etc.) and connections to the administrator's personal infrastructure MUST NOT be used.
3. Kiosk user: no SSH login, no sudo, not in `wheel`.
4. The MA admin UI MUST require authentication; guests only reach the Party/Quiz guest view. ⚠ check how MA separates admin and guest access and whether login can be enforced. If it cannot — admin UI is bound to loopback and reached via SSH tunnel.

## 4. Secrets

1. All secrets go through sops-nix (age) only. Secrets MUST NOT appear in the Nix store, in git in plaintext, in logs, in unit environment variables, or on command lines.
2. The host age key is derived from the SSH host key.
3. Secrets and office-specific values (time zone, admin keys, speaker MAC, Entra/Teams IDs) live only in the private `jukebox-private` repo. This repo is public: it holds code, `docs/private-example.nix` with placeholder values, and nothing that identifies the office.
4. Secret inventory and rotation:

| Secret | Rotation |
|---|---|
| YT Music cookie | On expiry (401 in MA logs) and on any suspected leak |
| Entra app credential | Certificate, not client secret; lifetime ≤ 12 months |
| Workflows webhook URL | Recreate the flow on leak |
| MA admin password | On administrator change |
| Admin sudo password (yescrypt hash, `admin-password`) | On administrator change |
| MA long-lived token for the bridge (`bridge/ma-token`) | On leak; revoke in MA profile settings |
| Cloudflare DNS token (`cloudflare-dns-env`) | Scope: Zone → DNS → Edit on the company zone only, client IP filter = office egress IP, expiry ≤ 12 months; rotate on expiry or leak |

5. Secrets reach services via `LoadCredential=` or a 0400 file owned by the service user.

## 5. Accounts

1. Google: a dedicated account for the jukebox only; 2FA on; recovery to a corporate mailbox. Personal accounts MUST NOT be used.
2. Teams scope: a dedicated team ("Jukebox") containing only the jukebox channel. RSC permissions are granted per team, not per channel, so a dedicated team is what limits the blast radius to that one channel.
3. Entra app — least privilege:
   - read: `ChannelMessage.Read.Group` (application, resource-specific consent), installed only in the jukebox team. This is the documented least-privileged application permission for listing channel messages ([List channel messages](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0)). Tenant-wide `ChannelMessage.Read.All` MUST NOT be granted.
   - post: Graph has no app-only permission for posting to a channel outside migration scenarios (application = `Teamwork.Migrate.All` only, "Application permissions are only supported for migration" — [Send chatMessage in a channel](https://learn.microsoft.com/en-us/graph/api/channel-post-messages?view=graph-rest-1.0)). Bot replies therefore go through a Workflows webhook. `Teamwork.Migrate.All`, `Group.ReadWrite.All`, and delegated `ChannelMessage.Send` on a service account MUST NOT be used.
4. The Workflows flow is owned by a dedicated service account, not a personal one. ⚠ check flow ownership and what happens to the flow when the owner account is disabled.
5. Bot admins are identified by Entra object ID, never by display name.

## 6. Host

1. Disk: single NVMe, LUKS2, TPM2 unlock bound to Secure Boot state (PCR 7). ⚠ check the lanzaboote + `systemd-cryptenroll` setup on this Tiny model.
2. BIOS/UEFI: admin password set, boot from internal disk only, Secure Boot on.
3. Physical: Kensington lock, not in a freely accessible spot, USB ports physically hard to reach where possible.
4. Only what is needed is installed: no compilers, dev shells, or debugging tools in the system profile.
5. Updates: `flake.lock` pinned; nixpkgs bumped at least every 2 weeks and out of band on CVEs in used components; the MA changelog is read before every bump.
6. journald persistent, size-capped.
7. Kernel/sysctl/mount hardening via nix-mineral (`modules/hardening.nix`). Every override of a nix-mineral default carries a one-line reason; `kernel-modules.disable` categories are audited against the host's `facter.json`, not left at blanket defaults.

## 7. Services

Every systemd unit ships hardened in the same change that adds it. Baseline:

- `DynamicUser=` or a dedicated system user;
- `ProtectSystem=strict` with targeted `ReadWritePaths=`/`StateDirectory=`;
- `ProtectHome=`, `PrivateTmp=`, `PrivateDevices=` (except audio/BT units that need device access);
- `NoNewPrivileges=`, empty `CapabilityBoundingSet=`;
- `RestrictAddressFamilies=` — minimal set;
- `SystemCallFilter=` — a single `~`-prefixed string plus `SystemCallErrorNumber=EPERM`;
- `SocketBindAllow=`/`SocketBindDeny=` — own ports only;
- `MemoryDenyWriteExecute=` — on everywhere except JIT (kiosk browser).

Every directive left off carries a one-line comment with the reason.

**OCI containers** (PO Token server): image pinned by digest, `--cap-drop=all`, `no-new-privileges`, `--userns=auto`, `--read-only`, port bound to `127.0.0.1` only, no `--privileged`, no host socket mounts.

## 8. Music Assistant

1. Only providers in use are enabled. These MUST NOT be enabled without a recorded decision: `openai_compatible`, `openai_tts`, `ai_radio` (send data externally), `airplay_receiver`, `spotify_connect`, `sendspin_source`, `ariacast_receiver`, `vban_receiver` (accept external audio), `hass`, `hass_players`.
2. Party: add-to-queue, boost and skip token limits and refill rates are set explicitly, never left at defaults without review. Party has no track-length limit; that is enforced by the bridge (§9).
3. The guest URL is shared only inside the company (Teams channel, QR codes in the office); never posted publicly.
4. Playback is possible only within `jukebox.workHours` (squeezelite is stopped outside it, `modules/work-hours.nix`). A system-level volume ceiling is still required — not implemented yet.
5. MA Remote Access is disabled — Party supports it, and it would expose the guest view outside the office network.
6. MCP (`fastmcp_server`, decision 2026-11-07: admin control from an AI client):
   - "Require authentication" stays on; one Connect Wizard token per client, revoked when the client is retired.
   - Enabled permissions: query, playback control, queue management. Edit/Delete permissions and the Debug and Config namespaces stay off.
   - "Confirm destructive operations" stays on.
   - Reached at `https://<fqdn>/mcp/v1` over TLS; Caddy answers 403 on `/mcp/*` for any source outside `jukebox.adminNets`.
   - Library, queue and player names reach the AI vendor through the client; nothing beyond that is exposed.

## 9. Teams bridge

1. Only messages addressed to the bot (prefix/mention) are processed. Other messages are neither stored nor logged.
2. Messages posted by applications (including the bot's own Workflows posts) are ignored.
3. Journal: timestamp, author Entra object ID, command name. Never the text of other messages.
4. Commands are allowlisted; arguments are validated; spawning a shell/subprocess with user input MUST NOT happen.
5. Links are accepted only from `bridge.allowedDomains`, an enum of hosts the bridge has a parser for (`music.youtube.com`, `youtube.com`, `youtu.be`). Only plain `https` single-track links pass; the track ID is checked against Music Assistant, and unavailable tracks are refused. A message whose only links are non-music is ignored and not logged.
6. Per-user and global rate limits; admin commands (stop, volume, ban) restricted to the object ID allowlist.
7. The channel description tells employees that the bot reads messages addressed to it and what is logged.
8. Request/play log (decision 2026-11-07: full per-person log, for reports):
   - Stored in SQLite under the bridge's state directory (`/var/lib/private/teams-bridge`, DynamicUser, 0700, on the LUKS disk).
   - Requests (Teams only): time, author object ID and display name, command, its argument (search text), the bot's reply, success flag. Only commands addressed to the bot — §9.1 still holds.
   - Plays: time, track, artists, duration, source (`teams` with requester / `party` anonymous / `other`). Party guests are never identified.
   - Retention: `jukebox.bridge.retentionDays` (default 90), pruned at start, daily and on each weekly report.
   - Access: the full log only on `https://<fqdn>/stats`, which Caddy restricts to `jukebox.adminNets`. `!dj stats` and the weekly channel post show aggregates and the top-10 requesters by display name and request count — never which tracks a person requested.
   - Opt-out: `!dj stats optout` hides the author from the public top DJs (`optin` reverts); their requests stay in the IT log. The opt-out list is a preference, not log data, and is not pruned by retention.
   - The channel description MUST say this: what is recorded, for how long, and that the top requesters are shown in the channel. Whether this meets the company's privacy obligations to employees (Alberta PIPA) is a company decision, not a technical one.

## 10. Kiosk

1. `cage` plus a browser in kiosk mode under a dedicated user.
2. Browser: URL allowlist (local MA pages only), no DevTools, no downloads, no `file://`, no extensions, no password saving. ⚠ check the chosen browser's enterprise policies.
3. Non-persistent browser profile (tmpfs).
4. No keyboard/mouse attached to the kiosk in normal operation.

## 11. Bluetooth

1. Exactly one device — the speaker — is paired and trusted (by MAC).
2. After pairing, `discoverable`/`pairable` are off.
3. HID profiles (BT keyboards/mice) are disabled to prevent keystroke injection. ⚠ check the BlueZ `main.conf`/`input.conf` keys.

## 12. Supply chain

1. All dependencies come from nixpkgs/flake inputs with a pinned `flake.lock`. `pip install` or downloading code at runtime MUST NOT happen.
2. Containers are pinned by digest; the PO Token server version is the one the current MA requires.
3. Every new flake input or container states its source and reason in the commit message.

## 13. Incident response

**Kill switch:** block the jukebox VLAN on the FTD; locally — `systemctl stop music-assistant teams-bridge`.

| Event | Actions |
|---|---|
| Cookie leak / suspicion | Google: sign out all sessions, change password; new cookie into sops |
| Graph credential leak | Revoke the certificate in Entra; issue a new one |
| Webhook URL leak | Delete and recreate the flow |
| Cloudflare token leak | Roll/delete the token in Cloudflare; review the zone's audit log and DNS records for changes; new token into sops |
| Host compromise | Isolate the VLAN; collect the journal; reinstall from scratch; rotate every secret in §4 |
| Device theft | Rotate every secret in §4; remove its SSH host key from known_hosts and its FTD rules |

## 14. Acceptance checklist

Before going live and after any major change:

- [ ] `nmap` from a staff VLAN: only TCP 443 is open (8095, 80, 22 closed)
- [ ] A personal phone opens `https://<fqdn>` without a certificate warning; Party QR links use `https://<fqdn>`
- [ ] `/mcp/v1` returns 403 from a staff VLAN
- [ ] No internal segment is reachable from the jukebox VLAN
- [ ] MA admin UI is unreachable without login
- [ ] `systemd-analyze security <unit>` for every unit; deviations justified
- [ ] `git grep` finds no secrets in the repo; the Nix store contains no secrets
- [ ] TPM unlock works; with Secure Boot off it does not
- [ ] BT: the host is not discoverable; pairing a new device fails
- [ ] Bridge: a message not addressed to the bot does not appear in logs or in the request log
- [ ] `/stats` returns 403 from a staff VLAN
- [ ] Entries older than `retentionDays` are gone after the weekly report
- [ ] Party: limits hold when tested from two different phones

## Exceptions

| Item | Reason | Date | Review |
|---|---|---|---|
| §4.1 | YT Music cookie and MA account credentials live in MA's own state (`/var/lib/private/music-assistant`), not sops: MA accepts provider credentials only through its UI. Mitigated by LUKS, DynamicUser, 0700 state dir. | 2026-11-07 | When MA supports file-based provider config |
| §7 | `cage-tty1` is not sandboxed: it is a PAM login session, sandboxing it would sandbox the whole kiosk session. Covered by browser policies (§10). | 2026-11-07 | — |
| §7 | `music-assistant`: no `SocketBindAllow`, `MemoryDenyWriteExecute` off (upstream: deno JIT for ytmusic). | 2026-11-07 | On MA upgrades |
| §10.3 | Chromium profile is persistent: the Party dashboard needs a logged-in MA session that must survive reboots. | 2026-11-07 | — |
