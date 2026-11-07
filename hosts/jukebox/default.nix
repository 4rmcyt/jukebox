{
  lib,
  private,
  ...
}: let
  office = private.lib.office;
in {
  imports = [../../modules];

  networking.hostName = "jukebox";
  nixpkgs.hostPlatform = "x86_64-linux";
  # Generated on the Tiny with nixos-facter, see README.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;

  jukebox = {
    inherit (office) timeZone adminKeys speakerMac bridge;
    workHours.days = office.workDays;
  };

  system.stateVersion = "26.05";
}
