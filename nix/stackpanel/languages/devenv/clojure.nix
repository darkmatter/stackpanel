{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.stackpanel.languages.clojure;
in
{
  options.stackpanel.languages.clojure = {
    enable = lib.mkEnableOption "tools for Clojure development";

    lsp = {
      enable = lib.mkEnableOption "Clojure Language Server" // {
        default = true;
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.clojure-lsp;
        defaultText = lib.literalExpression "pkgs.clojure-lsp";
        description = "The Clojure language server package to use.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      (pkgs.clojure.override {
        jdk = config.stackpanel.languages.java.jdk.package;
      })
    ]
    ++ lib.optional cfg.lsp.enable cfg.lsp.package;
    stackpanel.languages.java.enable = true;
  };
}
