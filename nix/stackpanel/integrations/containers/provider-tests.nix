# Exercise the same evaluated images and host copy programs exported by the flake.
{
  lib,
  pkgs,
  inputs,
}:
let
  moduleLib = import ../../../flake/module-lib.nix lib;
  evaluate =
    backend: extra:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs inputs;
        lib = moduleLib;
        self.outPath = ../../..;
        localFlake = null;
        isGlobalEval = false;
      };
      modules = [
        ../..
        {
          stackpanel = {
            enable = true;
            name = "container-provider-tests";
            root = toString ./.;
            containers.settings = {
              inherit backend;
              defaultRegistry = "docker://registry.example/";
            };
            containerBuilders.rust =
              {
                appName,
                app,
                containerLib,
                image,
                ...
              }:
              let
                inherit (containerLib) pkgsLinux;
                kind = if app == null then "standalone" else "app";
                appDir = pkgsLinux.runCommand "rust-app-root" { } ''
                  mkdir -p $out/app
                  ln -s ${pkgsLinux.ripgrep}/bin/rg $out/app/rg
                '';
              in
              assert image.backend == backend && image.registry == "docker://registry.example/";
              assert if app == null then appName == "job" else app.path == "services/api";
              containerLib.buildImage (
                image
                // {
                  inherit appDir;
                  name = "rust-${kind}-${image.name}";
                  defaultCommand = [
                    "/app/rg"
                    "--version"
                  ];
                }
              );
            apps.api = {
              path = "services/api";
              container = {
                enable = true;
                type = "rust";
                name = "service";
              };
            };
            containers.images.job.type = "rust";
          };
        }
        extra
      ];
    }).config.stackpanel;

  forBackend =
    backend:
    let
      sp = evaluate backend { };
      transport = if backend == "nix2container" then "nix" else "docker-archive";
    in
    lib.mapAttrsToList
      (
        key: expectedName:
        let
          image = sp.containersComputed.images.${key};
          copy = sp.containersComputed.copyScripts.${key};
          program = copy.drvAttrs.text;
          source = builtins.unsafeDiscardStringContext "${transport}:${image}";
        in
        {
          name = "container provider: ${backend} exports ${key} image and matching copy program";
          actual =
            lib.isDerivation image
            && lib.isDerivation copy
            && lib.hasInfix source program
            && lib.hasInfix expectedName program;
          expected = true;
        }
      )
      {
        api = "rust-app-service";
        job = "rust-standalone-job";
      };

  sp = evaluate "dockerTools" { };
  selector = lib.findFirst (field: field.name == "type") null sp.panels.containers-app-config.fields;
  invalid = evaluate "dockerTools" { stackpanel.containers.images.job.type = lib.mkForce "missing"; };
in
lib.concatMap forBackend [
  "nix2container"
  "dockerTools"
]
++ [
  {
    name = "container provider: selector includes built-in and external builders";
    actual = lib.all (id: builtins.elem id (map (choice: choice.value) selector.options)) [
      "bun"
      "custom"
      "go"
      "node"
      "rust"
      "static"
    ];
    expected = true;
  }
  {
    name = "container provider: unknown image builder is rejected";
    actual = (builtins.tryEval invalid.containers.images.job.type).success;
    expected = false;
  }
]
