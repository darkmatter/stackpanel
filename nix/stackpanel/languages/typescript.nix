# ==============================================================================
# typescript.nix - TypeScript Language Toolchain
#
# Adds the TypeScript compiler and optionally the language server.
# This replaces devenv's languages.typescript module.
#
# Usage in .stackpanel/config.nix:
#   languages.typescript.enable = true;
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.languages.typescript;
in
{
  options.stackpanel.languages.typescript = {
    enable = lib.mkEnableOption "TypeScript compiler";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.typescript;
      defaultText = lib.literalExpression "pkgs.typescript";
      description = "The TypeScript package to use.";
    };

    lsp = {
      enable = lib.mkEnableOption "TypeScript language server" // {
        default = true;
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.typescript-language-server;
        defaultText = lib.literalExpression "pkgs.typescript-language-server";
        description = "The TypeScript language server package to use.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = [ cfg.package ] ++ lib.optional cfg.lsp.enable cfg.lsp.package;

    stackpanel.motd.features = [ "TypeScript" ];
  };
}
