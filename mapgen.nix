
{ config, lib, pkgs, modulesPath, ... }:

let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
in
{
  # Make an unprivileged, system user for running these tasks
  users.users.mapgen = {
    isSystemUser = true;
    group = "mapgen";
    description = "mapgen user";
    home = "/var/lib/mapgen";
    createHome = true;
    # o+rx needed for caddy.nix
    homeMode = "755";
    packages = [
      pkgs.python39
      pkgs.python39Packages.pip
      unstablePkgs.caddy
    ];
  };
  users.groups.mapgen = { };

  # This is the actual service that does the work
  systemd.services.mesh-geojson = {
    description = "a service that generates geojson for mapping";

    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    
    path = [ pkgs.python39 pkgs.python39Packages.pip ];

    serviceConfig = {
      Type = "oneshot";
      User = "mapgen";
      Group = "mapgen";

      TimeoutStartSec = "5min";
      Restart = "no";
      ExecStart = "/var/lib/mapgen/update_geojson.sh";
    };
  };

  # This is the timer that periodically triggers the above service
  # N.B. -- don't try to be clever and put the whole unit description in the timer's unitConfig. Doesn't work
  systemd.timers.mesh-geojson = {
    description = "a timer that periodically invokes mesh-geojson.service";

    wantedBy = [ "timers.target" ];

    timerConfig = {
      # The service already runs at boot.
      # Just run it every hour thereafter.
      OnUnitActiveSec = "1hour";
    };
  };

  # Finally, we need a webserver that handles that geojson
  # This has been migrated to caddy.nix. Will be removed once it's clear we're sticking with that
  #systemd.services.mesh-webserver = {
  #  description = "a map webserver";
  #
  #  wantedBy = [ "multi-user.target" ];
  #  after = [ "network-online.target" ];
  #
  #  path = [ unstablePkgs.caddy ];
  #
  #  serviceConfig = {
  #    Type = "simple";
  #    User = "mapgen";
  #    Group = "mapgen";
  #
  #    Restart = "on-failure";
  #    RestartSec = "10s";
  #
  #    ExecStart = "/var/lib/mapgen/website/start_webserver.sh";
  #  };
  #};
}
