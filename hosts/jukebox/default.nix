{lib, ...}: {
  imports = [../../modules];

  networking.hostName = "jukebox";
  nixpkgs.hostPlatform = "x86_64-linux";
  # Generated on the Tiny with nixos-facter, see README.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;

  jukebox = {
    timeZone = "UTC";
    adminKeys = [];
    speakerMac = null;
    workHours.days = ["Mon" "Tue" "Wed" "Thu" "Fri"];
  };

  system.stateVersion = "26.05";
}
