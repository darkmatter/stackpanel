# A real external flake, with no Stackpanel or nixpkgs input.
{
  description = "Public SDK discovery fixture";
  outputs = _: {
    stackpanelModuleMeta = {
      overlays = [
        (final: _: {
          fixtureTool = final.writeShellScriptBin "fixture-tool" "echo fixture";
          fixtureUI = final.writeTextDir "index.html" "<title>Fixture UI</title>";
        })
      ];
      flakeModules = [
        {
          perSystem = { pkgs, ... }: { packages.fixture-adapter = pkgs.fixtureTool; };
        }
      ];
    };

    # Deliberately use the documented curried SDK form. Forcing pkgs here in
    # global evaluation would fail: that context has no system or nixpkgs set.
    stackpanelModules.default =
      {
        lib,
        pkgs,
        isGlobalEval,
        ...
      }:
      lib.stackpanel.mkModule {
        name = "discovery-fixture";
        meta = {
          name = "Discovery fixture";
          category = "fixture-tools";
        };
        defaultEnable = true;
        packages = [ pkgs.fixtureTool ];
        ui = ./studio.json;
        panels.fixture-ui = {
          title = "Fixture panel";
          type = "PANEL_TYPE_CUSTOM";
          uiBundle = {
            package = pkgs.fixtureUI;
            entry = "index.html";
            permissions = [ "config:read" ];
          };
        };
        config = _: {
          stackpanel.nixosModules = lib.optionalAttrs isGlobalEval { fixture-global = { }; };
          stackpanel.containerBuilders.fixture =
            { image, containerLib, ... }:
            containerLib.buildImage (
              image
              // {
                appDir = containerLib.pkgsLinux.writeTextDir "app/message" "from an external module";
                defaultCommand = [
                  "/bin/cat"
                  "/app/message"
                ];
              }
            );
          stackpanel.containers.images.fixture.type = "fixture";
        };
      };
  };
}
