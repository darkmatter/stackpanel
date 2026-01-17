# ==============================================================================
# tasks.nix
# type: sp-task
#
# Workspace-level task definitions (not app-specific).
# Each task matches the proto Task shape with exec, description, cwd, env.
# ==============================================================================
{
  # Development tasks
  dev = {
    exec = "turbo run dev";
    description = "Start all development servers";
    env = { };
  };

  build = {
    exec = "turbo run build";
    description = "Build all packages and apps";
    env = { };
  };

  # Testing tasks
  test = {
    exec = "turbo run test";
    description = "Run all tests";
    env = { };
  };

  "test:watch" = {
    exec = "turbo run test:watch";
    description = "Run tests in watch mode";
    env = { };
  };

  "test:coverage" = {
    exec = "turbo run test:coverage";
    description = "Run tests with coverage report";
    env = { };
  };

  # Code quality tasks
  lint = {
    exec = "turbo run lint";
    description = "Run linter across all packages";
    env = { };
  };

  format = {
    exec = "bun run prettier --write .";
    description = "Format all code";
    env = { };
  };

  typecheck = {
    exec = "turbo run typecheck";
    description = "Run TypeScript type checker";
    env = { };
  };

  # Database tasks
  "db:migrate" = {
    exec = "bun run drizzle-kit migrate";
    description = "Run database migrations";
    cwd = "apps/server";
    env = { };
  };

  "db:push" = {
    exec = "bun run drizzle-kit push";
    description = "Push schema changes to database";
    cwd = "apps/server";
    env = { };
  };

  "db:studio" = {
    exec = "bun run drizzle-kit studio";
    description = "Open Drizzle Studio database GUI";
    cwd = "apps/server";
    env = { };
  };

  # Code generation tasks
  "generate:proto" = {
    exec = "./generate.sh";
    description = "Generate TypeScript and Go types from proto schemas";
    cwd = "packages/proto";
    env = { };
  };

  "generate:types" = {
    exec = "./nix/stackpanel/core/generate-types.sh";
    description = "Generate TypeScript types from Nix schemas";
    env = { };
  };

  # Cleanup tasks
  clean = {
    exec = "turbo run clean && rm -rf node_modules/.cache";
    description = "Clean build artifacts and caches";
    env = { };
  };
}
