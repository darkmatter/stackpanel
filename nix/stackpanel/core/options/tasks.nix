# ==============================================================================
# tasks.nix
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  db = import ../../db { inherit lib; };
in
{
  options.stackpanel.taskModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend task configuration options.
    '';
  };

  options.stackpanel.tasks = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          { options = db.extend.task; }
        ]
        ++ config.stackpanel.taskModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = "Task definitions forwarded to devenv tasks.";
  };
}
