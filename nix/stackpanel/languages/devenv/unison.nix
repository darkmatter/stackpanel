{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.unison;
in
{
  options.stackpanel.languages.unison = {
    enable = lib.mkEnableOption "tools for Unison development";

    package = lib.mkOption {
      type = lib.types.package;
      description = "Which package of Unison to use";
      default = pkgs.unison-ucm;
      defaultText = lib.literalExpression "pkgs.unison-ucm";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      cfg.package
    ];
  };
}
