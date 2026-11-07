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
  # Hardware report (MACs, serials) lives in the private repo, see docs/installation.md §4.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists "${private}/facter.json") "${private}/facter.json";

  jukebox = {
    inherit (office) timeZone adminKeys speakerMac bridge fqdn acmeEmail adminNets;
    workHours.days = office.workDays;
  };

  system.stateVersion = "26.05";
}
