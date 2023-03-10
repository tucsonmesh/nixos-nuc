
{ config, lib, pkgs, modulesPath, ... }:

let
  vid = "051d";
  pid = "0002";
  upsname = "apc";
  upsmonUser = "nut";
  upsmonPassword = "ups-password";
in
{
  # We have a UPS now
  # Let's copy reddit dude
  # https://www.reddit.com/r/NixOS/comments/10rwzbc/working_powerupsnut_netserver_config_for_nixos/
  # Also just this
  # https://github.com/NixOS/nixpkgs/issues/91681
  power.ups = {
    enable = true;
    mode = "standalone";
    maxStartDelay = 30;
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
        "bus = \"002\""
      ];
      # "this option is not valid for usbhid-ups" -- the internet
      maxStartDelay = null;
    };
  };
 
  users.users."${upsmonUser}" = {
    isSystemUser = true;
    group = "${upsmonUser}";
    home = "/var/lib/nut";
    createHome = true;
  };
  users.groups."${upsmonUser}" = { };

  # The UPS should be accessible by non-root user nut
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="${vid}", ATTRS{idProduct}=="${pid}", MODE="644", GROUP="${upsmonUser}", OWNER="${upsmonUser}", SYMLINK+="usb/ups"
  '';

  systemd.services.upsd.serviceConfig = {
    User = "${upsmonUser}";
    Group = "${upsmonUser}";
  };

  systemd.services.upsdrv.serviceConfig = {
    User = "${upsmonUser}";
    Group = "${upsmonUser}";
  };

  # upsSetup is a dependency we want to run first from 
  # https://github.com/NixOS/nixpkgs/blob/4a0377b56ad94c807874bfda8a164299534d5d62/nixos/modules/services/monitoring/ups.nix#L242-L246
  system.activationScripts.upsOwnership = lib.stringAfter [ "upsSetup" ]
    ''
      # Ensure that the UPS state directory is writable by ${upsmonUser}
      chown ${upsmonUser}:${upsmonUser} /var/state/ups
    '';

   # reference: https://github.com/networkupstools/nut/tree/master/conf
  environment.etc = {
    # all this file needs to do is exist
    upsdConf = {
      text = ''
      LISTEN 127.0.0.1
      LISTEN ::1
      '';
      target = "nut/upsd.conf";
      mode = "0440";
      group = "${upsmonUser}";
      user = "${upsmonUser}";
    };

    upsdUsers = {
      # Technically this doesn't need to match with upsmonUser, but it's nice for consistency
      text = ''
      [${upsmonUser}]
        password = ${upsmonPassword}
        upsmon master
      '';
      target = "nut/upsd.users";
      mode = "0440";
      group = "${upsmonUser}";
      user = "${upsmonUser}";
    };

    upsmonConf = {
      text = ''
        # From upsmon.conf(5):
        # This file should not be writable by the upsmon user, as it would be possible to exploit a hole, change the SHUTDOWNCMD to something malicious, then wait for upsmon to be restarted
        RUN_AS_USER ${upsmonUser}
        MONITOR ${upsname}@localhost 1 ${upsmonUser} ${upsmonPassword} master

        # If we ever need to shutdown, here's how to do it
        SHUTDOWNCMD "shutdown -h 0"
        # Require at least one UPS because it's the only one we have
        MINSUPPLIES 1
        # Poll every 15 seconds
        POLLFREQ 15
        # Except if we're on battery, poll every 5 seconds
        POLLFREQALERT 5
        # Wait up to 15 seconds for everyone to disconnect during shutdown events
        HOSTSYNC 15
        # Allow UPS to go missing for 1 minute before declaring it "dead"
        DEADTIME 60
        # If the battery needs to be replaced, generated an event every 12 hours
        RBWARNTIME 43200
        # If we can't reach any of the UPS entries in this config file, warn every 5 minutes
        NOCOMMWARNTIME 300
        # If we decide we need to shutdown, give the final warning 5 seconds before it happens
        FINALDELAY 5

        # Notification configuration
        NOTIFYMSG  ONLINE   "UPS %s is getting line power"
        NOTIFYFLAG ONLINE   SYSLOG

        NOTIFYMSG  ONBATT   "UPS %s lost line power. Running on battery"
        NOTIFYFLAG ONBATT   SYSLOG+WALL

        NOTIFYMSG  LOWBATT  "UPS %s is low on battery"
        NOTIFYFLAG LOWBATT  SYSLOG+WALL
        
        NOTIFYMSG  FSD      "UPS %s is being shutdown"
        NOTIFYFLAG FSD      SYSLOG+WALL
        
        NOTIFYMSG  COMMOK   "Communications established with UPS %s"
        NOTIFYFLAG COMMOK   SYSLOG
        
        NOTIFYMSG  COMMBAD  "Communications lost with UPS %s"
        NOTIFYFLAG COMMBAD  SYSLOG+WALL
        
        NOTIFYMSG  SHUTDOWN "System is shutting down. Goodbye <3"
        NOTIFYFLAG SHUTDOWN SYSLOG+WALL
        
        NOTIFYMSG  REPLBATT "UPS %s battery needs to be replaced"
        NOTIFYFLAG REPLBATT SYSLOG+WALL
        
        NOTIFYMSG  NOCOMM   "UPS %s cannot be contacted for monitoring"
        NOTIFYFLAG NOCOMM   SYSLOG+WALL
      '';
      target = "nut/upsmon.conf";
      mode = "0444";
      group = "root";
      user = "root";
    };
  };
}
