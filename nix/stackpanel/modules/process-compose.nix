{
  lib,
  config,
  pkgs,
  options,
  ...
}:
let
  cfg = config.stackpanel;
  apps = cfg.apps or { };
  appsComputed = cfg.appsComputed or { };

  hasFilesOption = options ? stackpanel.files;
  hasProcessesOption = options ? processes;

  scriptsModule =
    { lib, ... }:
    {
      options.scripts = {
        enable = lib.mkEnableOption "app scripts + process-compose integration";
        package-json = {
          enable = lib.mkEnableOption "package.json generation for scripts";
          path = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Override package.json path (defaults to app.path/package.json).";
          };
        };
        process-compose = {
          enable = lib.mkEnableOption "process-compose dev process";
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Override process name (defaults to app name).";
          };
        };
      };
    };

  mkAggregateWrapper =
    appName: label: tools:
    if tools == [ ] then
      null
    else
      pkgs.writeShellApplication {
        name = "stackpanel-${appName}-${label}";
        runtimeInputs = tools;
        text = lib.concatStringsSep "\n" (
          [ "set -euo pipefail" ] ++ map (tool: "${lib.getExe tool}") tools
        );
      };

  mkWrapperSet =
    appName: appCfg: appComputed:
    let
      tooling = appComputed.wrappedTooling or { };
      buildTools =
        (if tooling.build != null then [ tooling.build ] else [ ]) ++ (tooling.build-steps or [ ]);
    in
    {
      install =
        if tooling.install != null then mkAggregateWrapper appName "install" [ tooling.install ] else null;
      build = mkAggregateWrapper appName "build" buildTools;
      test = if tooling.test != null then mkAggregateWrapper appName "test" [ tooling.test ] else null;
      dev = if tooling.dev != null then mkAggregateWrapper appName "dev" [ tooling.dev ] else null;
      format = mkAggregateWrapper appName "format" (tooling.formatters or [ ]);
      lint = mkAggregateWrapper appName "lint" (tooling.linters or [ ]);
    };

  scriptEntries =
    name: wrappers:
    lib.filterAttrs (_: v: v != null) {
      install = if wrappers.install != null then lib.getExe wrappers.install else null;
      build = if wrappers.build != null then lib.getExe wrappers.build else null;
      test = if wrappers.test != null then lib.getExe wrappers.test else null;
      dev = if wrappers.dev != null then lib.getExe wrappers.dev else null;
      format = if wrappers.format != null then lib.getExe wrappers.format else null;
      lint = if wrappers.lint != null then lib.getExe wrappers.lint else null;
    };

  mkPackageJson =
    name: appCfg: wrappers:
    let
      appName = appCfg.name or name;
      scripts = scriptEntries name wrappers;
    in
    pkgs.runCommand "${name}-package.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "jsonContent" ];
        jsonContent = builtins.toJSON {
          name = appName;
          private = true;
          scripts = scripts;
        };
      }
      ''
        jq '.' < "$jsonContentPath" > $out
      '';

  mkProcessEntries =
    name: appCfg: wrappers:
    let
      processName = appCfg.scripts.process-compose.name or name;
      installName = "${processName}-install";
      buildName = "${processName}-build";
      installProcess =
        if wrappers.install != null then
          {
            ${installName} = {
              exec = lib.getExe wrappers.install;
              process-compose = {
                availability.restart = "never";
              };
            };
          }
        else
          { };
      buildProcess =
        if wrappers.build != null then
          {
            ${buildName} = {
              exec = lib.getExe wrappers.build;
              process-compose = {
                availability.restart = "never";
                depends_on = lib.optionalAttrs (wrappers.install != null) {
                  ${installName}.condition = "process_completed_successfully";
                };
              };
            };
          }
        else
          { };
      devDepends =
        (lib.optionalAttrs (wrappers.install != null) {
          ${installName}.condition = "process_completed_successfully";
        })
        // (lib.optionalAttrs (wrappers.build != null) {
          ${buildName}.condition = "process_completed_successfully";
        });
      devProcess =
        if wrappers.dev != null then
          {
            ${processName} = {
              exec = lib.getExe wrappers.dev;
              process-compose = lib.optionalAttrs (devDepends != { }) {
                depends_on = devDepends;
              };
            };
          }
        else
          { };
    in
    installProcess // buildProcess // devProcess;

  appEntries = lib.mapAttrsToList (
    name: appCfg:
    let
      appComputed = appsComputed.${name} or { };
      wrappers = mkWrapperSet name appCfg appComputed;
      packageJsonPath =
        if appCfg.scripts.package-json.path != null then
          appCfg.scripts.package-json.path
        else if appCfg.path != null then
          "${appCfg.path}/package.json"
        else
          null;
    in
    {
      wrappers = wrappers;
      packageJsonPath = packageJsonPath;
      packageJsonDrv = mkPackageJson name appCfg wrappers;
      processEntries = mkProcessEntries name appCfg wrappers;
      scriptsCfg = appCfg.scripts;
    }
  ) apps;
in
{
  config = lib.mkMerge [
    {
      stackpanel.appModules = [
        scriptsModule
      ];
    }
    (lib.mkIf cfg.enable (
      {
        stackpanel.devshell.packages = lib.mkMerge (
          map (entry: lib.filter (x: x != null) (lib.attrValues entry.wrappers)) appEntries
        );
      }
      // lib.optionalAttrs hasFilesOption {
        stackpanel.files.enable = true;
        stackpanel.files.entries = lib.mkMerge (
          map (
            entry:
            let
              scriptsCfg = entry.scriptsCfg;
            in
            lib.optionalAttrs
              (scriptsCfg.enable && scriptsCfg.package-json.enable && entry.packageJsonPath != null)
              {
                "${entry.packageJsonPath}" = {
                  type = "derivation";
                  drv = entry.packageJsonDrv;
                };
              }
          ) appEntries
        );
      }
      // lib.optionalAttrs hasProcessesOption {
        processes = lib.mkMerge (
          map (
            entry:
            let
              scriptsCfg = entry.scriptsCfg;
            in
            lib.optionalAttrs (scriptsCfg.enable && scriptsCfg.process-compose.enable) entry.processEntries
          ) appEntries
        );
      }
    ))
  ];
}
