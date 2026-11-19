# Public descriptors only: do not traverse generated file contents, packages'
# closures, service environments, task bodies or build-check derivations.
{ lib, serializePackage }:
cfg:
let
  select = names: builtins.intersectAttrs (lib.genAttrs names (_: null));
  publicFiles = lib.mapAttrs (
    path: file:
    {
      inherit path;
      type = file.format;
    }
    // select [
      "module"
      "modules"
      "format"
      "writer"
      "description"
      "source"
      "enable"
      "gitignore"
      "mode"
    ] file
  ) (cfg.files.entries or { });
  publicScripts = lib.mapAttrs (
    name: script:
    {
      inherit name;
      binPath = cfg.devshell._commandsSerializable.${name}.binPath or null;
    }
    // select [ "module" "description" "args" "timeout" ] script
  ) (cfg.scripts or { });
  describeTask =
    name: task:
    {
      inherit name;
    }
    // select [
      "module"
      "description"
      "dependsOn"
      "before"
      "package"
      "inputs"
      "outputs"
      "cache"
      "persistent"
      "interactive"
    ] task;
  publicTasks = lib.mapAttrs describeTask (cfg.tasks or { });
  appTasks = lib.concatLists (
    lib.mapAttrsToList (
      appName: app:
      lib.mapAttrsToList (
        taskName: task: (describeTask "${appName}:${taskName}" task) // { inherit appName taskName; }
      ) (app.tasks or { })
    ) (cfg.apps or { })
  );
  publicServices = lib.mapAttrs (
    name: svc:
    {
      inherit name;
      proxy = {
        enable = svc.proxy.enable or false;
        port = svc.proxy.port or null;
      };
    }
    // select [ "module" "enable" "description" "displayName" "port" "autoStart" ] svc
  ) (cfg.services or { });

  group =
    rows: builtins.groupBy (row: row.module) (builtins.filter (row: (row.module or null) != null) rows);
  byModule = {
    files = group (
      lib.concatMap (
        file:
        map (module: file // { inherit module; }) (
          lib.unique (lib.optional ((file.module or null) != null) file.module ++ (file.modules or [ ]))
        )
      ) (lib.attrValues publicFiles)
    );
    scripts = group (lib.attrValues publicScripts);
    tasks = group (lib.attrValues publicTasks ++ appTasks);
    services = group (lib.attrValues publicServices);
    packages = lib.mapAttrs (module: map (pkg: (serializePackage pkg) // { inherit module; })) (
      cfg.modulePackages or { }
    );
    healthchecks = group (
      map (select [
        "module"
        "id"
        "name"
        "description"
        "enabled"
        "type"
        "scope"
        "severity"
        "tags"
        "required"
      ]) (cfg.doctorList or [ ])
    );
  };
  ids = lib.unique (
    builtins.attrNames (cfg.modules or { })
    ++ lib.concatMap builtins.attrNames (lib.attrValues byModule)
  );
in
{
  moduleOutputs = lib.genAttrs ids (id: lib.mapAttrs (_: grouped: grouped.${id} or [ ]) byModule);
  files = {
    enable = cfg.files.enable or true;
    entries = publicFiles;
  };
  scripts = publicScripts;
  services = publicServices;
  tasks = publicTasks;
}
