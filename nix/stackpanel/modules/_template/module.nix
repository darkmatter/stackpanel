# ==============================================================================
# module.nix - Module Implementation
#
# This is a standard NixOS-style module that defines options and configuration.
# For complex modules, you can split this into options.nix and config.nix.
#
# The module should:
# 1. Define options under stackpanel.modules.<id>.*
# 2. Define per-app options via appModules if needed
# 3. Implement config = lib.mkIf cfg.enable { ... }
# 4. Declare checks under stackpanel.doctor.<id> (build scope certifies the
#    module for CI; runtime/repo scope feed `stack doctor` and the UI)
#
# For large modules with many checks, consider splitting checks into checks.nix
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  # Import metadata for reference
  meta = import ./meta.nix;

  # Shorthand for this module's config
  cfg = config.stackpanel.modules.${meta.id};

  # Shorthand for stackpanel config
  sp = config.stackpanel;

  # ---------------------------------------------------------------------------
  # Per-app options module (if this module adds per-app configuration)
  # ---------------------------------------------------------------------------
  # Uncomment and customize if you need per-app options:
  #
  # appModule = { lib, name, ... }: {
  #   options.myModule = {
  #     enable = lib.mkEnableOption "Enable ${meta.name} for this app";
  #     # Add more per-app options here
  #   };
  # };
  #
  # Then add to config below:
  #   stackpanel.appModules = [ appModule ];

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.modules.${meta.id} = {
    enable = lib.mkEnableOption meta.description;

    # Add module-specific options here
    # Example:
    # package = lib.mkOption {
    #   type = lib.types.package;
    #   default = pkgs.my-package;
    #   description = "The package to use";
    # };
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # -------------------------------------------------------------------------
    # Module Registration - Required for UI discovery. UNGUARDED on purpose:
    # `stackpanel.modules` is one submodule-typed option, so guarding this with
    # `mkIf cfg.enable` would have to evaluate modules.<id>.enable to merge the
    # very option that provides it (infinite recursion). Metadata is not
    # behavior; the enable flag is the user's input, never set here.
    # -------------------------------------------------------------------------
    {
      stackpanel.modules.${meta.id} = {
        # Only the display fields: meta.nix also carries discovery data
        # (id, tags, requires, features, ...) that this option does not accept.
        meta = {
          inherit (meta)
            name
            description
            icon
            category
            author
            version
            homepage
            ;
        };
        source.type = "builtin";
        inherit (meta) features;
        flakeInputs = meta.flakeInputs or [ ];
        inherit (meta) tags;
        inherit (meta) priority;
        healthcheckModule = meta.id;
      };
    }

    # Everything below is behavior and is guarded.
    (lib.mkIf (sp.enable && cfg.enable) {
      # -------------------------------------------------------------------------
      # Packages - Add packages to devshell
      # -------------------------------------------------------------------------
      # stackpanel.devshell.packages = [ pkgs.my-package ];

      # -------------------------------------------------------------------------
      # Files - Generate configuration files
      # -------------------------------------------------------------------------
      # stackpanel.files.entries = {
      #   "path/to/config.json" = {
      #     type = "text";
      #     text = builtins.toJSON { key = "value"; };
      #     description = "Configuration file for ${meta.name}";
      #     source = meta.id;
      #   };
      # };

      # -------------------------------------------------------------------------
      # Scripts - Add shell commands
      # -------------------------------------------------------------------------
      # stackpanel.scripts = {
      #   my-command = {
      #     exec = ''
      #       echo "Hello from ${meta.name}"
      #     '';
      #     description = "Run ${meta.name}";
      #   };
      # };

      # =========================================================================
      # Doctor checks - one surface, three scopes
      # =========================================================================
      # `stackpanel.doctor.<module>.<name>` replaces the separate moduleChecks
      # (build) and healthchecks (runtime) surfaces. Pick a scope per check:
      #   - build:   a derivation that must build; run by `nix flake check` and
      #              `stack doctor --build`. `eval` + `packages` certify the module.
      #   - runtime: machine state outside the repo (tools, caches, services);
      #              shown as traffic lights in the UI, run by `stack doctor`.
      #              May carry a `fixCommand` hint - the doctor never runs it.
      #   - repo:    an observation about the repository; run by `stack doctor`.
      #              Repo state is fixed by reconciliation, never by a check.
      # The deprecated `stackpanel.moduleChecks` / `stackpanel.healthchecks.modules`
      # spellings still work and write into this option.
      # -------------------------------------------------------------------------
      stackpanel.doctor.${meta.id} = {
        displayName = meta.name;

        # REQUIRED for certification: the module evaluates without errors
        eval = {
          scope = "build";
          description = "${meta.name} module evaluates correctly";
          required = true;
          derivation = pkgs.runCommand "${meta.id}-eval-check" { } ''
            echo "✓ Module ${meta.name} evaluates successfully"
            touch $out
          '';
        };

        # REQUIRED for certification: required packages are available
        packages = {
          scope = "build";
          description = "${meta.name} packages are available";
          required = true;
          derivation =
            pkgs.runCommand "${meta.id}-packages-check"
              {
                # nativeBuildInputs = [ pkgs.my-package ];
              }
              ''
                # my-package --version
                echo "✓ All required packages available"
                touch $out
              '';
        };

        # Runtime probe: shown in the UI, run in the devshell
        installed = {
          scope = "runtime";
          description = "${meta.name} is installed and accessible";
          script = ''
            # command -v my-command >/dev/null 2>&1 && my-command --version
            echo "Check not implemented"
            exit 0
          '';
          severity = "critical";
          timeout = 5;
          # fixCommand = "nix develop";   # hint for the user when this fails
        };

        # Repo observation: something about the checkout itself
        # config-valid = {
        #   scope = "repo";
        #   description = "Configuration is valid";
        #   script = ''
        #     test -f "$STACKPANEL_ROOT/path/to/config.json"
        #   '';
        #   severity = "warning";
        # };
      };
    })
  ];
}
