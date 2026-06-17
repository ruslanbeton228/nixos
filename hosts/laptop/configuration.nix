# NixOS configuration for laptop.

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

    # BOOT

    boot = {
      extraModulePackages = [ config.boot.kernelPackages.rtl8188eus-aircrack ]; # Fix wifi svistok
      loader = {
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot/efi";
        };
        grub = {
          devices = [ "nodev" ];
          efiSupport = true;
          useOSProber = true;
          configurationLimit = 7;
          gfxmodeEfi = "1920x1080";
        };
      };
    };

  # HARDWARE (FIX KITAI_WIFI)

  hardware.usb-modeswitch.enable = true;

  # NETWORK

  networking = {
    hostName = "laptop";
    networkmanager = {
      enable = true;
      plugins = with pkgs; [
        networkmanager-l2tp
        networkmanager-openvpn
        networkmanager-openconnect
        networkmanager-strongswan
      ];
      appendNameservers = [ "8.8.8.8" ];
    };
    firewall = { 
      enable = false;
    };
  };

  # TIMEZONE
  
  time.timeZone = "Asia/Irkutsk";

  # LANGUAGE

  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-k16n.psf.gz";  # RU
    packages = [ pkgs.terminus_font ];
    keyMap = "us";
  };

  # DESKTOP
  
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    xkb = {
      variant = "";
      options = "grp:alt_shift_toggle";
      layout = "us,ru";
    };
  }; 

  # TOUCHPAD

  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      tapping = true;              # default true
      scrollMethod = "twofinger";  # default "twofinger"
      disableWhileTyping = true;   # default false
    };
  };
  services.touchegg.enable = true;
  systemd.user.services = {
    touchegg-client = {
      description = "Touchégg. The client.";
      wantedBy = pkgs.lib.mkForce [];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.touchegg}";
      };
    };
  };
  
  # SOUND

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # USERS
  # Define a user account. Don't forget to set a password with ‘passwd’.

  users.users = {
    roman = {
      isNormalUser = true;
      initialPassword = "password"; # Don't forget to change it with passwd.
      extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
      shell = pkgs.zsh; # Default user shell.
      packages = with pkgs; [ 
      ];
    };
    # ADD MORE USERs HERE 
  };

  # PROGRAMS
  
  programs.zsh = { 
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    ohMyZsh = { 
      enable = true;
      theme = "jonathan";
      plugins = [ 
        "git"
      ];
      customPkgs = [
        pkgs.nix-zsh-completions
      ];
    };
  };

  programs.nh = {
    enable = true;
    flake = "/home/roman/.setup";
  };
 
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment = {
    shells = [ 
      pkgs.bash
      pkgs.zsh
    ];
    systemPackages = with pkgs; [
      curl
      wget
      htop 
      bottom 
      git 
      neovim 
      nmap
      jq
      ncdu
      unzip
      tree
      nitch
      rsync
      lm_sensors  
      ntfs3g
      dnsutils
      firefox
      google-chrome
      wireguard-tools
      tilix
      vscode
      zoom-us
      mattermost-desktop
      flameshot
      kazam
      telegram-desktop 
      keepassxc
      vault
      lshw
      openconnect
      opencode
      # Gnome.
      gnomeExtensions.dash-to-dock
      gnomeExtensions.burn-my-windows
      gnome-tweaks
      tela-circle-icon-theme
      volantes-cursors
      # WIFI DEBUG.
      usbutils
      pciutils
      usb-modeswitch
    ];
  };

  # SSH

  services.openssh = { 
    enable = true;
    startWhenNeeded = true;
    allowSFTP = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # NIX

  nixpkgs = { 
    config = {
      allowUnfree = true;
    };
  };
  nix = {
    extraOptions = ''
    experimental-features = nix-command flakes
    '';
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?

}

