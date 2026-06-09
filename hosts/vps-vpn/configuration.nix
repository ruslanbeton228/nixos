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
      bat
      bottom
      curl
      dnsutils
      docker-compose
      duf
      nitch
      git
      htop
      ipset
      jq
      neovim
      ncdu
      nitch
      rsync
      tree
      unzip
      wget
    ];
  };
  
  networking = {
    hostName = "vpn-1vds";
    useDHCP = false;
    interfaces.ens3 = {
      useDHCP = false;
      # Spoof/Hardcode the MAC address required by the hosting provider
      macAddress = "52:54:00:73:1F:1B";
      ipv4.addresses = [
        {
          address = "85.137.89.216";
          prefixLength = 32;
        }
      ];
    };
    # Explicitly specify the interface for the gateway
    # since it's outside the /32 subnet
    defaultGateway = {
      address = "10.0.0.1";
      interface = "ens3";
    };
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
      trusted-users = [ "@wheel" ];
    };
  };

  nixpkgs.config.allowUnfree = true;

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
    qemuGuest.enable = true;
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

  system.stateVersion = "26.05";
}
