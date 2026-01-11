# ==============================================================================
# commands.nix
#
# Standalone command definitions that can be linked to apps.
# Commands are defined once and referenced by ID in app definitions.
# ==============================================================================
{
  # Development commands
  dev = {
    name = "dev";
    description = "Start development server with hot reload";
    category = "development";
  };

  build = {
    name = "build";
    description = "Build for production";
    category = "build";
  };

  start = {
    name = "start";
    description = "Start production server";
    category = "production";
  };

  # Testing commands
  test = {
    name = "test";
    description = "Run test suite";
    category = "testing";
  };

  "test:watch" = {
    name = "test:watch";
    description = "Run tests in watch mode";
    category = "testing";
  };

  "test:coverage" = {
    name = "test:coverage";
    description = "Run tests with coverage report";
    category = "testing";
  };

  # Code quality commands
  lint = {
    name = "lint";
    description = "Run linter";
    category = "quality";
  };

  format = {
    name = "format";
    description = "Format code";
    category = "quality";
  };

  typecheck = {
    name = "typecheck";
    description = "Run type checker";
    category = "quality";
  };

  # Database commands
  "db:migrate" = {
    name = "db:migrate";
    description = "Run database migrations";
    category = "database";
  };

  "db:seed" = {
    name = "db:seed";
    description = "Seed database with sample data";
    category = "database";
  };

  "db:reset" = {
    name = "db:reset";
    description = "Reset database (drop, create, migrate, seed)";
    category = "database";
  };

  "db:studio" = {
    name = "db:studio";
    description = "Open database studio/GUI";
    category = "database";
  };

  # Deployment commands
  deploy = {
    name = "deploy";
    description = "Deploy to production";
    category = "deployment";
  };

  "deploy:staging" = {
    name = "deploy:staging";
    description = "Deploy to staging environment";
    category = "deployment";
  };

  # Code generation commands
  generate = {
    name = "generate";
    description = "Run code generators";
    category = "codegen";
  };

  "generate:types" = {
    name = "generate:types";
    description = "Generate TypeScript types";
    category = "codegen";
  };
}
