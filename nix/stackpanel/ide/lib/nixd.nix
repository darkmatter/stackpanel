{ lib, ... }:
{
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
      localRef = "\"git+file://${root}\"";

      # FlakeHub URL for external users
      flakehubRef = "\"https://flakehub.com/f/darkmatter/stackpanel/*\"";

      # Choose the appropriate reference:
      # - For stackpanel repo with valid local root: use local file reference
      # - Otherwise: use FlakeHub URL (works for users and as fallback)
      ref = if isStackpanelRepo && hasValidLocalRoot then localRef else flakehubRef;

    in
    rec {
      inherit isStackpanelRepo hasValidLocalRoot;

      # Expression to get stackpanel options from the flake
      flakeOptionsExpr = "(builtins.getFlake ${ref}).legacyPackages.\${builtins.currentSystem}.stackpanelOptions";

      # NOTE: nixd evaluates option expressions in *pure* mode, so `builtins.getFlake`
      # on an unlocked reference (like git+file:// or FlakeHub "*") will fail unless
      # nixd is run with --impure. For stackpanel development, use a pure local eval.
      localEvalBaseExpr =
        "let pkgs = import <nixpkgs> { }; lib = pkgs.lib; eval = lib.evalModules { modules = [ "
        + "${root}/nix/stackpanel/core/options "
        + "{ _module.args = { inherit pkgs lib; }; } "
        + "]; }; in eval";

      localStackpanelOptionsExpr = "${localEvalBaseExpr}.options.stackpanel";
      localFullOptionsExpr = "${localEvalBaseExpr}.options";
      # Prefer local pure evaluation when hacking on stackpanel itself.
      optionsExpr =
        if isStackpanelRepo && hasValidLocalRoot then localStackpanelOptionsExpr else flakeOptionsExpr;
      nixosOptionsExpr = if isStackpanelRepo && hasValidLocalRoot then localFullOptionsExpr else "null";
    };
}
