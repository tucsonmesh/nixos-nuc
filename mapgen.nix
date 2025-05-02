
{ config, lib, pkgs, modulesPath, ... }:

let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
in
{
  # Create the webbies group so that mapgen and caddy can collab
  users.groups.webbies = { name = "webbies"; };

  # Make an unprivileged, system user for running mapgen tasks
  users.users.mapgen = {
    isSystemUser = true;
    group = "mapgen";
    description = "mapgen user";
    home = "/var/lib/mapgen";
    createHome = true;
    homeMode = "750";
    packages = [
      pkgs.python311
      pkgs.python311Packages.pip
      unstablePkgs.caddy
    ];
    extraGroups = [ "webbies" ];
  };
  users.groups.mapgen = { };

  # This is the actual service that does the work
  systemd.services.mesh-geojson = {
    description = "a service that generates geojson for mapping";

    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    path = [ pkgs.python311 pkgs.python311Packages.pip ];

    script = ''
      set -x

      echo "Updating mesh.geojson..."

      source /var/lib/mapgen/trello_env.sh
      pushd  /var/lib/mapgen/trello_to_geojson
      source ./venv/bin/activate
      python get_board.py
      if [ $? -ne 0 ]; then
        python call_for_help.py
        echo "Updates failed!"
      else
        mv out.geojson /var/lib/mapgen/website/mesh.geojson
        echo "Updates completed!"
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "mapgen";
      Group = "mapgen";

      TimeoutStartSec = "5min";
      Restart = "no";
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
      OnUnitActiveSec = "2hours";
    };
  };
}
