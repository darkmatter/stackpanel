# ==============================================================================
# apps.nix
#
# Application definitions with references to commands and variables.
# Apps link to standalone entities defined in commands.nix and variables.nix.
#
# Fields:
#   - name: Display name for the app
#   - path: Path to app directory relative to project root
#   - type: App type (bun, go, python, rust, etc.)
#   - port: Development server port (optional)
#   - domain: Local development domain (optional)
#   - commands: List of command IDs from commands.nix
#   - variables: List of variable IDs from variables.nix
#   - description: Brief description of what the app does
# ==============================================================================
{
  web = {
    name = "Web Application";
    description = "Main frontend application built with React and TanStack";
    path = "apps/web";
    type = "bun";
    port = 3000;
    domain = "stackpanel.localhost";
    commands = [
      "dev"
      "build"
      "start"
      "test"
      "lint"
      "format"
      "typecheck"
    ];
    variables = [
      "NODE_ENV"
      "PORT"
      "APP_URL"
      "API_URL"
      "DATABASE_URL"
      "AUTH_SECRET"
      "STRIPE_PUBLISHABLE_KEY"
    ];
  };

  api = {
    name = "API Server";
    description = "Backend API server built with Go";
    path = "apps/api";
    type = "go";
    port = 8080;
    domain = "api.localhost";
    commands = [
      "dev"
      "build"
      "start"
      "test"
      "lint"
      "db:migrate"
      "db:seed"
      "generate"
    ];
    variables = [
      "NODE_ENV"
      "PORT"
      "DATABASE_URL"
      "REDIS_URL"
      "AUTH_SECRET"
      "STRIPE_SECRET_KEY"
      "STRIPE_WEBHOOK_SECRET"
      "LOG_LEVEL"
    ];
  };

  docs = {
    name = "Documentation";
    description = "Project documentation site";
    path = "apps/docs";
    type = "bun";
    port = 3001;
    domain = "docs.localhost";
    commands = [
      "dev"
      "build"
      "start"
    ];
    variables = [
      "NODE_ENV"
    ];
  };

  cli = {
    name = "CLI Tool";
    description = "Command-line interface for project management";
    path = "apps/stackpanel-go";
    type = "go";
    commands = [
      "build"
      "test"
      "lint"
      "format"
    ];
    variables = [ ];
  };
}
