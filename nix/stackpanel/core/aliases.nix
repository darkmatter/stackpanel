# ==============================================================================
# aliases.nix
#
# Shell aliases and shortcuts for stackpanel commands.
#
# Provides convenient aliases for common stackpanel CLI operations:
#   - `x` - List available commands (stackpanel commands list)
#   - `x <cmd> [args...]` - Run a command (stackpanel run <cmd> [args...])
#
# The aliases are automatically available in the devshell and forward all
# arguments correctly to the underlying stackpanel commands.
# ==============================================================================
{
  config,
  lib,
  ...
}:
let
  cfg = config.stackpanel.aliases;
in
{
  options.stackpanel.aliases = {
    enable = lib.mkEnableOption "stackpanel shell aliases" // {
      default = true;
    };

    shortcut = lib.mkOption {
      type = lib.types.str;
      default = "x";
      description = ''
        Command name for the stackpanel shortcut alias.
        
        Usage:
          - `${cfg.shortcut}` - List all commands
          - `${cfg.shortcut} dev` - Run dev command
          - `${cfg.shortcut} cmd arg1 arg2` - Run cmd with args
      '';
      example = "sp";
    };
  };

  config = lib.mkIf (config.stackpanel.enable && cfg.enable) {
    # Add function to enterShell hooks for nix develop/devenv shell
    stackpanel.devshell.hooks.after = lib.mkAfter [
      ''
        # Stackpanel command shortcut: ${cfg.shortcut}
        ${cfg.shortcut}() {
          if [ $# -eq 0 ]; then
            stackpanel commands list
          else
            stackpanel run "$@"
          fi
        }
      ''
    ];

    # Export function definition for direnv
    # This allows the function to be available even when using `use flake`
    stackpanel.devshell.env.STACKPANEL_ALIAS_FUNC = ''
      ${cfg.shortcut}() {
        if [ $# -eq 0 ]; then
          stackpanel commands list
        else
          stackpanel run "$@"
        fi
      }
    '';

    # Add to hooks.before to source the function early
    stackpanel.devshell.hooks.before = lib.mkAfter [
      ''eval "$STACKPANEL_ALIAS_FUNC"''
    ];
  };
}
