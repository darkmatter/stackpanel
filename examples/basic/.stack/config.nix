{
  enable = true;
  name = "example-basic";
  github = "acme/example-basic";

  cli.enable = true;
  theme.enable = true;
  ide.enable = true;
  ide.vscode.enable = true;

  apps = {
    web = {
      name = "Web";
      description = "Frontend app";
      path = "apps/web";
      type = "bun";
      domain = "web";
    };
  };
}
