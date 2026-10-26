{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.robotframework;
in
{
  options.stackpanel.languages.robotframework = {
    enable = lib.mkEnableOption "tools for Robot Framework development";

    python = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python3;
      defaultText = lib.literalExpression "pkgs.python3";
      description = "The Python package to use.";
    };

  };

  config = lib.mkIf cfg.enable {
    packages = [
      (cfg.python.withPackages (ps: [
        ps.robotframework
      ]))
    ];
  };
}
