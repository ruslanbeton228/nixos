# █▀▄▀█ ▄▀█ █ █▄░█   █▀▀ █░░ ▄▀█ █▄▀ █▀▀ ▀
# █░▀░█ █▀█ █ █░▀█   █▀░ █▄▄ █▀█ █░█ ██▄ ▄
# -- -- -- -- -- -- -- -- -- -- -- -- -- -

{
  description = "NixOS configurations for my devices";
  
  inputs = {
    # Default:
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  
  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      specialArgs = { inherit system inputs; };
    in {
    nixosConfigurations = {
      vps-vpn = lib.nixosSystem {
        inherit specialArgs;
        modules = [
          ./hosts/vps-vpn/configuration.nix
        ];
      };
      laptop = lib.nixosSystem {
        inherit specialArgs;
        modules = [
          ./hosts/laptop/configuration.nix
        ];
      };
      # ... add more hosts here:
    };
  };
}  