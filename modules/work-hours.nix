{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.jukebox.workHours;
  kiosk = config.jukebox.kioskUser;
  hhmm = t: lib.replaceStrings [":"] [""] t;
  inWorkHours = pkgs.writeShellScript "jukebox-in-work-hours" ''
    day=$(LC_ALL=C ${pkgs.coreutils}/bin/date +%a)
    now=$(${pkgs.coreutils}/bin/date +%H%M)
    case " ${lib.concatStringsSep " " cfg.days} " in
      *" $day "*) ;;
      *) exit 1 ;;
    esac
    [ "$now" -ge ${hhmm cfg.start} ] && [ "$now" -lt ${hhmm cfg.end} ]
  '';
in {
  # Outside work hours squeezelite is down, so Music Assistant has no player to play to.
  systemd.user.services.squeezelite.serviceConfig.ExecCondition = inWorkHours;

  systemd.user.timers.jukebox-start = {
    wantedBy = ["timers.target"];
    unitConfig.ConditionUser = kiosk;
    timerConfig = {
      OnCalendar = "${lib.concatStringsSep "," cfg.days} ${cfg.start}";
      Unit = "squeezelite.service";
    };
  };

  systemd.user.timers.jukebox-stop = {
    wantedBy = ["timers.target"];
    unitConfig.ConditionUser = kiosk;
    timerConfig.OnCalendar = "*-*-* ${cfg.end}";
  };

  systemd.user.services.jukebox-stop = {
    description = "Stop playback at the end of work hours";
    unitConfig.ConditionUser = kiosk;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user stop squeezelite.service";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      RestrictAddressFamilies = ["AF_UNIX"];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictNamespaces = true;
      SystemCallArchitectures = "native";
    };
  };
}
