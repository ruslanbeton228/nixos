# NixOS configuration for the VPS-VPN (Netherlands).

{ inputs, pkgs, ... }:
{
  imports = [
    # Host autogenerate hardware configuration:
    ./hardware-configuration.nix # virtual
  ];

  boot.loader.grub = {
    device = "/dev/vda";
    configurationLimit = 7;
  };

  i18n.defaultLocale = "en_US.UTF-8";

  environment = {
    shells = [
      pkgs.bash
      pkgs.zsh
    ];
    systemPackages = with pkgs; [
      curl
      dnsutils
      docker-compose
      git
      htop
      neovim
      wget
      xraymgr
    ];
  };
  networking = {
    hostName = "vps-vpn";
    interfaces = {
      ens3.ipv4.addresses = [
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

  nix = {
    package = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings = {
      trusted-users = [ "papa" ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (final: prev:{
      xraymgr = inputs.xraymgr.packages."${pkgs.stdenv.hostPlatform.system}".default;  
    })
  ];

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
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
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
      # ... add more users here
    };
  };

  virtualisation = {
    docker.enable = true;
  };

  time.timeZone = "Europe/Amsterdam";

  system.stateVersion = "25.11";
}