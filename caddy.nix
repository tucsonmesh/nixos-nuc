
{ config, lib, pkgs, modulesPath, ... }:

 
let
  unstablePkgs = import ( fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz ) { config = config.nixpkgs.config; };
in
{
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
      (restrict-vpn) {
        @iswireguard remote_ip 10.100.0.1/24
        @istailscale remote_ip 100.64.0.0/10

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
      		import restrict-vpn localhost:8080
      	}

      	redir /librenms /librenms/
      	handle_path /librenms/* {
      		import restrict-vpn localhost:8081
      	}

      	redir /speedtest /speedtest/
      	handle_path /speedtest/* {
      		# no wireguard restriction
      		reverse_proxy localhost:8082
      	}

        handle * {
          file_server
          root * ${
            pkgs.runCommand "wild-nix-caddy-directory" {} ''
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

      listenAddresses = [ "0.0.0.0" ];
    };

    virtualHosts.":8080" = {
      extraConfig = ''
      	root * /var/lib/mapgen/website/deploy

      	file_server {
      		hide /var/lib/mapgen/website/deploy/.git*
      	}
      '';

      listenAddresses = [ "127.0.0.1" "::1" ];
    };
  };
}
