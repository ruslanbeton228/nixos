# NixOS configuration for the VPS-VPN (Netherlands).

{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- BOOT ---

  boot.loader.grub = {
    device = "/dev/vda";
    configurationLimit = 7;
  };

  # --- LOCALIZATION ---

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Amsterdam";

  # --- PACKAGES ---

  environment = {
    shells = [
      pkgs.bash
      pkgs.zsh
    ];
    systemPackages = with pkgs; [
      # Command-line utilities.
      htop
      jq
      ncdu
      tree

      # Development tools.
      git
      neovim

      # Networking.
      curl
      dnsutils

      # System administration.
      docker-compose
    ];
  };

  # --- NETWORKING ---

  networking = {
    hostName = "vps-vpn";
    useDHCP = false;
    interfaces.ens3 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "89.110.66.188";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "89.110.66.1";
    nameservers = [
      "8.8.8.8"
      "1.1.1.1"
    ];
    firewall = {
      enable = true;
      allowedTCPPorts = [
        53
        80
        443
        1500
      ];
      allowedUDPPorts = [
        53
        500
        1500
        4500
      ];
    };
  };

  # --- NIX ---

  nix = {
    package = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings = {
      trusted-users = [ "@wheel" ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  # --- PROGRAMS ---

  programs = {
    nh = {
      enable = true;
      flake = "/home/papa/.setup";
    };
    zsh = {
      enable = true;
      ohMyZsh = {
        enable = true;
        theme = "jonathan";
      };
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };
  };

  # --- SERVICES ---

  services = {
    fail2ban = {
      enable = true;
      extraPackages = [ pkgs.ipset ];
      jails = {
        sshd = {
          settings = {
            enable = true;
            port = "22";
          };
        };
      };
    };
    openssh = {
      enable = true;
      allowSFTP = true;
      ports = [ 22 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        LogLevel = "VERBOSE";
      };
    };
    qemuGuest.enable = true;
  };

  # --- USERS ---

  users = {
    users = {
      papa = {
        isNormalUser = true;
        description = "Roman";
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOiDsyUqqD+4HLTULbd5Es3F6a07fiSu8mE2C3ErcCHe rootVPN"
        ];
      };
    };
  };

  # --- VIRTUALIZATION ---

  virtualisation = {
    docker.enable = true;
  };

  # --- SYSTEM ---

  # Keep this value at the release used for the initial installation.
  system.stateVersion = "26.05";
}
