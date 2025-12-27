# ==============================================================================
# web/devenv.nix
#
# Devenv module for the web application (apps/web).
# Configures JavaScript/Bun development environment and defines the web process.
#
# Features:
#   - Enables JavaScript language support with Bun runtime
#   - Configures automatic dependency installation
#   - Defines 'web' process for development server
#
# Process: `bun dev` running in apps/web directory
# Profile: profiles.web available for web-only development
# ==============================================================================

{ pkgs, lib, config, ...}:
let
  # config.devenv.root is set by devenv and points to the project root
  # Fall back to "." if not available (shouldn't happen in practice)
  root = if config.git.root != null then config.git.root else config.devenv.root or ".";
in {
  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.web = {
    # exec = ''
    #   ${pkgs.bun}/bin/bun run dev
    # '';
    exec = "${pkgs.bun}/bin/bun dev";
    cwd = "${root}/apps/web";
  };
  profiles.web.module = {};
}