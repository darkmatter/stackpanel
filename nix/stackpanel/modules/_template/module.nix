# ==============================================================================
# module.nix - Module Implementation
#
# This is a standard NixOS-style module that defines options and configuration.
# For complex modules, you can split this into options.nix and config.nix.
#
# The module should:
# 1. Register metadata under stackpanel.modules.<id> (enable is provided by the schema)
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
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # -------------------------------------------------------------------------
    # Module Registration - Required for UI discovery. UNGUARDED on purpose:
    # Declare identity even when disabled. Only generated outputs depend on
    # the enable flag; discovery must never depend on its own activation.
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
      # stackpanel.modulePackages.${meta.id} = [ pkgs.my-package ];

      # -------------------------------------------------------------------------
      # Files - Generate configuration files
      # -------------------------------------------------------------------------
      # stackpanel.files.entries = {
      #   "path/to/config.json" = {
      #     type = "text";
      #     text = builtins.toJSON { key = "value"; };
      #     description = "Configuration file for ${meta.name}";
      #     source = meta.id;
      #     module = meta.id;
      #   };
      # };

      # -------------------------------------------------------------------------
      # Scripts - Add shell commands
      # -------------------------------------------------------------------------
      # stackpanel.scripts = {
      #   my-command = {
      #     module = meta.id;
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
      # -------------------------------------------------------------------------
      stackpanel.doctor.${meta.id} = {
        displayName = meta.name;

        # REQUIRED for certification: the module evaluates without errors
        eval = {
          module = meta.id;
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
          module = meta.id;
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
          module = meta.id;
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
