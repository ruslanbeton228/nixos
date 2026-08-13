{
  description = "NixOS configurations for my devices";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      # --- COMMON VALUES ---

      system = "x86_64-linux";
      inherit (nixpkgs) lib;
      inherit (lib) nixosSystem;
      pkgs = nixpkgs.legacyPackages.${system};

      # --- INSTALLATION SCRIPTS ---

      setupDisk = pkgs.writeShellApplication {
        name = "setup-disk";
        runtimeInputs = with pkgs; [
          coreutils
          dosfstools
          e2fsprogs
          gawk
          gnugrep
          lvm2
          parted
          util-linux
        ];
        text = builtins.readFile ./scripts/setup-disk.sh;
        meta.description = "Prepare storage for a NixOS installation";
      };
      setupNetwork = pkgs.writeShellApplication {
        name = "setup-network";
        runtimeInputs = with pkgs; [
          coreutils
          iproute2
          iputils
        ];
        text = builtins.readFile ./scripts/setup-network.sh;
        meta.description = "Configure temporary installer networking";
      };
    in
    {
      # --- NIXOS HOSTS ---

      nixosConfigurations = {
        laptop = nixosSystem {
          modules = [
            ./hosts/desktop-laptop/configuration.nix
          ];
        };
        workstation = nixosSystem {
          modules = [
            ./hosts/desktop-workstation/configuration.nix
          ];
        };
        vps-vpn = nixosSystem {
          modules = [
            ./hosts/vps-vpn/configuration.nix
          ];
        };
      };

      # --- DEVELOPMENT TOOLS ---

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;

      # --- PACKAGES ---

      packages.${system} = {
        default = setupDisk;
        setup-disk = setupDisk;
        setup-network = setupNetwork;
      };

      # --- APPLICATIONS ---

      apps.${system} = {
        default = {
          type = "app";
          program = lib.getExe setupDisk;
          meta.description = "Prepare storage for NixOS";
        };
        setup-disk = {
          type = "app";
          program = lib.getExe setupDisk;
          meta.description = "Prepare storage for NixOS";
        };
        setup-network = {
          type = "app";
          program = lib.getExe setupNetwork;
          meta.description = "Configure installer networking";
        };
      };

      # --- CHECKS ---

      # Evaluate every host without building its system closure.
      checks.${system} =
        let
          mkEval =
            name: drv:
            pkgs.runCommand "check-${name}" {
              _trigger = builtins.typeOf drv;
            } "touch $out";
          hosts = [
            "laptop"
            "workstation"
            "vps-vpn"
          ];
        in
        (builtins.listToAttrs (
          map (
            name:
            let
              configuration = self.nixosConfigurations.${name};
            in
            {
              inherit name;
              value = mkEval name configuration.config.system.build.toplevel;
            }
          ) hosts
        ))
        // {
          setup-disk = setupDisk;
          setup-network = setupNetwork;
        };
    };
}
