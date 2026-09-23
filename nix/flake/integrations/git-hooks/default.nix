# ==============================================================================
# integrations/git-hooks — pre-commit checks via git-hooks.nix
# ==============================================================================
{
  localFlake,
  localInputs,
  inputs,
}:
let
  available = inputs ? git-hooks;
in
{
  inherit available;

  flakeModules = if available then [ inputs.git-hooks.flakeModule ] else [ ];

  perSystem =
    {
      lib,
      system,
      self,
      inputs,
      loadedConfig,
      ...
    }:
    let
      gitHooksConfig = loadedConfig.git-hooks or { };
    in
    lib.mkIf (available && (gitHooksConfig.enable or false)) {
      checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = self;
        hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
      };
    };
}
