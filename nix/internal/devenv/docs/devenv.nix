# ==============================================================================
# docs/devenv.nix
#
# Devenv module for the documentation site (apps/docs).
# Configures JavaScript/Bun development environment for the docs app.
#
# Features:
#   - Enables JavaScript language support with Bun runtime
#   - Configures automatic dependency installation
#   - Defines 'docs' process for documentation dev server
#   - Provides 'docs:install' task for dependency installation
#
# Process: `bun run dev` running in apps/docs directory
# Profile: profiles.docs available for docs-only development
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # config.devenv.root is set by devenv and points to the project root
  # Fall back to "." if not available (shouldn't happen in practice)
  root = if config.git.root != null then config.git.root else config.devenv.root or ".";
in
{
  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.docs = {
    exec = ''
      ${pkgs.bun}/bin/bun run dev
    '';
    cwd = "${root}/apps/docs";
  };

  tasks."docs:install" = {
    exec = ''
      set -euo pipefail
      echo "📦 Installing docs dependencies..."
      cd "${root}/apps/docs"
      ${pkgs.bun}/bin/bun install
    '';
  };

  profiles.docs.module = { };
  enterShell = ''
    echo "📚 Starting docs development server..."
  '';
}
