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
      spConfig,
      ...
    }:
    let
      gitHooksConfig = spConfig.git-hooks or { };
      # App tooling contributes stage-keyed hooks, whereas git-hooks.nix
      # expects a flat set of named hooks with an explicit stages list.
      stages = [ "pre-commit" "pre-push" ];
      grouped = gitHooksConfig.hooks or { };
      appHooks = lib.concatMapAttrs (stage: lib.mapAttrs' (name: hook:
        lib.nameValuePair "${stage}-${name}" ({ enable = true; inherit name; stages = [ stage ]; } // hook)
      )) (lib.getAttrs (builtins.filter (s: grouped ? ${s}) stages) grouped);
      hooks = builtins.removeAttrs gitHooksConfig [ "enable" "hooks" "extraLinters" "extraFormatters" ]
        // builtins.removeAttrs grouped stages // appHooks;
      # git-hooks.nix publishes lib per system; skip the check where it has none.
      supportsSystem = inputs.git-hooks.lib ? ${system};
    in
    lib.mkIf (available && supportsSystem && (gitHooksConfig.enable or false) && hooks != { }) {
      checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = self;
        inherit hooks;
      };
    };
}
