{ lib, config, ... }:
let
  inherit (lib) types mkOption;
  metadata = { name, ... }: {
    options = {
      label = mkOption {
        type = types.str;
        default = name;
        description = "Display name of the provider.";
      };
      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Provider icon.";
      };
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Provider summary.";
      };
      module = mkOption {
        type = types.str;
        default = name;
        description = "ID of the module providing this entry.";
      };
    };
  };
  registry =
    description: type:
    mkOption {
      inherit description;
      type = types.attrsOf type;
      default = { };
    };
  providers = config.stackpanel.appBuildProviders;
  # Inspect keys, not derivations: listing apps must not evaluate toolchains or lockfiles.
  owners = lib.zipAttrsWith (_: ids: ids) (
    lib.mapAttrsToList (id: packages: lib.mapAttrs (_: _: id) packages) providers
  );
in
{
  options.stackpanel = {
    appRuntimes = registry "Language runtimes, selected with apps.<app>.<id>.enable." (
      types.submodule metadata
    );
    appFrameworks = registry "Frameworks selected with apps.<app>.framework.<id>.enable." (
      types.submodule [
        metadata
        {
          options = {
            compatibleRuntimes = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Runtime IDs compatible with this framework. Empty means unrestricted.";
            };
            defaultTasks = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Default apps.<app>.tasks.<task>.exec shell commands. Run from the
                app directory, with local and workspace node_modules/.bin on PATH.
                Explicit task definitions take precedence.
              '';
            };
            deployMetadata = mkOption {
              type = types.uniq (types.functionTo types.attrs);
              default = _: { };
              description = ''
                Function from the evaluated app to extra pure-data deployment
                parameters. For example, a Worker framework targeting Cloudflare
                returns { cloudflareAdapter = "worker"; entrypoint = "src/api.ts"; }.
                The host, app path and binding lists remain controlled by the app.
              '';
            };
          };
        }
      ]
    );
    appBuildProviders = registry "Per-runtime packages, keyed by app name. Each app may have at most one provider." (
      types.lazyAttrsOf types.package
    );
    appBuildPackages = mkOption {
      internal = true;
      readOnly = true;
      type = types.lazyAttrsOf types.package;
      description = "App build providers indexed by app name for package export.";
    };
    containerBuilders = registry ''
      Functions from { appName, app, image, containerLib, pkgs, inputs, lib }
      to { container, copyScript }. app is null for standalone images. image
      contains the normalized name, version, backend, projectRoot, port, paths,
      command, environment, layers and registry. Use containerLib.buildImage
      for the standard Linux image and host-native copy script.
    '' (types.uniq (types.functionTo types.attrs));
    deploymentHosts = registry "Deployment host IDs available to apps." (types.submodule metadata);
    deployBackends = registry "Deployment backends available to stack deploy." (
      types.submodule [
        metadata
        {
          options.nixosService = lib.mkEnableOption "generating the app's NixOS service on assigned machines";
          options.script = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Absolute path to the backend executable, or null for a built-in CLI handler.";
          };
        }
      ]
    );
    modulePackages = registry "Development shell packages contributed by each module." (
      types.listOf types.package
    );
  };

  config.stackpanel.appBuildPackages = lib.mapAttrs' (
    app: ids:
    if lib.length ids == 1 then
      lib.nameValuePair app providers.${lib.head ids}.${app}
    else
      throw "stackpanel: conflicting build providers for app '${app}': ${lib.concatStringsSep ", " ids}"
  ) owners;
}
