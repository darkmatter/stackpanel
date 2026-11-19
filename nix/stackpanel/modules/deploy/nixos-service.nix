# ==============================================================================
# nixos-service.nix - Default NixOS service module template
#
# Called as: import ./nixos-service.nix { inherit name app lib; }
# Returns: a NixOS module function
#
# Generates:
#   - systemd.services.${name}    (the service unit)
#   - users.users.${name}         (system user)
#   - users.groups.${name}        (system group)
#   - sops.secrets."${name}-env"  (if app.deployment.secrets != [], requires sops-nix)
#
# ExecStart resolution:
#   - Explicit deployment.command overrides the runtime's resolvedCommand.
#   - A function is resolved at NixOS evaluation time, using target packages.
#
# Prerequisites:
#   - inputs must be available as a specialArg when used by a runtime provider
#   - sops-nix must be imported if app.deployment.secrets is non-empty
# ==============================================================================
{
  name,
  app,
  lib,
}:
let
  hasSecrets = (app.deployment.secrets or [ ]) != [ ];
  defaultEnv = app.deployment.defaultEnv or "prod";
in
{
  pkgs,
  inputs,
  ...
}@targetArgs:
let
  command = app.deployment.command or null;
  resolvedCommand = app.deployment.resolvedCommand or null;
  execStart =
    if command != null then
      command
    else if lib.isFunction resolvedCommand then
      resolvedCommand (targetArgs // { inherit pkgs inputs name; })
    else if resolvedCommand != null then
      resolvedCommand
    else
      throw "stackpanel: app '${name}' (backend: ${
        app.deployment.backend or "colmena"
      }) has no ExecStart: set deployment.command or enable a runtime that supplies deployment.resolvedCommand";
in
{
  systemd.services.${name} = {
    description = "${name} stackpanel service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = execStart;
      User = name;
      Group = name;
      Restart = "on-failure";
      RestartSec = "5s";
    }
    // lib.optionalAttrs hasSecrets {
      EnvironmentFile = "/run/secrets/${name}-env";
    };
  };

  users.users.${name} = {
    isSystemUser = true;
    group = name;
    description = "${name} service user";
  };
  users.groups.${name} = { };
}
// lib.optionalAttrs hasSecrets {
  sops.secrets."${name}-env" = {
    format = "dotenv";
    sopsFile = ".stack/secrets/${defaultEnv}.yaml";
  };
}
