# ==============================================================================
# web-service.nix - NixOS module for running a stackpanel web app
#
# Declares a systemd service that runs a Nix-packaged web application.
# Designed for use on NixOS EC2 instances managed by Colmena.
#
# The binary cache is configured via accept-flake-config in the flake,
# so instances pull pre-built closures from Cachix automatically.
#
# Usage in a nixosConfiguration:
#   { inputs, ... }: {
#     imports = [ inputs.stackpanel.nixosModules.web-service ];
#     stackpanel.web = {
#       enable = true;
#       package = inputs.self.packages.x86_64-linux.web;
#       port = 80;
#     };
#   }
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.web;
in
{
  options.stackpanel.web = {
    enable = lib.mkEnableOption "stackpanel web application service";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The Nix-built web application package to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port the web server listens on.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host the web server binds to.";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "/etc/stackpanel-web.env";
      description = "Path to the environment file (populated by SSM bootstrap).";
    };

    ssmParameterPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SSM parameter path to pull environment variables from on boot.";
      example = "/stackpanel/staging/web-runtime";
    };

    ssmRegion = lib.mkOption {
      type = lib.types.str;
      default = "us-west-2";
      description = "AWS region for SSM parameter lookups.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "stackpanel-web";
      description = "User to run the web service as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "stackpanel-web";
      description = "Group to run the web service as.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = "/var/lib/stackpanel-web";
      createHome = true;
    };

    users.groups.${cfg.group} = { };

    # SSM environment bootstrap: pulls parameters into the env file on boot
    systemd.services.stackpanel-web-env = lib.mkIf (cfg.ssmParameterPath != null) {
      description = "Pull stackpanel web environment from SSM";
      wantedBy = [ "multi-user.target" ];
      before = [ "stackpanel-web.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.awscli2 pkgs.jq ];
      script = ''
        set -euo pipefail
        ENV_FILE="${cfg.envFile}"

        cat >"$ENV_FILE" <<ENVEOF
        NODE_ENV=production
        HOST=${cfg.host}
        PORT=${toString cfg.port}
        ENVEOF

        aws ssm get-parameters-by-path \
          --path "${cfg.ssmParameterPath}" \
          --recursive \
          --with-decryption \
          --output json \
          --region "${cfg.ssmRegion}" \
        | jq -r '.Parameters[] | "\(.Name | split("/")[-1])=\(.Value)"' >>"$ENV_FILE"

        chmod 600 "$ENV_FILE"
        chown ${cfg.user}:${cfg.group} "$ENV_FILE"
      '';
    };

    systemd.services.stackpanel-web = {
      description = "stackpanel web application";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optional (cfg.ssmParameterPath != null) "stackpanel-web-env.service";
      wants = [ "network-online.target" ];
      requires = lib.optional (cfg.ssmParameterPath != null) "stackpanel-web-env.service";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/${cfg.package.pname or cfg.package.name or "web"}";
        Restart = "always";
        RestartSec = 5;
        EnvironmentFile = lib.optional (cfg.envFile != null) cfg.envFile;
        Environment = [
          "NODE_ENV=production"
          "HOST=${cfg.host}"
          "PORT=${toString cfg.port}"
        ];
      };
    };

    # Trust the binary cache so nixos-rebuild can pull closures
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      accept-flake-config = true;
      extra-substituters = [ "https://darkmatter.cachix.org" ];
      extra-trusted-public-keys = [
        "darkmatter.cachix.org-1:7R5qAiOVHxDpFy7yguECfC1JqVDgMdckGc+CDKk2pWA="
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
