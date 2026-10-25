# NixOS configuration for the desktop workstation.

{ pkgs, inputs, ... }:
let
  # Grub theme
  theme = inputs.distro-grub-themes.packages.${pkgs.stdenv.hostPlatform.system}."msi-grub-theme";
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- BOOT ---

  boot = {
    initrd.verbose = false;
    consoleLogLevel = 0;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
    ];
    loader = {
      efi = {
        canTouchEfiVariables = false;
        efiSysMountPoint = "/boot/efi";
      };
      grub = {
        enable = true;
        configurationLimit = 7;
        devices = [ "nodev" ];
        efiInstallAsRemovable = true;
        efiSupport = true;
        useOSProber = true;
        gfxmodeEfi = "1920x1080";
        splashImage = "${theme}/splash_image.jpg";
        inherit theme;
      };
    };
  };

  # --- HARDWARE ---

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true; 
    };  
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  # --- NETWORKING ---

  networking = {
    hostName = "workstation";
    # NetworkManager obtains addresses from the local DHCP server.
    useDHCP = false;
    networkmanager = {
      enable = true;
      plugins = with pkgs; [
        networkmanager-l2tp
        networkmanager-openvpn
        networkmanager-openconnect
        networkmanager-strongswan
      ];
    };
  };

  # --- LOCALIZATION ---

  time.timeZone = "Asia/Irkutsk";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-k16n.psf.gz";
    keyMap = "us";
    packages = [ pkgs.terminus_font ];
  };

  # --- GNOME DESKTOP ---

  services = {
    desktopManager.gnome.enable = true;
    displayManager.gdm.enable = true;
    # This shared option also configures keyboard layouts on Wayland.
    xserver.xkb = {
      layout = "us,ru";
      options = "grp:alt_shift_toggle";
    };
  };

  # --- AUDIO ---

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  security.rtkit.enable = true;

  # --- USERS ---

  users.users = {
    roman = {
      isNormalUser = true;
      description = "Roman";
      extraGroups = [
        "docker"
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.zsh;
    };
  };

  # --- PROGRAMS ---

  programs = {
    nh = {
      enable = true;
      flake = "/home/roman/.setup";
    };
    nix-ld.enable = true;
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      ohMyZsh = {
        enable = true;
        theme = "jonathan";
        plugins = [ "git" ];
        customPkgs = [ pkgs.nix-zsh-completions ];
      };
    };
    gamescope = {
      enable = true;
      # ! broken: steam: setuid use of bubblewrap is not supported in this build
      # ? see: https://github.com/NixOS/nixpkgs/issues/523200
      capSysNice = false;
    };
    steam = {
      enable = true;
      extest = {
        enable = true;
      };
      gamescopeSession = {
        enable = true;
      };
    };
  };

  # --- PACKAGES ---

  environment = {
    # Work around broken L2TP/IPsec configuration with strongSwan.
    # See: https://github.com/NixOS/nixpkgs/issues/375352
    etc."strongswan.conf".text = "";
    shells = [
      pkgs.bash
      pkgs.zsh
    ];
    systemPackages = with pkgs; [
      # Command-line utilities.
      bottom
      curl
      htop
      jq
      ncdu
      nitch
      rsync
      tree
      unzip
      wget

      # Development tools.
      claude-code
      docker-compose
      git
      nvchad
      opencode
      python3
      uv
      vscode

      # Networking.
      dnsutils
      nmap
      openconnect
      wireguard-tools

      # Desktop applications.
      bottles
      firefox
      gradia
      google-chrome
      keepassxc
      kooha
      mattermost-desktop
      protonup-qt
      telegram-desktop
      tilix
      vault
      zoom-us

      # GNOME extensions and customization.
      gnomeExtensions.burn-my-windows
      gnomeExtensions.dash-to-dock
      gnome-tweaks
      tela-circle-icon-theme
      volantes-cursors

      # Hardware and storage.
      lact
      lm_sensors
      lshw
      ntfs3g
      pciutils
      usbutils
    ];
  };

  # --- SERVICES ---

  services.fstrim.enable = true;

  services.lact.enable = true;

  services.xray = {
    enable = true;
    settingsFile = "/etc/xray/config.json";
  };

  # Skip startup until the imperative configuration has been created.
  systemd.services.xray.unitConfig = {
    ConditionPathExists = "/etc/xray/config.json";
  };

  # --- SSH ---

  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    allowSFTP = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # --- VIRTUALIZATION ---

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };

  # --- NIX ---

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      trusted-users = [ "@wheel" ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        nvchad = inputs.nix4nvchad.packages.${pkgs.stdenv.hostPlatform.system}.default;
      })
    ];
  };
  

  # --- SYSTEM ---

  # Keep this value at the release used for the initial installation.
  system.stateVersion = "26.05";
}
