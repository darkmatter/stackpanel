# ==============================================================================
# commands.nix
#
# Workspace-level command definitions for tooling configuration.
# Each command matches the proto Command shape with package, bin, args, env, cwd.
# ==============================================================================
{
  # Linting
  eslint = {
    package = "eslint";
    args = [ "." ];
    config-path = "eslint.config.js";
    config-arg = [ "--config" ];
    env = { };
  };

  biome = {
    package = "biome";
    bin = "biome";
    args = [
      "check"
      "."
    ];
    env = { };
  };

  # Formatting
  prettier = {
    package = "prettier";
    args = [
      "--write"
      "."
    ];
    config-path = ".prettierrc";
    env = { };
  };

  # Type checking
  tsc = {
    package = "typescript";
    bin = "tsc";
    args = [ "--noEmit" ];
    env = { };
  };

  # Testing
  vitest = {
    package = "vitest";
    args = [ "run" ];
    env = { };
  };

  "vitest:watch" = {
    package = "vitest";
    args = [ ];
    env = { };
  };

  "vitest:coverage" = {
    package = "vitest";
    args = [
      "run"
      "--coverage"
    ];
    env = { };
  };

  # Build tools
  turbo = {
    package = "turbo";
    args = [ ];
    env = { };
  };

  # Database
  drizzle-kit = {
    package = "drizzle-kit";
    args = [ ];
    cwd = "apps/server";
    env = { };
  };

  # Go tools
  go-build = {
    package = "go";
    bin = "go";
    args = [
      "build"
      "-o"
      "stackpanel"
      "./cmd/stackpanel"
    ];
    cwd = "apps/stackpanel-go";
    env = { };
  };

  go-test = {
    package = "go";
    bin = "go";
    args = [
      "test"
      "./..."
    ];
    cwd = "apps/stackpanel-go";
    env = { };
  };

  # Proto generation
  buf = {
    package = "buf";
    args = [ "generate" ];
    cwd = "packages/proto";
    env = { };
  };
}
