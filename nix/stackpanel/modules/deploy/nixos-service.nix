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
#   - Other apps: app.deployment.command (required, throws if missing)
#
# Prerequisites:
#   - inputs.self must be available as a NixOS specialArg
#   - sops-nix must be imported if app.deployment.secrets is non-empty
# ==============================================================================
{ name, app, lib }:
let
  isGoApp = app.go.enable or false;
  hasSecrets = (app.deployment.secrets or [ ]) != [ ];
  defaultEnv = app.deployment.defaultEnv or "prod";
  binaryName = if isGoApp then app.go.binaryName or name else name;
in
# Return a NixOS module function
{
  config,
  pkgs,
  inputs,
  ...
}:
let
  execStart =
    if isGoApp then
      "${inputs.self.packages.${pkgs.system}.${name}}/bin/${binaryName}"
    else if app.deployment.command or null != null then
      app.deployment.command
    else
      throw "stackpanel: deployment.command must be set for non-Go app '${name}' (backend: ${app.deployment.backend or "colmena"})";
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
        # sops-nix places secrets at /run/secrets/<name> by default
        EnvironmentFile = "/run/secrets/${name}-env";
      };
  };

  users.users.${name} = {
    isSystemUser = true;
    group = name;
    description = "${name} service user";
  };
  users.groups.${name} = { };

  # Requires sops-nix (https://github.com/Mic92/sops-nix) to be imported
  sops.secrets."${name}-env" = lib.mkIf hasSecrets {
    format = "dotenv";
    sopsFile = ".stackpanel/secrets/${defaultEnv}.yaml";
  };
}
