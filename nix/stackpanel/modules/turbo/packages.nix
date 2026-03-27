# ==============================================================================
# packages.nix - Turbo Workspace Package Declarations
#
# Declares workspace packages whose package.json scripts and turbo.json tasks
# are managed by Nix. Single source of truth for both files.
#
# Usage:
#   stackpanel.turbo.packages.infra = {
#     name = "@stackpanel/infra";
#     path = "packages/infra";
#     dependencies = { alchemy = "^0.81.2"; };
#     scripts.deploy = {
#       exec = "alchemy deploy";
#       turbo = { enable = true; cache = false; };
#     };
#   };
#
# This generates:
#   - packages/infra/package.json (with name, scripts, deps, exports)
#   - turbo.json tasks entry for scripts with turbo.enable = true
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.turbo;
  pkgsCfg = cfg.packages;
  hasPkgs = builtins.length (builtins.attrNames pkgsCfg) > 0;

  # ============================================================================
  # Submodule: turbo task config for a script
  # ============================================================================
  turboScriptOpts = {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Register this script as a turbo task in turbo.json";
      };

      cache = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable Turborepo caching (null = turbo default)";
      };

      dependsOn = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tasks that must complete first (use ^ for workspace deps)";
      };

      outputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Output file globs for caching";
      };

      inputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Input file globs for cache key";
      };

      persistent = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Long-running process (e.g. dev server)";
      };

      interactive = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Task accepts stdin input";
      };
    };
  };

  # ============================================================================
  # Submodule: package script entry
  # ============================================================================
  scriptOpts = {
    options = {
      exec = lib.mkOption {
        type = lib.types.str;
        description = ''
          The command string for this script.
          Written to package.json scripts as-is.
        '';
      };

      turbo = lib.mkOption {
        type = lib.types.submodule turboScriptOpts;
        default = { };
        description = "Turbo task configuration for this script";
      };
    };
  };

  # ============================================================================
  # Submodule: workspace package declaration
  # ============================================================================
  packageOpts = {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "NPM package name (e.g. @stackpanel/infra)";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Workspace path relative to repo root (e.g. packages/infra)";
      };

      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set private: true in package.json";
      };

      type = lib.mkOption {
        type = lib.types.enum [
          "module"
          "commonjs"
        ];
        default = "module";
        description = "Package type (module = ESM, commonjs = CJS)";
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "package.json dependencies";
      };

      devDependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "package.json devDependencies";
      };

      exports = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          package.json exports field.
          Example: { "." = { default = "./src/index.ts"; }; }
        '';
      };

      scripts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule scriptOpts);
        default = { };
        description = "package.json scripts (and optional turbo task config)";
      };

      # Escape hatch for additional package.json fields
      extraFields = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Additional fields to merge into package.json.
          Use for fields not covered by other options (e.g. bin, main, files).
        '';
      };
    };
  };

  # ============================================================================
  # Build package.json value for a package (used with type = "json" for merging)
  # ============================================================================
  mkPackageJsonValue =
    _pkgId: pkg:
    {
      name = pkg.name;
      private = pkg.private;
      type = pkg.type;
    }
    // lib.optionalAttrs (pkg.scripts != { }) {
      scripts = lib.mapAttrs (_: s: s.exec) pkg.scripts;
    }
    // lib.optionalAttrs (pkg.dependencies != { }) {
      dependencies = pkg.dependencies;
    }
    // lib.optionalAttrs (pkg.devDependencies != { }) {
      devDependencies = pkg.devDependencies;
    }
    // lib.optionalAttrs (pkg.exports != { }) {
      exports = pkg.exports;
    }
    // pkg.extraFields;

  flattenJsonSetOps =
    prefix: value:
    if builtins.isAttrs value then
      lib.flatten (lib.mapAttrsToList (key: nested: flattenJsonSetOps (prefix ++ [ key ]) nested) value)
    else
      [
        {
          op = "set";
          path = prefix;
          inherit value;
        }
      ];

  # ============================================================================
  # Collect turbo-enabled scripts as stackpanel.tasks entries
  # ============================================================================
  collectTurboTasks =
    let
      # For each package, extract scripts with turbo.enable = true
      # and build a task entry compatible with stackpanel.tasks schema
      pkgTasks = lib.mapAttrsToList (
        _pkgId: pkg:
        lib.filterAttrs (_: v: v != null) (
          lib.mapAttrs (
            scriptName: scriptCfg:
            if scriptCfg.turbo.enable then
              { }
              // lib.optionalAttrs (scriptCfg.turbo.cache != null) {
                cache = scriptCfg.turbo.cache;
              }
              // lib.optionalAttrs (scriptCfg.turbo.dependsOn != [ ]) {
                dependsOn = scriptCfg.turbo.dependsOn;
              }
              // lib.optionalAttrs (scriptCfg.turbo.outputs != [ ]) {
                outputs = scriptCfg.turbo.outputs;
              }
              // lib.optionalAttrs (scriptCfg.turbo.inputs != [ ]) {
                inputs = scriptCfg.turbo.inputs;
              }
              // lib.optionalAttrs (scriptCfg.turbo.persistent != null) {
                persistent = scriptCfg.turbo.persistent;
              }
              // lib.optionalAttrs (scriptCfg.turbo.interactive != null) {
                interactive = scriptCfg.turbo.interactive;
              }
            else
              null
          ) pkg.scripts
        )
      ) pkgsCfg;
    in
    lib.foldl' (acc: tasks: acc // tasks) { } pkgTasks;

in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.turbo.packages = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule packageOpts);
    default = { };
    description = ''
      Workspace package declarations.

      Each entry generates a package.json at the specified path and
      optionally registers scripts as turbo.json tasks.

      This is the single source of truth for package scripts — changes here
      update both package.json and turbo.json atomically.
    '';
    example = lib.literalExpression ''
      {
        infra = {
          name = "@stackpanel/infra";
          path = "packages/infra";
          dependencies = { alchemy = "^0.81.2"; };
          scripts.deploy = {
            exec = "alchemy deploy";
            turbo = { enable = true; cache = false; };
          };
        };
      }
    '';
  };

  # ============================================================================
  # Config
  # ============================================================================
  config = lib.mkIf hasPkgs {

    # --------------------------------------------------------------------------
    # Generate package.json for each declared package
    # --------------------------------------------------------------------------
    stackpanel.files.entries = lib.mapAttrs' (
      pkgId: pkg:
      lib.nameValuePair "${pkg.path}/package.json" {
        type = "json-ops";
        adopt = "backup";
        ops = flattenJsonSetOps [ ] (mkPackageJsonValue pkgId pkg);
        source = "turbo";
        description = "Package manifest for ${pkg.name}";
      }
    ) pkgsCfg;

    # --------------------------------------------------------------------------
    # Register turbo-enabled scripts as tasks (flows into turbo.json)
    # --------------------------------------------------------------------------
    stackpanel.tasks = collectTurboTasks;
  };
}
