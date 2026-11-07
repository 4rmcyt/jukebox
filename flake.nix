{
  description = "Office jukebox: Music Assistant on a Lenovo Tiny";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    lanzaboote,
    nix-mineral,
    sops-nix,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    nixosConfigurations.jukebox = nixpkgs.lib.nixosSystem {
      modules = [
        disko.nixosModules.disko
        lanzaboote.nixosModules.lanzaboote
        nix-mineral.nixosModules.nix-mineral
        sops-nix.nixosModules.sops
        ./hosts/jukebox
      ];
    };

    packages.x86_64-linux.teams-bridge = pkgs.callPackage ./bridge/package.nix {};

    formatter.x86_64-linux = pkgs.alejandra;
  };
}
