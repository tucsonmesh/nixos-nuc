# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./configuration-private.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # tailscale subnet routers need to be able to forward 
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

  networking.hostName = "nixos-nuc"; # Define your hostname.
  # ignore wpa_supplicant because we'll be using NetworkManager to configure wireless networking
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Set your time zone.
  time.timeZone = "America/Phoenix";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  # networking.interfaces.wlp2s0.useDHCP = true;
  # TODO: NetworkManager basically just ignores all this?
  networking.interfaces.wlp2s0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "10.96.12.184";
        prefixLength = 26;
      }
    ];
  };
  networking.defaultGateway = "10.96.12.129";
  networking.nameservers = [ "10.96.12.129" ];
    
  # Enable sound
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Define user accounts. Don't forget to set a password with ‘passwd’.
  users.users.josh = {
    isNormalUser = true;
    home = "/home/josh";
    description = "josh";
    extraGroups = [ "wheel" "networkmanager" "docker" ]; # Enable 'sudo', ability to configure network, and docker
    # hashed passwords and authorized keys set in ./configuration-private.nix
  };
  users.users.glen = {
    isNormalUser = true;
    home = "/home/glen";
    description = "glen";
    # hashed passwords and authorized keys set in ./configuration-private.nix
  };

  # Disable mutable users
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
    unstablePkgs.helix
    unstablePkgs.tailscale
  ];

  # Disable sleep
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Enable X11 + gnome + xfce.
  services.xserver = {
    enable = true;
    displayManager = {
      gdm.enable = true;
    };
    desktopManager = {
      gnome.enable = true;
      xfce.enable = true;
    };
  };
    
  # Enable xrdp with xfce as the DE because gnome is being a pain in the ass
  services.xrdp = {
    # TODO: disabled until a CVE is addressed
    #enable = true;
    enable = false;
    defaultWindowManager = "xfce4-session";
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
    # From Xe Iaso
    extraConfig = ''
      AuthenticationMethods publickey
      AllowStreamLocalForwarding no
      AllowAgentForwarding no
      AllowTcpForwarding yes
      X11Forwarding no
    '';
  };

  networking.nat.enable = true;
  networking.nat.externalInterface = "wlp2s0";
  networking.nat.internalInterfaces = [ "mesh-wg" ];
  # "warning: Strict reverse path filtering breaks Tailscale exit node use and some subnet routing setups. Consider setting `networking.firewall.checkReversePath` = 'loose'"
  # Configure the firewall, letting basically just tailscale & SSH through
  networking.firewall = {
    enable = true;
    # tailscale
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [ 
      # ssh
      22 
      # xrdp
      3389
    ];
    allowedUDPPortRanges = [
      # wireguard
      { from = 51820; to = 51820; }
      # mosh server
      { from = 60000; to = 61000; }
      # tailscale
      { from = config.services.tailscale.port; to = config.services.tailscale.port; }
    ];
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
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o wlp2s0 -j MASQUERADE
      '';

      # This undoes the above command
      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o wlp2s0 -j MASQUERADE
      '';

      # private key file and peers defined in ./configuration-private.nix
    };
  };
  
  # Virtualization
  virtualisation = {
    podman = {
      enable = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.dnsname.enable = true;
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
  system.stateVersion = "22.05"; # Did you read the comment?

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
}

