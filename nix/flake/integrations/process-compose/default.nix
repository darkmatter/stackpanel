# ==============================================================================
# integrations/process-compose — process-compose-flake wiring
#
# Uses flakeConfig (separate perSystem) so it can read the finished
# devShells.default.passthru after the shell is constructed.
# ==============================================================================
{
  localFlake,
  localInputs,
  inputs,
}:
let
  available = inputs ? process-compose-flake;
in
{
  inherit available;

  flakeModules = if available then [ inputs.process-compose-flake.flakeModule ] else [ ];

  # Separate perSystem arm — must see merged config.devShells / legacyPackages.
  flakeConfig =
    { lib, ... }:
    {
      perSystem =
        { config, lib, ... }:
        let
          shell = config.devShells.default or null;
          processes = if shell != null then shell.passthru.processes or { } else { };
          hasProcesses = processes != { };
          sp = config.legacyPackages.stackpanelFullConfig or null;
          enabled = sp != null && (sp.enable or false) && hasProcesses;
        in
        lib.mkIf enabled {
          process-compose.dev.settings = {
            environment = sp.process-compose.environment or { };
            inherit processes;
          };
        };
    };
}
