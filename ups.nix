
{ config, lib, pkgs, modulesPath, ... }:

let
  vid = "051d";
  pid = "0002";
  upsname = "apc";
  upsmonUser = "nut";
in
{
  # Load in the nixos-unstable version of ups.nix (has fixes, etc)
  disabledModules = [ "services/monitoring/ups.nix" ];
  imports = [
    <nixos-unstable/nixos/modules/services/monitoring/ups.nix>
  ];

  # age.secrets.upsmonUserPasswordFile.file = "/etc/nixos/secrets/upsmonUser.passwordFile.age";
  
  # APC UPS declaration
  power.ups = {
    enable = true;
    mode = "standalone";
    openFirewall = false;

    ups."${upsname}" = {
      # I noticed that nut-scanner put everything it detected in quotes and NixOS wasn't doing that
      driver = "\"usbhid-ups\"";
      port = "\"auto\"";
      # Except this guy, he gets quoted and putting escaped quotes here makes him double-quoted
      description = "APC BE580G2 UPS";
      directives = [
        "vendorid = \"${vid}\""
        "productid = \"${pid}\""
        "product = \"Back-UPS ES 850G2 FW:931.a10.D USB FW:a10\""
        "vendor = \"American Power Conversion\""
        "serial = \"4B2216P31656\""
        #"bus = \"001\""
      ];
      # maxStartDelay = 30;
      # "this option is not valid for usbhid-ups" -- the internet
      maxStartDelay = null;
    };

    upsmon = {
      enable = true;
      monitor."${upsname}" = {
        system = "${upsname}@localhost";
        user = "${upsmonUser}";
        # passwordFile = config.age.secrets.upsmonUserPasswordFile.path;
        passwordFile = "/etc/nixos/secrets/upsmonUser.passwordFile";
        type = "master";
      };
      settings = {
        # Run as unprivileged user
        RUN_AS_USER = lib.mkForce "${upsmonUser}";
        # If we ever need to shutdown, here's how to do it
        SHUTDOWNCMD = "''${pkgs.systemd}/bin/shutdown now";
        # Require at least one UPS because it's the only one we have
        MINSUPPLIES = 1;
        # Poll every 15 seconds
        POLLFREQ = 15;
        # Except if we're on battery, poll every 5 seconds
        POLLFREQALERT = 5;
        # Wait up to 15 seconds for everyone to disconnect during shutdown events
        HOSTSYNC = 15;
        # Allow UPS to go missing for 1 minute before declaring it "dead"
        DEADTIME = 60;
        # If the battery needs to be replaced, generated an event every 12 hours
        RBWARNTIME = 43200;
        # If we can't reach any of the UPS entries in this config file, warn every 5 minutes
        NOCOMMWARNTIME = 300;
        # If we decide we need to shutdown, give the final warning 5 seconds before it happens
        FINALDELAY = 5;

        # Notification configuration
        NOTIFYFLAG = [
          [ "ONLINE"    "SYSLOG"      ]
          [ "ONBATT"    "SYSLOG+WALL" ]
          [ "LOWBATT"   "SYSLOG+WALL" ]
          [ "FSD"       "SYSLOG+WALL" ]
          [ "COMMOK"    "SYSLOG"      ]
          [ "COMMBAD"   "SYSLOG+WALL" ]
          [ "SHUTDOWN"  "SYSLOG+WALL" ]
          [ "REPLBATT"  "SYSLOG+WALL" ]
          [ "NOCOMM"    "SYSLOG+WALL" ]
        ];

        NOTIFYMSG = [
          [ "ONLINE"    "UPS %s is getting line power"               ]
          [ "ONBATT"    "UPS %s lost line power. Running on battery" ]
          [ "LOWBATT"   "UPS %s is low on battery"                   ]
          [ "FSD"       "UPS %s is being shutdown"                   ]
          [ "COMMOK"    "Communications established with UPS %s"     ]
          [ "COMMBAD"   "Communications lost with UPS %s"            ]
          [ "SHUTDOWN"  "System is shutting down. Goodbye <3"        ]
          [ "REPLBATT"  "UPS %s battery needs to be replaced"        ]
          [ "NOCOMM"    "UPS %s cannot be contacted for monitoring"  ]
        ];
      };
    };

    upsd = {
      enable = true;
      listen = [ 
        { address = "127.0.0.1"; } 
      ];
    };

    users."${upsmonUser}" = {
      passwordFile = "/etc/nixos/secrets/upsmonUser.passwordFile";
      upsmon = "primary";
    };
  };
 
  users.users."${upsmonUser}" = {
    isSystemUser = true;
    group = "${upsmonUser}";
    home = "/var/lib/nut";
    createHome = true;
  };
  users.groups."${upsmonUser}" = { };

  services.udev.packages = [ pkgs.nut ];

  # The UPS should be accessible by non-root user nut
  # services.udev.extraRules = ''
  #   SUBSYSTEM=="usb", ATTRS{idVendor}=="${vid}", ATTRS{idProduct}=="${pid}", MODE="644", GROUP="${upsmonUser}", OWNER="${upsmonUser}", SYMLINK+="usb/ups"
  # '';
}
