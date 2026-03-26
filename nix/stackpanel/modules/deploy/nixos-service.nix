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
#   - Go apps:   ${inputs.self.packages.${pkgs.system}.${name}}/bin/${binaryName}
#   - Bun apps:  ${inputs.self.packages.${pkgs.system}.${name}}/bin/${binaryName}
#   - Other apps: app.deployment.command (required, throws if missing)
#
# Prerequisites:
#   - inputs.self must be available as a NixOS specialArg
#   - sops-nix must be imported if app.deployment.secrets is non-empty
# ==============================================================================
{ name, app, lib }:
let
  isGoApp = app.go.enable or false;
  isBunApp = app.bun.enable or false;
  hasSecrets = (app.deployment.secrets or [ ]) != [ ];
  defaultEnv = app.deployment.defaultEnv or "prod";
  binaryName =
    if isGoApp then
      let bn = app.go.binaryName or null; in if bn != null then bn else name
    else if isBunApp then
      let bn = app.bun.binaryName or null; in if bn != null then bn else name
    else name;
in
{
  config,
  pkgs,
  inputs,
  ...
}:
let
  execStart =
    if isGoApp || isBunApp then
      "${inputs.self.packages.${pkgs.system}.${name}}/bin/${binaryName}"
    else if app.deployment.command or null != null then
      app.deployment.command
    else
      throw "stackpanel: deployment.command must be set for non-Go/non-Bun app '${name}' (backend: ${app.deployment.backend or "colmena"})";
in
{
  systemd.services.${name} = {
    description = "${name} stackpanel service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig =
      {
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
