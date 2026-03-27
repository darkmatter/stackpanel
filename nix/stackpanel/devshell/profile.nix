# ==============================================================================
# profile.nix
#
# Unified package profile for devshell environments.
#
# Creates a single Nix store derivation (via pkgs.buildEnv) that merges all
# devshell packages into a unified directory tree. This replaces 90+ individual
# PATH entries with a single entry, resulting in:
#
#   - Faster command resolution (shorter PATH)
#   - Cleaner environment (easier to inspect)
#   - GC root protection (symlinked to .stack/state/profile)
#   - Easy introspection: ls .stack/state/profile/bin/
#
# Inspired by devenv's .devenv/profile approach.
#
# The profile is built at Nix evaluation time and symlinked into the project
# at shell entry. Individual binaries inside the profile are symlinks back to
# their original store paths, so there is no file copying:
#
#   .stack/state/profile/
#   ├── bin/
#   │   ├── node -> /nix/store/…-nodejs-22.22.0/bin/node
#   │   ├── bun  -> /nix/store/…-bun-1.3.3/bin/bun
#   │   ├── go   -> /nix/store/…-go-1.25.6/bin/go
#   │   └── …
#   └── share/
#       ├── man/              # merged man pages
#       ├── bash-completion/  # merged completions
#       └── …
#
# Usage:
#   # Enabled by default. To disable:
#   stackpanel.devshell.profile.enable = false;
#
#   # Customise what gets linked into the profile:
#   stackpanel.devshell.profile.pathsToLink = [ "/" ];
#
# Integration:
#   The flake-level shell builders (nix/flake/default.nix and
#   nix/internal/flake/default.nix) check devshellOutputs.profile and, when
#   enabled, pass `[ profile ] ++ devenvPackages` to mkShell instead of the
#   full individual package list.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell;
  profileCfg = cfg.profile;
  util = config.stackpanel.util;

  # All packages contributed by stackpanel modules (scripts, CLI, languages, …)
  modulePackages = cfg.packages;
  packageCount = builtins.length modulePackages;

  # De-duplicate while preserving order (first occurrence wins on collision).
  uniquePackages = lib.unique modulePackages;

  # ── Build the unified profile ────────────────────────────────────────────
  profile = pkgs.buildEnv {
    name = "stackpanel-profile";
    paths = uniquePackages;
    pathsToLink = profileCfg.pathsToLink;

    # Multiple packages may ship the same binary (e.g. coreutils' `env` vs
    # another provider).  Letting the first package win matches devenv's
    # behaviour and avoids noisy build failures.
    ignoreCollisions = true;

    # Pull in extra outputs so that `man git` etc. work from the profile.
    extraOutputsToInstall = profileCfg.extraOutputsToInstall;
  };
in
{
  # ── Options ────────────────────────────────────────────────────────────────
  options.stackpanel.devshell.profile = {
    enable = lib.mkEnableOption "unified package profile (single PATH entry instead of many)" // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The built profile derivation.

        This is a `pkgs.buildEnv` that merges every devshell package into one
        directory tree using symlinks.  The flake shell builder uses this as a
        single `packages` entry for `mkShell`, collapsing 90+ individual PATH
        entries down to one.
      '';
    };

    pathsToLink = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/bin"
        "/share"
      ];
      description = ''
        Subdirectories to link from each package into the profile.

        The default links `/bin` (executables) and `/share` (man pages, shell
        completions, locale data, etc.).  Set to `[ "/" ]` to link everything
        — including `lib/`, `include/`, `etc/` — at the cost of a larger
        profile derivation.
      '';
      example = [ "/" ];
    };

    extraOutputsToInstall = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "man" ];
      description = ''
        Additional Nix package outputs to include in the profile.
        Common values: "man", "doc", "info".
      '';
      example = [
        "man"
        "doc"
      ];
    };
  };

  # ── Config ─────────────────────────────────────────────────────────────────
  config = lib.mkIf (config.stackpanel.enable && profileCfg.enable && modulePackages != [ ]) {
    # Expose the built derivation for the flake shell builders.
    stackpanel.devshell.profile.package = profile;

    # Symlink the profile into the state directory on every shell entry.
    # This serves two purposes:
    #   1. GC root – the symlink from the worktree keeps the store path alive
    #      across `nix-collect-garbage` runs.
    #   2. Introspection – `ls .stack/state/profile/bin/` instantly shows
    #      every command available in the devshell.
    stackpanel.devshell.hooks.after = [
      ''
        if [[ -n "''${STACKPANEL_STATE_DIR:-}" ]]; then
          ${util.log.debug "profile: symlinking ${toString packageCount}-package profile to state dir"}
          ln -sfn "${profile}" "$STACKPANEL_STATE_DIR/profile"
        fi
      ''
    ];
  };
}
