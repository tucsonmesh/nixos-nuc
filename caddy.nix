
{ config, lib, pkgs, modulesPath, ... }:

 
let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
in
{
  # mapgen and caddy users share the webbies group for sharing access to deployed map contents
  users.users.caddy.extraGroups = [ "webbies" ];

  # restart the unit when changed rather than reloading. reloading never works
  systemd.services.caddy.restartIfChanged = true;
  systemd.services.caddy.reloadIfChanged = false;

  services.caddy = {
    enable = true;
    resume = false;
    acmeCA = null;
    package = unstablePkgs.caddy;

    logFormat = ''
      level INFO
      format console
    '';

    globalConfig = ''
     	admin off
    	persist_config off
      auto_https off
    '';

    extraConfig = ''
      # special helper for declaring wireguard-or-tailscale-restricted reverse-proxied services
      (restricted-ips) {
        @iswireguard remote_ip 10.100.0.1/24
        @istailscale remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48

        # if remote IP is good, allow through to the specified
        handle @iswireguard {
          reverse_proxy "{args[0]}"
        }
        handle @istailscale {
          reverse_proxy "{args[0]}"
        }

      	# otherwise, abort
      	handle {
      		abort
      	}
      }
    '';

    virtualHosts.":80" = {
      extraConfig = ''
        handle_errors {
          respond "ERROR: {err.status_code} {err.status_text}"
        }

      	redir /map /map/
      	handle_path /map/* {
          # no wireguard/vpn restriction
          reverse_proxy localhost:8080
      	}

      	redir /librenms /librenms/
      	handle_path /librenms/* {
          # wireguard/vpn restriction
          import restricted-ips localhost:8081
      	}

      	redir /speedtest /speedtest/
      	handle_path /speedtest/* {
          # no wireguard/vpn restriction
      		reverse_proxy localhost:8082
      	}

        handle * {
          file_server
          root * ${
            pkgs.runCommand "basic-caddy-site-gen" {} ''
              mkdir "$out"
              cat <<EOF > "$out/index.html"
              <!DOCTYPE html>
              <html>
                <head>
                  <meta name="viewport" content="width=device-width; height=device-height;"></meta>
                  <title>Turnip Turns Up</title>
                </head>
                <body>
                  <img alt="https://media.tenor.com/AzJxBJdHlF4AAAAd/turnip-turns-up-turnipup.gif" src="https://media.tenor.com/AzJxBJdHlF4AAAAd/turnip-turns-up-turnipup.gif" style="text-align: center; display: block; margin: auto;"></img>
                </body>
              </html>
              EOF
            ''
          }
        }
      '';

      listenAddresses = [ "0.0.0.0" "::" ];
    };

    virtualHosts.":8080" = {
      extraConfig = ''
      	root * /var/lib/caddy/map.js/

      	file_server {
      		hide /var/lib/caddy/map.js/.git*
      	}
      '';

      listenAddresses = [ "127.0.0.1" "::1" ];
    };
  };
}
