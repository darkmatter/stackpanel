# ==============================================================================
# codegen.nix
#
# Code generation framework for development shells.
#
# This module allows defining code generators that can be run manually or
# automatically on shell entry. Each generator is exposed as a devshell command
# and can be configured to run on shell initialization.
#
# Usage:
#   stackpanel.codegen = {
#     enable = true;
#     generators.types = {
#       exec = "pnpm run generate:types";
#       cwd = "./packages/types";
#       onEnter = true;  # Run when entering shell
#     };
#   };
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.codegen;

  # Import util for debug logging
  util = config.stackpanel.util;

  mkGenCmd = _name: gen: {
    exec = lib.concatStringsSep "\n" (
      lib.filter (s: s != "") [
        (lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') (gen.env or { })
        ))
        (if gen.cwd != null then "cd ${gen.cwd}" else "")
        gen.exec
      ]
    );
    runtimeInputs = gen.runtimeInputs or [ ];
    env = { }; # already injected in exec above; keep consistent
  };

  onEnterHooks = lib.mapAttrsToList (
    name: gen:
    lib.optionalString ((gen.onEnter or cfg.runOnEnter) == true) ''
      ${util.log.debug "codegen: running generator '${name}'"}
      echo "▶ running codegen: ${name}"
      ${gen.exec}
      ${util.log.debug "codegen: generator '${name}' completed"}
    ''
  ) cfg.generators;
in
{
  imports = [
    ../core/options
  ];

  config = lib.mkIf cfg.enable {
    stackpanel.scripts = lib.mkMerge [
      (lib.mapAttrs mkGenCmd cfg.generators)
    ];

    stackpanel.devshell.hooks.after = lib.mkAfter (lib.filter (s: s != "") onEnterHooks);
  };
}
