{
  lib,
  pkgs,
  ...
}: {
  boot = {
    # lanzaboote replaces the systemd-boot module.
    loader.systemd-boot.enable = lib.mkForce false;
    loader.efi.canTouchEfiVariables = true;
    lanzaboote = {
      enable = true;
      # Keys are created in the installer and copied in, see README.
      pkiBundle = "/var/lib/sbctl";
    };
    initrd.systemd = {
      enable = true;
      tpm2.enable = true;
    };
  };

  environment.systemPackages = [pkgs.sbctl];
}
