# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
  natInterface = "enp1s0";
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Hardening profile
      <nixpkgs/nixos/modules/profiles/hardened.nix>
      # <agenix/modules/age.nix>
      ./ups.nix
      ./mapgen.nix
      ./caddy.nix
      ./restic.nix
      ./secrets/configuration-private.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

  # we want a reasonably-updated kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelPackages = pkgs.linuxPackages_6_9_hardened;
  
  # tailscale subnet routers need to be able to forward 
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  # Override networking-related options that enable strict reverse path filtering in hardened profile
  boot.kernel.sysctl."net.ipv4.conf.all.log_martians" = false;
  boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" = "0";
  boot.kernel.sysctl."net.ipv4.conf.default.log_martians" = false;
  boot.kernel.sysctl."net.ipv4.conf.default.rp_filter" = "0";

  networking.hostName = "fw-mesh-vm-nixos";
  
  # Set your time zone.
  time.timeZone = "America/Phoenix";

  # Enable networking
  networking = {
    networkmanager.enable = true;
  };
  
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  users.groups.josh = {};
  users.users.josh = {
    isNormalUser = true;
    home = "/home/josh";
    description = "josh";
    group = "josh";
    extraGroups = [ "users" "networkmanager" "wheel" "docker" ];
  };

  users.groups.ghing = {};
  users.users.ghing = {
    isNormalUser = true;
    home = "/home/ghing";
    description = "geoff";
    group = "ghing";
    extraGroups = [ "users" ];
  };
  users.mutableUsers = false;

  # Only wheel (sudo) users can do nix sry
  nix.settings.allowed-users = [ "@wheel" ];
  security.sudo.execWheelOnly = true;

  # Packages installed in system profile
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    firefox
    tmux
    mosh
    stow
    wireguard-tools
    htop
    podman-compose
    docker-compose
    usbutils
    qrencode
    envsubst
    quickemu
    sshpass
    age
    restic
    ripgrep
    ncdu
    (pkgs.callPackage <agenix/pkgs/agenix.nix> {})
    unstablePkgs.helix
    unstablePkgs.tailscale
  ];

  # Also add 1Password. Unfortunately, GUI is what provides op-ssh-sign.
  # nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ ""]
  programs._1password = { enable = true; };
  programs._1password-gui = { enable = true; };

  # Disable sleep
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Enable the X11 windowing system.
  # Enable X11 + gnome + xfce.
  services.xserver = {
    enable = true;
    displayManager = {
      gdm.enable = true;
    };
    desktopManager = {
      gnome.enable = true;
      xfce.enable = false;
    };
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };
  
  # Enable xrdp with xfce as the DE because gnome is being a pain in the ass
  services.xrdp = {
    enable = true;
    defaultWindowManager = "xfce4-session";
  };

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # From Xe Iaso
    extraConfig = ''
      AuthenticationMethods publickey
      AllowStreamLocalForwarding no
      AllowAgentForwarding yes
      AllowTcpForwarding yes
      X11Forwarding no
    '';
  };

  networking.nat.enable = true;
  # Death to Wi-Fi, long live Ethernet
  networking.nat.externalInterface = "${natInterface}";
  networking.nat.internalInterfaces = [ "mesh-wg" ];
  # Configure the firewall
  networking.firewall = {
    enable = true;
    # It would be cool to not do this, but there are lots of edge cases
    # And if you're successfully sending packets in on either of these interfaces, you're authenticated already anyway
    trustedInterfaces = [ "tailscale0" "mesh-wg" ];
    allowedTCPPorts = [ 
      # ssh
      22 
      # xrdp
      3389
      # mesh services/caddy reverse proxy
      # applies filtering based on IP for certain routes anyway
      80
    ];
    allowedUDPPortRanges = [
      # wireguard
      { from = 51820; to = 51820; }
      # mosh server
      { from = 60000; to = 61000; }
      # tailscale
      { from = config.services.tailscale.port; to = config.services.tailscale.port; }
    ];
    # "warning: Strict reverse path filtering breaks Tailscale exit node use and some subnet routing setups. Consider setting `networking.firewall.checkReversePath` = 'loose'"
    checkReversePath = "loose";
  };
  
  # Enable and configure tailscale with a oneshot systemd unit
  nixpkgs.overlays = [(final: prev: {
    tailscale = unstablePkgs.tailscale;
  })];
  services.tailscale.enable = true;
  # oneshot systemd unit defined in ./configuration-private.nix

  networking.wireguard.interfaces = {
    mesh-wg = {
      # Determines the IP address and subnet of the server's end of the tunnel interface.
      ips = [ "10.100.0.1/24" ];

      # The port that WireGuard listens to. Must be accessible by the client + synchronized with firewall allowedUDPPorts
      listenPort = 51820;

      # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
      # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o ${natInterface} -j MASQUERADE
      '';

      # This undoes the above command
      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o ${natInterface} -j MASQUERADE
      '';

      # private key file and peers defined in ./configuration-private.nix
    };
  };
  
  # Virtualization
  virtualisation = {
    podman = {
      enable = true;
    };
    docker = {
      enable = true;
    };
  };  

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

  # don't do auto upgrades
  system.autoUpgrade.enable = false;
  system.autoUpgrade.allowReboot = false;

  # periodically collect garbage
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # and do automatic store optimization
  nix.settings.auto-optimise-store = true;

  # Spice agent
  #services.spice-vdagentd.enable = true;
  #services.qemuGuest.enable = true;
}
