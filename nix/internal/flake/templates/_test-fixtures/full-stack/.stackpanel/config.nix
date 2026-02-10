# Test Fixture: Full Stack
# Tests all features enabled
{
  enable = true;
  name = "test-full-stack";

  # Disable features that require runtime (for CI testing)
  cli.enable = false;
  theme.enable = false;
  ide.enable = false;
  motd.enable = false;

  # =====================================================
  # Multiple apps with different configurations
  # =====================================================
  apps = {
    # Web app with React/TypeScript
    web = {
      path = "apps/web";
      linting.oxlint = {
        enable = true;
        plugins = [ "react" "typescript" ];
        rules = {
          "no-console" = "warn";
          "no-debugger" = "error";
        };
        paths = [ "src" ];
      };
    };

    # Server app with Node.js
    server = {
      path = "apps/server";
      linting.oxlint = {
        enable = true;
        plugins = [ "typescript" ];
        rules = {
          "no-console" = "off"; # Allow console in server
        };
        paths = [ "src" ];
      };
    };

    # Documentation app
    docs = {
      path = "apps/docs";
      linting.oxlint = {
        enable = true;
        plugins = [ "typescript" ];
        paths = [ "src" ];
      };
    };
  };
}
