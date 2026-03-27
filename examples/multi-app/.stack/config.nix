{
  enable = true;
  name = "example-multi-app";
  github = "acme/example-multi-app";

  cli.enable = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;

  globalServices = {
    enable = true;
    postgres.enable = true;
    redis.enable = true;
  };

  apps = {
    web = {
      name = "Web";
      path = "apps/web";
      type = "bun";
      domain = "web";

      deploy = {
        enable = true;
        targets = [ "edge" ];
        role = "frontend";
      };
    };

    server = {
      name = "Server";
      path = "apps/server";
      type = "bun";
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
      type = "bun";
      domain = "docs";
    };
  };

  colmena = {
    enable = false;
    machineSource = "infra";
  };
}
