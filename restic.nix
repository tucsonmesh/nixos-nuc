{ config, lib, pkgs, modulesPath, ... }:

{
  environment.systemPackages = with pkgs; [
    restic
  ];

  services.restic.backups = {
    remotebackup = {
      extraOptions = [
        "sftp.command='sshpass -f /etc/nixos/secrets/restic/restic-sftp-pass ssh mesh-nuc@100.67.108.110 -s sftp'"
      ];
      repository = "sftp:mesh-nuc@100.67.108.110:/mesh-backup/nixos-nuc";
      initialize = true;
      passwordFile = "/etc/nixos/secrets/restic/restic-repo-pass";

      paths = [
        "/home"
        "/var/lib/mapgen"
        "/etc/nixos"
        "/root"
        "/dumbledore"
      ];

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 8"
      ];

      timerConfig = {
        OnCalendar = "04:20";
      };
    };
  };

  # append sshpass to the path of the generated unit service config
  systemd.services.restic-backups-remotebackup.path = [ pkgs.sshpass ];
}
