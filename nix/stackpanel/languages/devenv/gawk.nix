{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.gawk;
in
{
  options.stackpanel.languages.gawk = {
    enable = lib.mkEnableOption "tools for GNU Awk development";
  };

  config = lib.mkIf cfg.enable {
    packages = with pkgs; [
      gawk
      gawkextlib.gawkextlib
    ];
  };
}
