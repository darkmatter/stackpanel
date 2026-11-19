{
  inputs,
  pkgs,
  system,
}:
let
  inherit (inputs) stackpanel self;
  inherit (pkgs) lib;
  extension = inputs.test-module.stackpanelModules.default;
  legacy = self.legacyPackages.${system};
  state = legacy.stackpanelSerializable;
  panelById = id: lib.findFirst (p: p.id == id) (throw "${id} was not serialized") state.panelsList;
  panel = panelById "fixture-ui";
  nativePanel = panelById "discovery-fixture-ui";
  preview = legacy.stackpanelSpeculate {
    enablePath = [
      "modules"
      "fixture-preview"
      "enable"
    ];
  };
  adopted = legacy.stackpanelSpeculate { adoption.modules.fixture-preview.enable = true; };
  replaced = legacy.stackpanelSpeculate {
    enablePath = [
      "modules"
      "fixture-preview"
      "enable"
    ];
    modules = [
      ({ pkgs, lib, ... }: {
        stackpanel = {
          modulePackages.fixture-preview = lib.mkForce [
            (pkgs.writeShellScriptBin "fixture-preview-tool" "echo replacement")
          ];
          services.fixture-preview.env.MODE = "replacement";
        };
      })
    ];
  };
  names = map lib.getName;
  containsAll = expected: actual: builtins.all (v: builtins.elem v actual) expected;
  locals = [
    "fixture-local-nix"
    "fixture-local-modules"
  ];
  explicit = { pkgs, ... }: {
    stackpanel.devshell.packages = [ (pkgs.writeShellScriptBin "fixture-explicit" ":") ];
  };
  viaParts =
    autoImportInputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ system ];
      imports = [ stackpanel.flakeModules.default ];
      stackpanel = {
        inherit autoImportInputs;
        imports = [ explicit ];
      };
    };
  parts = viaParts true;
  optOut = viaParts false;
  manual = stackpanel.lib.mkFlake {
    inputs = inputs // {
      skipped.stackpanelModules.default = throw "unexpected automatic module import";
    };
    systems = [ system ];
    autoImportInputs = false;
    stackpanelImports = [
      explicit
      extension
    ];
  };
  unavailableBackend = stackpanel.lib.mkFlake {
    inputs = inputs // {
      nix2container.packages.x86_64-linux.nix2container = null;
    };
    systems = [ system ];
  };
  # Pure interface harness: evaluate the public devenv module with the same
  # input and root arguments the devenv CLI supplies. No shell is entered.
  devenvEval =
    autoImportInputs:
    lib.evalModules {
      specialArgs = {
        inherit inputs;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      };
      modules = [
        stackpanel.devenvModules.default
        ({ lib, ... }: {
          options = {
            devenv.root = lib.mkOption { type = lib.types.str; };
            shell = lib.mkOption { type = lib.types.package; };
            packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
            enterShell = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };
          };
          config = {
            devenv.root = toString self.outPath;
            shell = pkgs.hello;
            stackpanel = {
              inherit autoImportInputs;
              imports = [
                explicit
                ({ lib, ... }: {
                  options.stackpanel.inlineDevenvFixture = lib.mkEnableOption "inline devenv fixture";
                })
              ];
            };
          };
        })
      ];
    };
  discoveredDevenv = devenvEval true;
  manualPackages = names manual.legacyPackages.${system}.stackpanelFullConfig.devshell.packages;
  devenvManualPackages = names (devenvEval false).config.packages;
  options = stackpanel.lib.getOptions {
    inherit pkgs inputs;
    extraImports = [
      ({ lib, isGlobalEval, ... }: {
        options.stackpanel.fixtureOption = lib.mkOption {
          type = lib.types.bool;
          default = !isGlobalEval && lib.stackpanel ? mkModule;
        };
      })
    ];
  };
  explicitOnly =
    out:
    let
      sp = out.legacyPackages.${system}.stackpanelFullConfig;
    in
    !sp.autoImportInputs
    && !(sp.modules ? discovery-fixture)
    && containsAll (locals ++ [ "fixture-explicit" ]) (names sp.devshell.packages);
in
assert containsAll [
  "mkModule"
  "mkSimpleModule"
  "mkInfraModule"
  "spField"
  "jsonSchemaFromSpFields"
  "panels"
  "ports"
  "validateModule"
] (builtins.attrNames stackpanel.lib);
assert stackpanel.lib.validateModule {
  inherit pkgs inputs;
  module = extension;
  moduleId = "discovery-fixture";
};
assert options.autoImportInputs.default && options.fixtureOption.default;
assert state.registries == [ "https://registry.example.test/modules.json" ];
assert builtins.any (m: m.id == "discovery-fixture" && m.enabled) state.modulesListAll;
assert containsAll (locals ++ [ "fixture-global" ]) (builtins.attrNames self.nixosModules);
assert self.packages.${system}.fixture-adapter == pkgs.fixtureTool;
assert !(inputs ? nix2container) && lib.isDerivation self.packages.${system}.container-fixture;
assert builtins.isString self.packages.${system}.container-fixture.drvPath;
assert !(builtins.tryEval unavailableBackend.packages.${system}.container-fixture.drvPath).success;
assert containsAll (
  locals
  ++ [
    "fixture-tool"
    "fixture-explicit"
  ]
) (names parts.legacyPackages.${system}.stackpanelFullConfig.devshell.packages);
assert explicitOnly optOut && !(optOut.nixosModules ? fixture-global);
assert !manual.legacyPackages.${system}.stackpanelFullConfig.autoImportInputs;
assert containsAll (
  locals
  ++ [
    "fixture-tool"
    "fixture-explicit"
  ]
) manualPackages;
assert containsAll (
  locals
  ++ [
    "fixture-tool"
    "fixture-explicit"
  ]
) (names discoveredDevenv.config.packages);
# CLI nixd uses the upstream project.options expression; flake-parts nixd
# uses the actual named devShell. Both must retain non-serializable imports.
assert
  discoveredDevenv.options.stackpanel.nixdOptions.default.inlineDevenvFixture.type.name == "bool";
assert discoveredDevenv.config.shell.stackpanelOptions.inlineDevenvFixture.type.name == "bool";
assert
  containsAll (locals ++ [ "fixture-explicit" ]) devenvManualPackages
  && !(builtins.elem "fixture-tool" devenvManualPackages);
assert !(legacy.stackpanelFullConfig.services ? fixture-preview);
assert builtins.elem "preview.txt" (map (f: f.path) preview.files);
assert
  builtins.elem "fixture-preview-tool" preview.packages
  && builtins.elem "fixture-preview" preview.services;
assert builtins.elem "fixture-preview" adopted.services;
assert builtins.match "[0-9a-f]{64}" preview.packageFingerprints.fixture-preview-tool != null;
assert builtins.match "[0-9a-f]{64}" preview.serviceFingerprints.fixture-preview != null;
assert
  preview.packageFingerprints.fixture-preview-tool
  != replaced.packageFingerprints.fixture-preview-tool;
assert preview.serviceFingerprints.fixture-preview != replaced.serviceFingerprints.fixture-preview;
assert builtins.elem "fixture-preview-tool" (
  map (p: p.name) preview.moduleOutputs.fixture-preview.packages
);
assert nativePanel.id == "discovery-fixture-ui" && nativePanel.module == "discovery-fixture";
assert nativePanel.slot == "module" && nativePanel.title == "Discovery fixture";
assert nativePanel.type == "PANEL_TYPE_SPEC" && nativePanel.uiBundle == null;
assert nativePanel.spec == lib.importJSON ./test-module/studio.json;
assert
  panel.uiBundle.package == toString pkgs.fixtureUI
  && panel.uiBundle.permissions == [ "config:read" ];
pkgs.runCommand "stackpanel-module-discovery" { } ''
  grep -F 'Fixture UI' ${lib.escapeShellArg "${panel.uiBundle.package}/${panel.uiBundle.entry}"}
  ${lib.optionalString (system == "x86_64-linux") ''
    # nix2container produces an image descriptor. Build it on its native
    # platform; Darwin evaluation still requires the real Linux derivation.
    ${pkgs.jq}/bin/jq -e 'type == "object" and length > 0' ${
      self.packages.${system}.container-fixture
    } >/dev/null
  ''}
  touch "$out"
''
