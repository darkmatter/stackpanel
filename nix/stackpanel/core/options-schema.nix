{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
  dirs = cfg.dirs or { profile = ".stack/profile"; };

  transformOptions =
    opt:
    opt
    // {
      declarations = map (
        decl:
        let
          declStr = toString decl;
        in
        {
          name = declStr;
          url = null;
        }
      ) (opt.declarations or [ ]);
    };

  optionsDoc = pkgs.nixosOptionsDoc {
    options = builtins.removeAttrs (options.stackpanel or { }) [ "_module" ];
    inherit transformOptions;
    warningsAreErrors = false;
  };

  optionsSchema =
    pkgs.runCommand "stackpanel-options.schema.json"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.nodejs
        ];
      }
      ''
        ${pkgs.nodejs}/bin/node ${./lib/options-doc-to-schema.cjs} \
          ${optionsDoc.optionsJSON}/share/doc/nixos/options.json > "$out.raw"
          ${pkgs.jq}/bin/jq '.' "$out.raw" > "$out"
      '';
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.files.entries."${dirs.profile}/stackpanel-options.schema.json" = {
      type = "derivation";
      drv = optionsSchema;
      source = "core";
      description = "JSON Schema for stackpanel config options";
    };
  };
}
