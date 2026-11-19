{ lib, pkgs }:
let
  # No implementation in Stackpanel knows these provider IDs.
  pkg = pkgs.writeShellScriptBin "sample-server" "echo serving";
  provider =
    { config, lib, ... }@args:
    lib.stackpanel.mkModule {
      name = "sample-provider";
      meta.name = "Sample provider";
      defaultEnable = true;
      appOptions = {
        sample-runtime.enable = lib.mkEnableOption "the sample runtime";
        framework.sample-framework.enable = lib.mkEnableOption "the sample framework";
      };
      appModule = { config, ... }: {
        config.deployment.resolvedCommand = lib.mkIf config.sample-runtime.enable (
          {
            inputs,
            pkgs,
            name,
            ...
          }:
          "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.${name}}/bin/sample-server"
        );
      };
      config = _: {
        stackpanel = {
          appRuntimes.sample-runtime = {
            label = "Sample runtime";
            module = "sample-provider";
          };
          appBuildProviders.sample-runtime = lib.mapAttrs (_: _: pkg) (
            lib.filterAttrs (_: app: app.sample-runtime.enable) config.stackpanel.apps
          );
          appFrameworks.sample-framework = {
            label = "Sample framework";
            module = "sample-provider";
            compatibleRuntimes = [ "sample-runtime" ];
            defaultTasks = {
              dev = "sample dev";
              build = "sample build";
            };
            deployMetadata = app: {
              entrypoint = "${app.path}/server.js";
              cloudflareAdapter = "worker";
            };
          };
          deploymentHosts.sample-host.label = "Sample host";
          deployBackends.sample-deploy = {
            script = "${pkg}/bin/sample-server";
            nixosService = true;
          };
        };
      };
    } args;
  evaluate =
    extra:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs lib;
        inputs = { };
        self.outPath = ../..;
        localFlake = null;
        isGlobalEval = false;
      };
      modules = [
        ../..
        provider
        {
          stackpanel = {
            enable = true;
            name = "provider-tests";
            deployment.defaultHost = "sample-host";
            apps.sample = {
              path = "apps/sample";
              sample-runtime.enable = true;
              framework.sample-framework.enable = true;
              tasks.build.exec = "sample build --release";
              deployment = {
                enable = true;
                backend = "sample-deploy";
                targets = [ "box" ];
              };
            };
          };
        }
        extra
      ];
    }).config.stackpanel;
  sp = evaluate { };
  # Evaluate the actual emitted NixOS module with the *target* package set.
  command =
    state:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sample = state.outputs.sample;
      };
      modules = [
        state.nixosModules.sample
        {
          options.systemd.services = lib.mkOption { type = lib.types.attrs; };
          options.users = lib.mkOption { type = lib.types.attrs; };
        }
      ];
    }).config.systemd.services.sample.serviceConfig.ExecStart;
  hosted = evaluate { stackpanel.apps.sample.deployment.host = "cloudflare"; };
  conflict = evaluate { stackpanel.appBuildProviders.other.sample = pkgs.hello; };

  # Use the same public projection as module and panel queries. Disable the
  # integrations via their advertised paths, not by overriding registry rows.
  public = (import ../../lib/serialize.nix { inherit lib; }).projectState;
  security = {
    stackpanel = {
      aws.roles-anywhere.enable = true;
      secrets.enable = true;
      secrets.secrets-dir = ".stack/secrets";
      step-ca.enable = true;
    };
  };
  active = public (evaluate security);
  owners = [
    "healthchecks"
    "aws-roles-anywhere"
    "deploy"
    "secrets"
    "step-ca"
  ];
  records = state: lib.listToAttrs (map (m: lib.nameValuePair m.id m) state.modulesListAll);
  inactive = lib.genAttrs owners (
    id:
    public (evaluate {
      config = lib.mkMerge [
        security
        (lib.setAttrByPath ([ "stackpanel" ] ++ lib.splitString "." (records active).${id}.enablePath) (
          lib.mkForce false
        ))
      ];
    })
  );
  healthPanel =
    state: lib.any (p: p.id == "healthchecks-overview" && p.module == "healthchecks") state.panelsList;
in
[
  {
    name = "built-in ownership: registered panels and outputs follow each owner's real enable path";
    actual = {
      activeOwners = lib.filter (id: (records active).${id}.enabled) owners;
      panels = [
        (healthPanel active)
        (healthPanel inactive.healthchecks)
      ];
      packages = map (id: active.moduleOutputs.${id}.packages != [ ]) [
        "aws-roles-anywhere"
        "deploy"
      ];
      checks = map (id: active.moduleOutputs.${id}.healthchecks != [ ]) [
        "secrets"
        "step-ca"
      ];
      disabled = lib.all (
        id:
        !(records inactive.${id}).${id}.enabled
        && lib.all (rows: rows == [ ]) (builtins.attrValues inactive.${id}.moduleOutputs.${id})
      ) owners;
    };
    expected = {
      activeOwners = owners;
      panels = [
        true
        false
      ];
      packages = [
        true
        true
      ];
      checks = [
        true
        true
      ];
      disabled = true;
    };
  }
  {
    name = "external runtime supplies package and target service executable";
    actual = [
      sp.outputs.sample.drvPath
      (command sp)
      sp.deployment.defaultHost
    ];
    expected = [
      pkg.drvPath
      "${pkg}/bin/sample-server"
      "sample-host"
    ];
  }
  {
    name = "explicit deployment command overrides runtime";
    actual = command (evaluate {
      stackpanel.apps.sample.deployment.command = "/run/overridden";
    });
    expected = "/run/overridden";
  }
  {
    name = "external framework wires defaults without overriding user tasks";
    actual = [
      sp.apps.sample.tasks.dev.exec
      sp.apps.sample.tasks.dev.module
      sp.apps.sample.tasks.build.exec
    ];
    expected = [
      "sample dev"
      "sample-provider"
      "sample build --release"
    ];
  }
  {
    name = "external framework deployment metadata reaches the host renderer";
    actual = hosted.infra.modules.deployment.inputs.apps.sample.entrypoint;
    expected = "apps/sample/server.js";
  }
  {
    name = "providers may not silently shadow another runtime's package";
    actual = (builtins.tryEval conflict.outputs.sample.drvPath).success;
    expected = false;
  }
]
