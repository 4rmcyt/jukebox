{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.jukebox.bridge;
  inherit (config.jukebox) workHours fqdn adminNets;
  package = pkgs.callPackage ../bridge/package.nix {};
  statsPort = 8096;
  secret = name: "${name}:${config.sops.secrets."bridge/${name}".path}";
  credentials = ["graph-key" "graph-thumbprint" "ma-token" "workflows-url"];

  hardening = {
    # Shared dynamic user: bridge and weekly report use the same state directory (request/play log).
    DynamicUser = true;
    User = "teams-bridge";
    StateDirectory = "teams-bridge";
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateUsers = true;
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
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    SocketBindDeny = "any";
    SystemCallArchitectures = "native";
    SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @privileged @raw-io @reboot @resources @swap";
    SystemCallErrorNumber = "EPERM";
    UMask = "0077";
    # IPAddressAllow omitted: Graph, login.microsoftonline.com and the Workflows endpoint sit on large, shifting ranges.
  };
in {
  options.jukebox.bridge = {
    enable = mkEnableOption "the Teams channel bridge";
    tenantId = mkOption {type = types.str;};
    clientId = mkOption {type = types.str;};
    teamId = mkOption {type = types.str;};
    channelId = mkOption {type = types.str;};
    adminIds = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Entra object IDs allowed to run admin commands.";
    };
    allowedDomains = mkOption {
      type = types.listOf (types.enum ["music.youtube.com" "youtube.com" "youtu.be"]);
      default = ["music.youtube.com" "youtube.com" "youtu.be"];
      description = "Link sources accepted as orders; each value needs a parser in bridge/jukebox_bridge/links.py.";
    };
    retentionDays = mkOption {
      type = types.ints.positive;
      default = 90;
      description = "Days the per-person request/play log is kept (docs/security.md §9).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs (map (n: "bridge/${n}") credentials) (_: {});

    systemd.services.teams-bridge = {
      description = "Teams channel to Music Assistant bridge";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "music-assistant.service"];
      environment = {
        JUKEBOX_TENANT_ID = cfg.tenantId;
        JUKEBOX_CLIENT_ID = cfg.clientId;
        JUKEBOX_TEAM_ID = cfg.teamId;
        JUKEBOX_CHANNEL_ID = cfg.channelId;
        JUKEBOX_ADMIN_IDS = lib.concatStringsSep "," cfg.adminIds;
        JUKEBOX_ALLOWED_DOMAINS = lib.concatStringsSep "," cfg.allowedDomains;
        JUKEBOX_STATS_PORT = toString statsPort;
        JUKEBOX_RETENTION_DAYS = toString cfg.retentionDays;
      };
      serviceConfig =
        hardening
        // {
          ExecStart = lib.getExe package;
          LoadCredential = map secret credentials;
          Restart = "on-failure";
          RestartSec = 10;
          SocketBindAllow = ["tcp:${toString statsPort}"];
        };
    };

    systemd.services.teams-bridge-report = {
      description = "Weekly jukebox report to the Teams channel";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      environment.JUKEBOX_RETENTION_DAYS = toString cfg.retentionDays;
      serviceConfig =
        hardening
        // {
          Type = "oneshot";
          ExecStart = "${lib.getExe package} report";
          LoadCredential = [(secret "workflows-url")];
        };
    };

    # Last work day of the week, at the end of work hours.
    systemd.timers.teams-bridge-report = {
      wantedBy = ["timers.target"];
      timerConfig.OnCalendar = "${lib.last workHours.days} ${workHours.end}";
    };

    # Per-person log: admin nets only, like /mcp/*.
    services.caddy.virtualHosts.${fqdn}.extraConfig = ''
      @statsForeign {
        path /stats*
        not remote_ip ${lib.concatStringsSep " " adminNets}
      }
      respond @statsForeign 403
      reverse_proxy /stats* 127.0.0.1:${toString statsPort}
    '';
  };
}
