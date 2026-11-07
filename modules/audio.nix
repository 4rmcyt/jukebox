{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.jukebox;
  syscallDeny = "~@clock @cpu-emulation @debug @module @mount @obsolete @privileged @raw-io @reboot @swap";
in {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # No BT keyboards/mice: blocks keystroke injection (profiles/input: input + hog plugins).
    disabledPlugins = ["input" "hog"];
    settings.General = {
      DiscoverableTimeout = 180;
      # Upstream default 0 = pairable forever.
      PairableTimeout = 180;
    };
  };

  # Runs in the kiosk user's session; wireplumber seat-monitoring keeps BT on the active cage seat only.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;

  systemd.user.services.squeezelite = {
    description = "Squeezelite player for Music Assistant";
    wantedBy = ["default.target"];
    wants = ["pipewire-pulse.socket"];
    after = ["pipewire-pulse.socket"];
    unitConfig.ConditionUser = cfg.kioskUser;
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.squeezelite-pulse} -s 127.0.0.1 -n Jukebox";
      Restart = "always";
      RestartSec = 5;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
      SystemCallArchitectures = "native";
      SystemCallFilter = syscallDeny;
      SystemCallErrorNumber = "EPERM";
      # CapabilityBoundingSet/SocketBind* no-op in the user manager; RestrictRealtime off: pulse may ask rtkit for RT.
    };
  };

  systemd.services.bt-reconnect = lib.mkIf (cfg.speakerMac != null) {
    description = "Reconnect the Bluetooth speaker";
    requires = ["bluetooth.service"];
    after = ["bluetooth.service"];
    path = [pkgs.bluez pkgs.gnugrep];
    script = ''
      bluetoothctl info ${cfg.speakerMac} | grep -q "Connected: yes" \
        || bluetoothctl connect ${cfg.speakerMac} || true
    '';
    serviceConfig = {
      Type = "oneshot";
      # BlueZ D-Bus policy allows any user to send to org.bluez.
      DynamicUser = true;
      PrivateNetwork = true;
      IPAddressDeny = "any";
      RestrictAddressFamilies = ["AF_UNIX"];
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
      SystemCallArchitectures = "native";
      SystemCallFilter = syscallDeny;
      SystemCallErrorNumber = "EPERM";
      UMask = "0077";
    };
  };

  systemd.timers.bt-reconnect = lib.mkIf (cfg.speakerMac != null) {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };
}
