{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.raku;
in
{
  options.stackpanel.languages.raku = {
    enable = lib.mkEnableOption "tools for Raku development";
  };

  config = lib.mkIf cfg.enable {
    packages = with pkgs; [
      rakudo
    ];
  };
}
