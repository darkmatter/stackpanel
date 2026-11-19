# Hash effective runtime identities in Nix. Never return a service's env,
# command or hook, and do not inspect arbitrary third-party function options.
{
  lib,
  sp,
  serializePackage,
}:
let
  fingerprint =
    value: builtins.hashString "sha256" (builtins.unsafeDiscardStringContext (builtins.toJSON value));
  packages = sp.devshell.packages ++ (sp.devshell._commandPkgs or [ ]);
  grouped = builtins.groupBy (p: p.name) (
    (map (p: {
      inherit (serializePackage p) name;
      identity = toString p;
    }) packages)
    ++ lib.optionals sp.userPackages.enable (
      map (p: {
        inherit (p) name;
        identity = p;
      }) sp.userPackages.serialized
    )
  );
  enabled = lib.filterAttrs (_: service: service.enable) sp.services;
in
{
  packages = builtins.attrNames grouped;
  packageFingerprints = lib.mapAttrs (
    _: group:
    fingerprint (lib.sort builtins.lessThan (lib.unique (map (p: fingerprint p.identity) group)))
  ) grouped;
  services = builtins.attrNames enabled;
  serviceFingerprints = lib.mapAttrs (
    _: service:
    fingerprint {
      inherit (service)
        command
        port
        proxy
        autoStart
        env
        shellHook
        dataDir
        displayName
        description
        module
        ;
      packages = map toString service.packages;
      process-compose = service.process-compose or { };
    }
  ) enabled;
}
