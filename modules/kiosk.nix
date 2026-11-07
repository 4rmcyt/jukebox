{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.jukebox;
  maUrl = "http://127.0.0.1:8095";
  browser = pkgs.writeShellScript "kiosk-browser" ''
    exec ${lib.getExe pkgs.chromium} \
      --kiosk \
      --ozone-platform=wayland \
      --no-first-run \
      --noerrdialogs \
      ${maUrl}
  '';
in {
  users.users.${cfg.kioskUser} = {
    isNormalUser = true;
    description = "Jukebox kiosk";
    hashedPassword = "!";
  };

  # cage-tty1 is a PAM login session for the kiosk user; sandboxing it would sandbox the whole session.
  services.cage = {
    enable = true;
    user = cfg.kioskUser;
    program = browser;
  };

  # Policy names: chromium components/policy/test/data/pref_mapping/<Name>.json
  programs.chromium = {
    enable = true;
    extraOpts = {
      URLBlocklist = ["*" "file://*"];
      URLAllowlist = [maUrl];
      DeveloperToolsAvailability = 2;
      DownloadRestrictions = 3;
      PasswordManagerEnabled = false;
      BrowserSignin = 0;
      ExtensionInstallBlocklist = ["*"];
      AllowFileSelectionDialogs = false;
      TranslateEnabled = false;
    };
  };
}
