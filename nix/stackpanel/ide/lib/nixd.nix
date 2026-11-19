{
  lib,
  pkgs,
  devenv ? null,
  ...
}:
let
  devenvCli = devenv != null && devenv.cli;
in
{
  # Both GUI editors need the same evaluator environment, without a devshell.
  launcher = pkgs.writeShellScript "stackpanel-nixd" ''
    export NIX_CONFIG="''${NIX_CONFIG:-}
    pure-eval = false"
    export NIX_PATH="nixpkgs=${pkgs.path}''${NIX_PATH:+:$NIX_PATH}"
    export PATH="${lib.makeBinPath [ pkgs.nixfmt ]}:$PATH"
    ${lib.optionalString devenvCli ''
      # Ask devenv for the bootstrap expression for this project. Flakeless
      # roots need not reconstruct the inputs, profiles or arbitrary imports.
      set -eo pipefail
      project=$(devenv lsp --print-config | ${pkgs.jq}/bin/jq -er '.nixd.options.devenv.expr | strings') || {
        echo 'Stackpanel nixd requires `devenv lsp --print-config` for devenv CLI projects.' >&2
        exit 1
      }
      set -- --nixos-options-expr "($project).stackpanel.nixdOptions.default" "$@"
    ''}
    exec ${pkgs.nixd}/bin/nixd "$@"
  '';

  mkValues =
    {
      project ? {
        repo = "";
      },
      github ? "",
      root ? null,
    }:
    let
      # Detect if we're working on stackpanel itself
      # Check both project.repo and the github option (owner/repo format)
      repoFromProject = project.repo or "";
      repoFromGithub =
        let
          parts = lib.splitString "/" github;
        in
        if builtins.length parts == 2 then builtins.elemAt parts 1 else "";
      repo = if repoFromProject != "" then repoFromProject else repoFromGithub;
      isStackpanelRepo = repo == "stackpanel";

      # Get a valid local path reference (requires root to be a real absolute path)
      hasValidLocalRoot = root != null && !lib.hasPrefix "/nix/store/" root;
    in
    rec {
      inherit isStackpanelRepo hasValidLocalRoot;

      # Expression to get stackpanel options from the flake
      # Use the project's resolved options, not its input flake's options:
      # only the former include the consumer's installed modules.
      flakeOptionsExpr = "(builtins.getFlake (toString ./.)).stackpanelOptions";
      moduleAuthorOptionsExpr =
        if devenv == null then
          "(builtins.getFlake (toString ./.)).stackpanelModuleAuthorOptions"
        else
          "(import ${devenv.sdk}/nix/stackpanel/lib/sdk.nix { lib = import ${devenv.nixpkgs}/lib; }).moduleAuthorOptions";

      # NOTE: nixd evaluates option expressions using the Nix evaluator's settings.
      # If `pure-eval = true` (the default in flake mode), expressions that use
      # `import <nixpkgs>`, absolute paths, or unlocked `builtins.getFlake` will fail.
      # The nixd wrapper script (generated alongside these settings) disables pure-eval
      # so these expressions work correctly.
      localEvalBaseExpr =
        "(let pkgs = import <nixpkgs> { }; lib = import ${root}/nix/flake/module-lib.nix pkgs.lib; "
        + "in lib.evalModules { modules = [ ${root}/nix/stackpanel/core/options ]; "
        + "specialArgs = { inherit pkgs lib; inputs = {}; isGlobalEval = false; }; })";

      localStackpanelOptionsExpr = "${localEvalBaseExpr}.options.stackpanel";
      localFullOptionsExpr = "${localEvalBaseExpr}.options";
      # Prefer local pure evaluation when hacking on stackpanel itself.
      optionsExpr =
        if devenvCli then
          null # The launcher's default worker holds the project tree.
        else if devenv != null then
          "(builtins.getFlake (toString ./.)).devShells.${pkgs.stdenv.hostPlatform.system}.${lib.strings.escapeNixString devenv.shellName}.stackpanelOptions"
        else if isStackpanelRepo && hasValidLocalRoot then
          localStackpanelOptionsExpr
        else
          flakeOptionsExpr;
      projectProvider = lib.optionalAttrs (!devenvCli) { stackpanel.expr = optionsExpr; };
      authorProvider.stackpanel-module.expr = moduleAuthorOptionsExpr;
      zedNixosProvider = lib.optionalAttrs (!devenvCli) { nixos.expr = nixosOptionsExpr; };
      nixosOptionsExpr = if isStackpanelRepo && hasValidLocalRoot then localFullOptionsExpr else "null";
    };
}
