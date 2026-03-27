# ==============================================================================
# reload.nix
#
# Hot-reload integration: background shell rebuild with PTY swap.
#
# When enabled, the `stackpanel-reload` Rust binary is added to the devshell
# and a `shell` script is registered that wraps `nix develop --impure` with
# file watching and automatic PTY hot-swap on rebuild success.
#
# Usage in .stack/config.nix:
#
#   stackpanel.devshell.reload.enable = true;
#
# Then enter the shell via:
#
#   stackpanel shell      # via the registered script
#   # or directly:
#   stackpanel-reload     # uses nix develop --impure by default
#
# Options:
#   stackpanel.devshell.reload.enable         (bool, default: false)
#   stackpanel.devshell.reload.watchPaths     (list of strings, default: standard set)
#   stackpanel.devshell.reload.debounceMs     (int, default: 500)
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell.reload;
  spCfg = config.stackpanel;

  # Build the stackpanel-reload binary from the Rust crate.
  # Uses rustPlatform.buildRustPackage which is available in all nixpkgs.
  stackpanel-reload = pkgs.rustPlatform.buildRustPackage {
    pname = "stackpanel-reload";
    version = "0.1.0";

    src = lib.cleanSource ../../../apps/stackpanel-reload;

    cargoLock.lockFile = ../../../apps/stackpanel-reload/Cargo.lock;

    # Disable tests during the Nix build (they require a real TTY).
    doCheck = false;

    meta = {
      description = "Background shell rebuild with PTY hot-swap for stackpanel";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };

  # The default watch paths (relative to project root).
  defaultWatchPaths = [
    "flake.nix"
    "flake.lock"
    "devenv.nix"
    "devenv.yaml"
    ".stack"
    "nix"
  ];

  # Resolve watch paths to their full project-root-relative form for the CLI.
  resolvedWatchPaths =
    if cfg.watchPaths != [ ]
    then cfg.watchPaths
    else defaultWatchPaths;

  # Arguments passed to stackpanel-reload when `stackpanel shell` is invoked.
  reloadArgs = lib.concatStringsSep " " (
    map (p: "--watch ${lib.escapeShellArg p}") resolvedWatchPaths
    ++ [ "--debounce ${toString cfg.debounceMs}" ]
  );

in
{
  # ── Options ──────────────────────────────────────────────────────────────────

  options.stackpanel.devshell.reload = {
    enable = lib.mkEnableOption "PTY hot-swap shell reload" // {
      default = false;
    };

    watchPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths to watch for changes (relative to project root).
        Defaults to the standard set: flake.nix, flake.lock, devenv.nix,
        devenv.yaml, .stack/, nix/.

        Set this to override the default watch paths entirely.
      '';
      example = [
        "flake.nix"
        "flake.lock"
        ".stack/config.nix"
      ];
    };

    debounceMs = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = ''
        Debounce delay in milliseconds after the last file change before
        triggering a background rebuild. Lower values = faster response;
        higher values = fewer spurious rebuilds from editor atomic-saves.
      '';
      example = 300;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = stackpanel-reload;
      description = "The stackpanel-reload binary package.";
      readOnly = true;
    };
  };

  # ── Config ───────────────────────────────────────────────────────────────────

  config = lib.mkIf (spCfg.enable && cfg.enable) {
    # Add the binary to the devshell.
    stackpanel.devshell.packages = [ cfg.package ];

    # Register the `shell` command so `stackpanel shell` (or `x shell`) works.
    stackpanel.scripts."shell" = {
      exec = ''
        exec ${cfg.package}/bin/stackpanel-reload \
          ${reloadArgs} \
          -- nix develop --impure --command "$SHELL"
      '';
      description = "Enter devshell with automatic hot-reload on config changes";
    };

    # Add a hint to the MOTD.
    stackpanel.motd.commands = [
      {
        name = "shell";
        description = "Enter devshell with hot-reload (stackpanel-reload)";
      }
    ];
  };
}
