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
      # git-hooks.nix publishes lib per system and has dropped systems we
      # still support (x86_64-darwin), so skip the check where it has none.
      supportsSystem = inputs.git-hooks.lib ? ${system};
    in
    lib.mkIf (available && supportsSystem && (gitHooksConfig.enable or false)) {
      checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = self;
        hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
      };
    };
}
