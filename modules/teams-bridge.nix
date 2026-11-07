{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.jukebox.bridge;
  secret = name: "${name}:${config.sops.secrets."bridge/${name}".path}";
  credentials = ["graph-key" "graph-thumbprint" "ma-token" "workflows-url"];
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
      type = types.listOf types.str;
      default = ["music.youtube.com" "youtube.com" "youtu.be"];
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
      };
      serviceConfig = {
        ExecStart = lib.getExe (pkgs.callPackage ../bridge/package.nix {});
        LoadCredential = map secret credentials;
        Restart = "on-failure";
        RestartSec = 10;

        DynamicUser = true;
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
    };
  };
}
