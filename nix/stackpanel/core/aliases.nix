# ==============================================================================
# aliases.nix
#
# Shell shortcut for stackpanel commands.
#
# The canonical CLI is `stack`, with `stackpanel` available as an alias. Both
# are provided by the stackpanel-cli package (not this module). This module
# adds a single convenience shortcut to the devshell:
#
#   - `spx` - Run stackpanel commands (`stack commands`; lists available
#             commands when called with no arguments)
#
# The shortcut is automatically available in the devshell and forwards all
# arguments correctly to the underlying stackpanel commands.
# ==============================================================================
{
  config,
  lib,
  ...
}:
let
  cfg = config.stackpanel.aliases;

  commandsRunner = ''
    if [ $# -eq 0 ]; then
      stack commands list
    else
      stack commands "$@"
    fi
  '';

  aliasScript = ''
    # Run stackpanel commands. Lists available commands when called with no args.
    spx() {
      ${commandsRunner}
    }
  '';
in
{
  options.stackpanel.aliases = {
    enable = lib.mkEnableOption "stackpanel shell aliases" // {
      default = true;
    };
  };

  config = lib.mkIf (config.stackpanel.enable && cfg.enable) {
    # Add alias definitions to enterShell hooks for nix develop/devenv shell
    stackpanel.devshell.hooks.after = lib.mkAfter [
      ''eval "$STACKPANEL_ALIAS_FUNC"''
    ];

    # Export function definition for direnv
    # This allows the function to be available even when using `use flake`
    stackpanel.devshell.env.STACKPANEL_ALIAS_FUNC = aliasScript;

    # Add to hooks.before to source the function early
    stackpanel.devshell.hooks.before = lib.mkAfter [
      ''eval "$STACKPANEL_ALIAS_FUNC"''
    ];
  };
}
