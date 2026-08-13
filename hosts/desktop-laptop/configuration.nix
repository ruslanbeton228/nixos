# NixOS configuration for laptop.

{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- BOOT ---

  boot = {
    # Support the external Wi-Fi adapter.
    extraModulePackages = [
      config.boot.kernelPackages.rtl8188eus-aircrack
    ];
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      grub = {
        enable = true;
        configurationLimit = 7;
        devices = [ "nodev" ];
        efiSupport = true;
        gfxmodeEfi = "1920x1080";
        useOSProber = true;
      };
    };
  };

  # --- HARDWARE ---

  hardware.usb-modeswitch.enable = true;

  # --- NETWORKING ---

  networking = {
    hostName = "laptop";
    useDHCP = false;
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

  # --- LOCALIZATION ---

  time.timeZone = "Asia/Irkutsk";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-k16n.psf.gz"; # RU
    packages = [ pkgs.terminus_font ];
    keyMap = "us";
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
      initialPassword = "password";
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
      docker-compose
      git
      neovim
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
      firefox
      google-chrome
      keepassxc
      mattermost-desktop
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
      lm_sensors
      lshw
      ntfs3g
      pciutils
      usb-modeswitch
      usbutils
    ];
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

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      trusted-users = [ "@wheel" ];
    };
  };

  # --- SYSTEM ---

  # Keep this value at the release used for the initial installation.
  system.stateVersion = "24.11";
}
