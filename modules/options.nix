{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.jukebox;
in {
  options.jukebox = {
    timeZone = mkOption {
      type = types.str;
      description = "Office time zone.";
    };
    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "The only account allowed to log in over SSH.";
    };
    adminKeys = mkOption {
      type = types.listOf types.str;
      description = "SSH public keys for the admin account.";
    };
    kioskUser = mkOption {
      type = types.str;
      default = "kiosk";
      description = "Account running cage, the browser, PipeWire and squeezelite.";
    };
    speakerMac = mkOption {
      type = types.nullOr (types.strMatching "([0-9A-F]{2}:){5}[0-9A-F]{2}");
      default = null;
      description = "MAC of the paired Bluetooth speaker (upper case).";
    };
    workHours = {
      days = mkOption {
        type = types.listOf (types.enum ["Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"]);
        description = "Days playback is allowed.";
      };
      start = mkOption {
        type = types.strMatching "[0-2][0-9]:[0-5][0-9]";
        default = "07:00";
        description = "Playback allowed from (local time).";
      };
      end = mkOption {
        type = types.strMatching "[0-2][0-9]:[0-5][0-9]";
        default = "17:00";
        description = "Playback stops at (local time).";
      };
    };
  };

  config.assertions = [
    {
      assertion = cfg.adminKeys != [];
      message = "jukebox.adminKeys is empty: the host would be unreachable over SSH.";
    }
  ];
}
