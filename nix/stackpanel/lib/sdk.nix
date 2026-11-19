# Public, pkgs-independent SDK shared by flake outputs, module arguments and CI.
{ lib }:
let
  sdk = {
    inherit (import ./mkModule.nix { inherit lib; }) mkModule mkSimpleModule;
    inherit (import ./mkInfraModule.nix { inherit lib; }) mkInfraModule;
    inherit (import ./json-schema.nix { inherit lib; }) jsonSchemaFromSpFields;
    inherit (import ./ui { inherit lib; }) ui moduleAuthorOptions;
    db = import ../db { inherit lib; };
    spField = sdk.db.field;
    inherit (sdk.db) proto schemas;
    panels = import ./panels.nix { inherit lib; };
    ports = import ./ports.nix { inherit lib; };
    extensionSdk = ../../../packages/extension-sdk;

    # Flake exports may return an ordinary module or the module function
    # produced by mkModule. Let evalModules supply each function's arguments.
    normalizeModule =
      module:
      if !lib.isFunction module then
        module
      else
        lib.setFunctionArgs (
          args:
          let
            result = module args;
          in
          if lib.isFunction result then { imports = [ result ]; } else result
        ) (lib.functionArgs module);

    # Returns true on success, throws the original evaluation error on failure.
    # Supply moduleId for a registry check: it must register metadata and its
    # declared enablePath must actually control the module, in both directions.
    validateModule =
      {
        pkgs,
        module,
        moduleId ? null,
        inputs ? { },
        extraModules ? [ ],
      }:
      let
        evaluate =
          extra:
          (lib.evalModules {
            modules = [
              ../.
              (sdk.normalizeModule module)
              {
                stackpanel.enable = true;
                stackpanel.name = "module-validation";
              }
            ]
            ++ extraModules
            ++ extra;
            specialArgs = {
              inherit inputs pkgs;
              lib = lib // {
                stackpanel = sdk;
              };
              isGlobalEval = false;
              inherit (pkgs.stdenv.hostPlatform) system;
              self = inputs.self or { outPath = ../.; };
              localFlake = null;
            };
          }).config.stackpanel;
        base = evaluate [ ];
        registration =
          base.modulesComputedAll.${moduleId}
            or (throw "Module `${moduleId}` did not register in stackpanel.modules");
        check =
          enabled:
          let
            sp = evaluate [
              (lib.setAttrByPath ([ "stackpanel" ] ++ lib.splitString "." registration.enablePath) (
                lib.mkForce enabled
              ))
            ];
            metadata = sp.modulesComputedAll.${moduleId};
            panels = lib.filterAttrs (_: panel: panel.module == moduleId) sp.panelsComputed;
          in
          if metadata.enabled != enabled then
            throw "Module `${moduleId}` does not honor its enablePath `${registration.enablePath}`"
          else
            builtins.deepSeq [ metadata panels ] true;
      in
      if moduleId == null then builtins.seq (builtins.attrNames base) true else check false && check true;
  };
in
sdk
