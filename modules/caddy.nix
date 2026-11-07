{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.jukebox;
in {
  # Env file: CLOUDFLARE_DNS_API_TOKEN=<token scoped to Zone.DNS:Edit on one zone>.
  sops.secrets.cloudflare-dns-env = {};

  services.caddy = {
    enable = true;
    # Replace with the hash from the first build's mismatch error.
    package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
      hash = lib.fakeHash;
    };
    email = cfg.acmeEmail;
    environmentFile = config.sops.secrets.cloudflare-dns-env.path;
    # Port 80 stays closed (QR codes and links are https); no HTTP/3, FTD drops QUIC.
    globalConfig = ''
      auto_https disable_redirects
      servers {
        protocols h1 h2
      }
    '';
    virtualHosts.${cfg.fqdn}.extraConfig = ''
      tls {
        dns cloudflare {env.CLOUDFLARE_DNS_API_TOKEN}
      }

      @mcpForeign {
        path /mcp/*
        not remote_ip ${lib.concatStringsSep " " cfg.adminNets}
      }
      respond @mcpForeign 403

      reverse_proxy 127.0.0.1:8095
    '';
  };

  networking.firewall.allowedTCPPorts = [443];

  # Upstream module sets NoNewPrivileges, PrivateDevices, ProtectHome; the package unit adds CAP_NET_ADMIN for QUIC buffers, unused here.
  systemd.services.caddy.serviceConfig = {
    AmbientCapabilities = lib.mkForce ["CAP_NET_BIND_SERVICE"];
    CapabilityBoundingSet = lib.mkForce ["CAP_NET_BIND_SERVICE"];
    ProtectSystem = lib.mkForce "strict";
    PrivateTmp = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
    # 443 for clients, 2019 for the admin API used by `caddy reload`.
    SocketBindAllow = ["tcp:443" "tcp:2019"];
    SocketBindDeny = "any";
    SystemCallArchitectures = "native";
    SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @raw-io @reboot @swap";
    SystemCallErrorNumber = "EPERM";
    UMask = "0077";
    # PrivateUsers omitted: would drop CAP_NET_BIND_SERVICE for :443.
  };
}
