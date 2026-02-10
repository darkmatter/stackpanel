# ==============================================================================
# go.nix - Go Language Toolchain
#
# Sets up the Go development toolchain: compiler, tools, GOPATH, GOROOT,
# and PATH. This replaces devenv's languages.go module.
#
# This module handles TOOLCHAIN setup (compiler, env, PATH).
# App-level config (building, packaging, air, gomod2nix) is in modules/go/.
#
# Usage in .stackpanel/config.nix:
#   languages.go.enable = true;
#
# Or auto-enabled when any app has go.enable = true.
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.languages.go;
  stateDir = config.stackpanel.dirs.state or ".stackpanel/state";
in
{
  options.stackpanel.languages.go = {
    enable = lib.mkEnableOption "Go development toolchain";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.go;
      defaultText = lib.literalExpression "pkgs.go";
      description = "The Go compiler package to use.";
    };

    enableHardeningWorkaround = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable fortify hardening for Delve debugger compatibility.";
    };

    lsp = {
      enable = lib.mkEnableOption "gopls language server" // {
        default = true;
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.gopls;
        defaultText = lib.literalExpression "pkgs.gopls";
        description = "The gopls package to use.";
      };
    };

    tools = {
      delve = lib.mkEnableOption "Delve debugger" // {
        default = true;
      };
      gotools = lib.mkEnableOption "gotools (goimports, etc.)" // {
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = [
      cfg.package
    ]
    ++ lib.optional cfg.tools.delve pkgs.delve
    ++ lib.optional cfg.tools.gotools pkgs.gotools
    ++ lib.optional cfg.lsp.enable cfg.lsp.package;

    # GOROOT is a static nix store path so it can go in env.
    # GOPATH references $STACKPANEL_STATE_DIR which is set by an earlier hook,
    # so it must be exported from a hook (env values are escaped/quoted).
    stackpanel.devshell.env = {
      GOROOT = "${cfg.package}/share/go/";
      GOTOOLCHAIN = "local";
    };

    stackpanel.devshell.hooks.main = [
      ''
        # Go toolchain: set GOPATH and add $GOPATH/bin to PATH
        export GOPATH="''${STACKPANEL_STATE_DIR:-${stateDir}}/go"
        export PATH="$GOPATH/bin:$PATH"
      ''
    ];

    stackpanel.motd.features = [ "Go ${cfg.package.version or ""}" ];
  };
}
