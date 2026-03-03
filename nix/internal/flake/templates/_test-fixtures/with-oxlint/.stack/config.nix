# Test Fixture: With OxLint
# Tests oxlint module with a web app
{
  enable = true;
  name = "test-with-oxlint";

  cli.enable = false;
  theme.enable = false;
  ide.enable = false;
  motd.enable = false;

  # Define an app with oxlint enabled
  apps.web = {
    path = "apps/web";
    linting.oxlint = {
      enable = true;
      plugins = [ "react" "typescript" ];
      rules = {
        "no-console" = "warn";
      };
      paths = [ "src" ];
    };
  };
}
