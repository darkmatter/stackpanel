{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.hare;
in
{
  options.stackpanel.languages.hare = {
    enable = lib.mkEnableOption "tools for Hare development";
  };

  config = lib.mkIf cfg.enable {
    packages = with pkgs; [
      hare
      haredoc
    ];
  };
}
