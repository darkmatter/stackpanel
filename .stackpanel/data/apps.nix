# ==============================================================================
# apps.nix - Application configuration
#
# Define your applications here. Commands (dev, build, test, lint, format)
# are automatically provided based on the app type (bun, go, etc.).
#
# Flake outputs:
#   nix build .#<app>       - Build for production
#   nix run .#<app>-dev     - Run dev server
#   nix run .#<app>         - Run production app
#   nix flake check         - Run all tests and lints
# ==============================================================================
{
  docs = {
    name = "docs";
    description = "Documentation site";
    path = "apps/docs";
    type = "bun";
    domain = "docs";
    port = 3002;
    environments = {
      dev = {
        name = "dev";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
      prod = {
        name = "prod";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
      staging = {
        name = "staging";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
    };
    variables = { };
  };

  server = {
    name = "server";
    description = "Backend API server";
    path = "apps/server";
    type = "bun";
    port = 3001;
    variables = { };
  };

  stackpanel-go = {
    name = "stackpanel";
    description = "Stackpanel CLI and agent (Go)";
    path = "apps/stackpanel-go";
    type = "go";
    variables = { };
  };

  web = {
    name = "web";
    description = "Main web application (Next.js)";
    path = "apps/web";
    type = "bun";
    domain = "stackpanel";
    port = 3000;
    environments = {
      dev = {
        name = "dev";
        variables = {
          DOCS-PORT = {
            key = "DOCS_PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
          OPENAI-API-KEY = {
            key = "OPENAI_API_KEY";
            type = 2;
            variable-id = "openai-api-key";
          };
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/web/port";
          };
        };
      };
    };
    variables = { };
    commands = {
      dev = { command = "bun run -F web dev"; };
    };
  };
}
