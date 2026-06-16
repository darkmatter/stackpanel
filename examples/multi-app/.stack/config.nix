# ==============================================================================
# .stack/config.nix
#
# Stackpanel configuration for the multi-app monorepo example.
# See the full options reference in the main stackpanel repo:
#   nix/stackpanel/core/options/
# ==============================================================================
{
  enable = true;
  name = "example-multi-app";
  github = "acme/example-multi-app";

  cli.enable = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;

  # Shared development services (postgres, redis, minio, ...).
  # Start them after entering the shell with `dev`.
  globalServices = {
    enable = true;
    postgres.enable = true;
    redis.enable = true;
  };

  apps = {
    web = {
      name = "Web";
      path = "apps/web";
      domain = "web";

      # Colmena/NixOS deployment mapping (disabled here for the example).
      deploy = {
        enable = true;
        targets = [ "edge" ];
        role = "frontend";
      };
    };

    server = {
      name = "Server";
      path = "apps/server";
      domain = "api";

      deploy = {
        enable = true;
        targets = [ "api" ];
        role = "backend";
      };
    };

    docs = {
      name = "Docs";
      path = "apps/docs";
      domain = "docs";
    };
  };

  colmena = {
    enable = false;
    machineSource = "infra";
  };
}
