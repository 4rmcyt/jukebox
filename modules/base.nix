{config, ...}: let
  cfg = config.jukebox;
in {
  time.timeZone = cfg.timeZone;

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      # Remote deploys copy unsigned store paths.
      trusted-users = ["@wheel"];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  users.mutableUsers = false;
  users.users.${cfg.adminUser} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = cfg.adminKeys;
    hashedPasswordFile = config.sops.secrets.admin-password.path;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [cfg.adminUser];
    };
  };

  networking.firewall.enable = true;

  services.journald.settings.Journal = {
    Storage = "persistent";
    SystemMaxUse = "500M";
  };

  zramSwap.enable = true;
}
