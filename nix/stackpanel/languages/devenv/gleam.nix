{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.gleam;
in
{
  options.stackpanel.languages.gleam = {
    enable = lib.mkEnableOption "tools for Gleam development";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.gleam;
      description = "The Gleam package to use.";
      defaultText = lib.literalExpression "pkgs.gleam";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.languages.erlang.enable = true;

    packages = [
      cfg.package
    ];
  };
}
