# ==============================================================================
# outputs.nix
#
# Output derivations that should be exposed via the flake or devenv.
#
# These are Nix derivations that can be built with `nix build .#<name>`.
# The adapter (devenv.nix or flake) is responsible for exposing these.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  types = lib.types;
in
{
  options.stackpanel.outputs = lib.mkOption {
    type = types.attrsOf (types.either types.package (types.attrsOf types.package));
    default = { };
    description = ''
      Output derivations to expose.
      
      These will be available as:
        - `nix build .#<name>` (via flake) - for direct packages
        - `nix run .#<group>.<name>` (via flake) - for grouped packages (like scripts)
        - `devenv outputs.<name>` (via devenv)
      
      Example:
        stackpanel.outputs = {
          my-docs = pkgs.runCommand "docs" {} "...";
          my-script = pkgs.writeShellScriptBin "foo" "...";
          # Grouped packages (available via nix run .#scripts.<name>)
          scripts = { foo = pkgs.writeShellScriptBin "foo" "..."; };
        };
    '';
    example = lib.literalExpression ''
      {
        docs-json = optionsDoc.optionsJSON;
        docs-md = optionsDoc.optionsCommonMark;
        scripts = { my-script = pkgs.writeShellScriptBin "test" "echo hello"; };
      }
    '';
  };

  # Flake apps - runnable via `nix run .#<name>`
  options.stackpanel.flakeApps = lib.mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        type = lib.mkOption {
          type = types.str;
          default = "app";
          description = "App type (always 'app' for Nix apps).";
        };
        program = lib.mkOption {
          type = types.str;
          description = "Path to the executable.";
        };
      };
    });
    default = { };
    description = ''
      Flake apps to expose via `nix run .#<name>`.
      
      Each app must have:
        - type: "app"
        - program: Path to executable (usually from a derivation)
      
      Example:
        stackpanel.flakeApps = {
          web = { type = "app"; program = "''${myPackage}/bin/web"; };
        };
    '';
  };
}
