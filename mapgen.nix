
{ config, lib, pkgs, modulesPath, ... }:

let
  pythonPackages = pkgs.python312Packages;

  pytrelloapi = pythonPackages.buildPythonPackage {
    name = "py-trello-api";
    src = pkgs.fetchFromGitHub {
      owner = "Konano";
      repo = "py-trello-api";
      rev = "f4ec4c90b9a837d09bd3bc6e593510d0b7234c64";
      sha256 = "KPOAHIm05nzbtPmkfH5vxzyuBCr8ZXQ7p9tPQ6KUGKA=";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    dependencies = [
      pythonPackages.requests
      pythonPackages.requests-oauthlib
      pythonPackages.python-dateutil
      pythonPackages.pytz
    ];
  };

  pytrello = pythonPackages.buildPythonPackage {
    name = "py-trello";
    src = pkgs.fetchFromGitHub {
      owner = "sarumont";
      repo = "py-trello";
      rev = "f89a72a218295c572921103a08d4ce3ec225c353";
      sha256 = "";
    };
  };

  trello2geojson =
    pythonPackages.buildPythonPackage {
      format = "pyproject";
      name = "trello-to-geojson";
      src = pkgs.fetchFromGitHub {
        owner = "tucsonmesh";
        repo = "trello-to-geojson";
        rev = "6cf978379da1e5d6b18669ae34fd56fbc6fde709";
        sha256 = "Y3rge0srt6qk4R5iX+iJ3GYIPb3bF1UFcJrpLRThom4=";
      };
      propagatedBuildInputs = [
        pytrelloapi
        pythonPackages.setuptools
        pythonPackages.slack-sdk
        pythonPackages.requests
        pythonPackages.requests-oauthlib
        pythonPackages.pytz
      ];
    };

  mapgenPkgs = [
    pkgs.acl
    pkgs.python311
    pkgs.python311Packages.pip
    trello2geojson
  ];
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
    homeMode = "755";
    packages = mapgenPkgs;
    extraGroups = [ "webbies" ];
  };
  users.groups.mapgen = { };

  # This is the actual service that does the work
  systemd.services.mesh-geojson = {
    description = "a service that generates geojson for mapping";

    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # All we need on the path are the binaries defined in mapgenPkgs  
    path = mapgenPkgs;

    script = ''
      set -x

      echo "Updating mesh.geojson..."

      pushd /var/lib/mapgen
      source /var/lib/mapgen/trello_env.sh
      trello-to-geojson > mesh.geojson

      if [ $? -ne 0 ]; then
        call-for-help C056JJYT9UH "Help! I can't generate new map geojson from the trello! The map won't update without this!"
        echo "Updates failed!"
      else
        echo "Updates completed!"
      fi

      # Either way (given we may have partially generated a mesh.geojson result), ensure caddy can read any file that does exist
      if [ -f mesh.geojson ]; then
        setfacl --modify u:caddy:r mesh.geojson
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
      # Let's run it every two hours thereafter.
      OnUnitActiveSec = "2hours";
    };
  };
}
