# ==============================================================================
# vscode-nix.nix
#
# VS Code integration for Nix: recommended extensions and nixd settings.
# Provides nixd options so Stackpanel options are discoverable in editor.
#
# This generates nix.serverSettings for nixd with:
#   - stackpanel: Full stackpanel options (from flake output)
#   - sp-user: Submodule options for stackpanel.users
#   - sp-app: Submodule options for stackpanel.apps
#   - sp-command: Submodule options for stackpanel.commands
#   - sp-task: Submodule options for stackpanel.tasks
#
# For users: references stackpanel via FlakeHub URL
# For stackpanel development: uses local reference via .stackpanel-root
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  ideCfg = config.stackpanel.ide;
  vscodeCfg = ideCfg.vscode;
  stackpanelCfg = config.stackpanel;

  # Detect if we're working on stackpanel itself
  # Check both project.repo and the github option (owner/repo format)
  repoFromProject = stackpanelCfg.project.repo or "";
  repoFromGithub =
    let
      parts = lib.splitString "/" (stackpanelCfg.github or "");
    in
    if builtins.length parts == 2 then builtins.elemAt parts 1 else "";
  repo = if repoFromProject != "" then repoFromProject else repoFromGithub;
  isStackpanelRepo = repo == "stackpanel";

  # Get a valid local path reference (requires .stackpanel-root with real absolute path)
  hasValidLocalRoot = stackpanelCfg.root != null && !lib.hasPrefix "/nix/store/" stackpanelCfg.root;
  localRef = "\"git+file://${stackpanelCfg.root}\"";

  # FlakeHub URL for external users
  flakehubRef = "\"https://flakehub.com/f/darkmatter/stackpanel/*\"";

  # Choose the appropriate reference:
  # - For stackpanel repo with valid local root: use local file reference
  # - Otherwise: use FlakeHub URL (works for users and as fallback)
  ref = if isStackpanelRepo && hasValidLocalRoot then localRef else flakehubRef;

  # Expression to get stackpanel options from the flake
  flakeOptionsExpr = "(builtins.getFlake ${ref}).legacyPackages.\${builtins.currentSystem}.stackpanelOptions";

  # Helper to get submodule options from the flake output
  mkSubOptionsExpr = optionPath: "${flakeOptionsExpr}.${optionPath}.type.getSubOptions []";
in
{
  config = lib.mkIf (ideCfg.enable && vscodeCfg.enable) {
    stackpanel.devshell.packages = [
      pkgs.nixd
      pkgs.nixfmt
    ];

    stackpanel.ide.vscode.extensions = lib.mkAfter [
      "jnoortheen.nix-ide"
    ];

    stackpanel.ide.vscode.settings-modules = lib.mkAfter [
      {
        config = {
          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
          };
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nil";
          "nix.formatterPath" = "alejandra";
          "nix.serverSettings" = {
            "nixd" = {
              "formatting" = {
                "command" = [ "nixfmt" ];
              };
              "options" = {
                # Disable default nixos options (not relevant for stackpanel projects)
                "nixos" = {
                  "expr" = "null";
                };
                # Full stackpanel options (from flake output)
                "stackpanel" = {
                  "expr" = flakeOptionsExpr;
                };
                # Submodule options for common attrs
                "sp-user" = {
                  "expr" = mkSubOptionsExpr "users";
                };
                "sp-app" = {
                  "expr" = mkSubOptionsExpr "apps";
                };
                "sp-task" = {
                  "expr" = mkSubOptionsExpr "tasks";
                };
              };
            };
            "nil" = {
              "formatting" = {
                "command" = [ "alejandra" ];
              };
              "options" = {
                "stackpanel" = {
                  "expr" = flakeOptionsExpr;
                };
              };
              "nix" = {
                "maxMemoryMB" = 8192;
                "flake" = {
                  "autoEvalInputs" = true;
                  "nixpkgsInputName" = "nixpkgs";
                };
              };
            };
          };
        };
      }
    ];
  };
}
