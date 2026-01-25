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
# 4. Define flake checks for CI (required for certification)
# 5. Define health checks for runtime monitoring
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
  config = lib.mkIf (sp.enable && cfg.enable) {
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
    # Flake Checks (CI) - Run with `nix flake check`
    # =========================================================================
    # These checks run in CI and are required for module certification.
    # Categories:
    #   - eval: Module evaluates (REQUIRED for certification)
    #   - packages: Dependencies available (REQUIRED for certification)
    #   - config: Config generation works (recommended)
    #   - integration: Works with sample project (recommended)
    #   - lint: Code passes linting (optional)
    #   - custom.*: Module-specific checks (optional)
    #
    # For large modules, consider moving checks to a separate checks.nix file.
    # -------------------------------------------------------------------------
    stackpanel.moduleChecks.${meta.id} = {
      # REQUIRED: Verify module evaluates without errors
      eval = {
        description = "${meta.name} module evaluates correctly";
        required = true;
        derivation = pkgs.runCommand "${meta.id}-eval-check" {} ''
          echo "✓ Module ${meta.name} evaluates successfully"
          touch $out
        '';
      };

      # REQUIRED: Verify required packages are available
      packages = {
        description = "${meta.name} packages are available";
        required = true;
        derivation = pkgs.runCommand "${meta.id}-packages-check" {
          # nativeBuildInputs = [ pkgs.my-package ];
        } ''
          # my-package --version
          echo "✓ All required packages available"
          touch $out
        '';
      };

      # RECOMMENDED: Verify config generation works
      # config = {
      #   description = "${meta.name} config generation works";
      #   required = false;
      #   derivation = pkgs.runCommand "${meta.id}-config-check" {} ''
      #     echo '${builtins.toJSON { example = "config"; }}' | ${pkgs.jq}/bin/jq .
      #     echo "✓ Config generation works"
      #     touch $out
      #   '';
      # };

      # OPTIONAL: Module-specific checks
      # custom = {
      #   my-custom-check = {
      #     description = "Custom check for ${meta.name}";
      #     required = false;
      #     derivation = pkgs.runCommand "${meta.id}-custom-check" {} ''
      #       echo "✓ Custom check passed"
      #       touch $out
      #     '';
      #   };
      # };
    };

    # =========================================================================
    # Health Checks (Runtime) - Shown in UI, run in devshell
    # =========================================================================
    # These checks run at runtime to verify the module is working correctly.
    # They are displayed in the Stackpanel UI and can be run manually.
    # -------------------------------------------------------------------------
    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        installed = {
          description = "${meta.name} is installed and accessible";
          script = ''
            # command -v my-command >/dev/null 2>&1 && my-command --version
            echo "Check not implemented"
            exit 0
          '';
          severity = "critical";
          timeout = 5;
        };
        # Add more runtime health checks as needed
        # config-valid = {
        #   description = "Configuration is valid";
        #   script = ''
        #     test -f "$STACKPANEL_ROOT/path/to/config.json"
        #   '';
        #   severity = "warning";
        #   timeout = 5;
        # };
      };
    };

    # -------------------------------------------------------------------------
    # Module Registration - Required for UI discovery
    # -------------------------------------------------------------------------
    stackpanel.modules.${meta.id} = {
      enable = true;
      inherit meta;
      source.type = "builtin";
      features = meta.features;
      tags = meta.tags;
      priority = meta.priority;
      healthcheckModule = meta.id;
    };
  };
}
