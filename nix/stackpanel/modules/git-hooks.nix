# ==============================================================================
# git-hooks.nix
#
# Git hooks integration using stackpanel app tooling wrappers.
# Consumes stackpanel.appsComputed.<app>.wrappedTooling.* and exposes a
# git-hooks configuration fragment suitable for git-hooks.nix.
#
# Usage (in .stackpanel/devenv.nix):
#   git-hooks.enable = true;
#   # merged-config.nix will expose this as git-hooks config
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;
  appsComputed = cfg.appsComputed or { };

  allTools =
    tools: lib.flatten (lib.mapAttrsToList (_: app: app.wrappedTooling.${tools} or [ ]) appsComputed);

  toolCommand = tool: {
    entry = "${lib.getExe tool}";
    language = "system";
    pass_filenames = false;
  };

  mkHooks =
    tools:
    lib.listToAttrs (
      lib.imap0 (idx: tool: {
        name = "stackpanel-${tools}-${toString idx}";
        value = toolCommand tool;
      }) tools
    );
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.git-hooks = {
      enable = lib.mkDefault true;
      hooks = {
        pre-commit = (mkHooks (allTools "formatters")) // (mkHooks (allTools "linters"));
        pre-push = mkHooks (allTools "build-steps");
      };
    };
  };
}
