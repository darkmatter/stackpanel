# ==============================================================================
# module.nix - Just Module Implementation
#
# Allows Nix modules to contribute justfile recipes that are automatically
# imported into the root Justfile.
#
# Each contributing module adds an entry to `stackpanel.just.modules`:
#
#   stackpanel.just.modules.deploy = {
#     description = "Deployment recipes";
#     recipes = ''
#       # Deploy to staging
#       deploy-staging:
#           just deploy us-west-2
#     '';
#   };
#
# The module:
#   1. Writes each entry as `.stack/gen/just/<name>.just`
#   2. Injects `import` lines into the root Justfile via a managed block
#   3. Adds `just` to the devshell if not already present
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel.just;
  sp = config.stackpanel;

  # Directory for generated justfile modules (relative to repo root)
  justDir = ".stack/gen/just";

  # All enabled modules
  enabledModules = lib.filterAttrs (_: m: m.enable) cfg.modules;

  # Generate import lines for the Justfile managed block
  importLines = lib.mapAttrsToList (name: _: "import '${justDir}/${name}.just'") enabledModules;
in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.just = {
    enable = lib.mkEnableOption "Just task runner integration" // {
      default = true;
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkEnableOption "this justfile module" // {
                default = true;
              };

              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Short description shown as a comment header in the generated .just file.";
              };

              recipes = lib.mkOption {
                type = lib.types.lines;
                description = ''
                  Justfile recipe text. This is written verbatim into
                  `.stack/gen/just/<name>.just` and imported by the root Justfile.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Justfile modules contributed by Nix modules. Each entry generates a
        `.just` file under `.stack/gen/just/` that is automatically imported
        by the root Justfile via a managed block.
      '';
      example = lib.literalExpression ''
        {
          db = {
            description = "Database management recipes";
            recipes = '''
              # Generate a new Drizzle migration after schema changes
              db-generate:
                  bun run db:generate
            ''';
          };
        }
      '';
    };
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkIf (sp.enable && cfg.enable) (
    lib.mkMerge [
      # Add just to devshell
      {
        stackpanel.devshell.packages = [ pkgs.just ];
      }

      # Generate .just files and Justfile imports when there are modules
      (lib.mkIf (enabledModules != { }) {
        stackpanel.files.entries =
          # Per-module .just files
          (lib.mapAttrs' (
            name: mod:
            lib.nameValuePair "${justDir}/${name}.just" {
              type = "text";
              text =
                let
                  header = if mod.description != "" then "# ${mod.description}\n\n" else "";
                in
                header + mod.recipes;
              description = "Justfile module: ${name}";
              source = "just";
            }
          ) enabledModules)
          // {
            # Inject import lines into the root Justfile via a managed block.
            # User content outside the block is untouched.
            "Justfile" = {
              type = "line-set";
              managed = "block";
              blockLabel = "stackpanel-just";
              sort = true;
              dedupe = true;
              lines = importLines;
              description = "Auto-imports for stackpanel justfile modules";
              source = "just";
            };
          };
      })

      # Module registration
      {
        stackpanel.modules.${meta.id} = {
          enable = true;
          meta = {
            inherit (meta)
              name
              description
              icon
              category
              author
              version
              ;
            homepage = meta.homepage;
          };
          source.type = "builtin";
          features = meta.features;
          flakeInputs = meta.flakeInputs;
          tags = meta.tags;
          priority = meta.priority;
        };
      }
    ]
  );
}
