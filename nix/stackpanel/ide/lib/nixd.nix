{ lib, pkgs, self,  ... }:
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

      # ---- EXPERIMENTAL ----
      # Use own inputs, faliling back to fetching tarballs, should be more reliable
      # gitignoreSrc = pkgs.fetchFromGitHub { owner = "hercules-ci"; repo = "gitignore.nix"; rev = "cb5e3fdca1de58ccbc3ef53de65bd372b48f567c"; hash = "sha256-XmjITeZNMTQXGhhww6ed/Wacy2KzD6svioyCX7pkUu4="; };

    in
    rec {
      # inherit (import gitignoreSrc { inherit (pkgs) lib; }) gitignoreSource;
      inherit isStackpanelRepo hasValidLocalRoot;

      # Expression to get stackpanel options from the flake
      # flakeOptionsExpr = "(builtins.getFlake ${ref}).legacyPackages.\${builtins.currentSystem}.stackpanelOptions";
      flakeOptionsExpr = "let"
        + "system = builtins.currentSystem; "
        + "pkgs = import <nixpkgs> { inherit system; }; "
        + "lib = pkgs.lib; "
        + "flake = builtins.getFlake ./.; "
        + "libstack = flake.inputs.stackpanel.outputs.lib; "
        + "in (libstack.getOptions { inherit (pkgs) lib; }).options";

      stackpanelInputOptionsExpr =
      if  self ? inputs.stackpanel.outputs.lib.getOptions then
      "${self.inputs.stackpanel.outputs.lib.getOptions { inherit (pkgs) lib; }}.options" else null;

      # NOTE: nixd evaluates option expressions using the Nix evaluator's settings.
      # If `pure-eval = true` (the default in flake mode), expressions that use
      # `import <nixpkgs>`, absolute paths, or unlocked `builtins.getFlake` will fail.
      # The nixd wrapper script (generated alongside these settings) disables pure-eval
      # so these expressions work correctly.
      localEvalBaseExpr =
        "let pkgs = import <nixpkgs> { }; lib = pkgs.lib; eval = lib.evalModules { modules = [ "
        + "${root}/nix/stackpanel/core/options "
        + "{ _module.args = { inherit pkgs lib; }; } "
        + "]; }; in eval";

      localStackpanelOptionsExpr = "${localEvalBaseExpr}.options.stackpanel";
      localFullOptionsExpr = "${localEvalBaseExpr}.options";
      # Prefer local pure evaluation when hacking on stackpanel itself.
      optionsExpr =
        if isStackpanelRepo && hasValidLocalRoot then localStackpanelOptionsExpr
        else if stackpanelInputOptionsExpr != null then stackpanelInputOptionsExpr
        else flakeOptionsExpr;
      nixosOptionsExpr = if isStackpanelRepo && hasValidLocalRoot then localFullOptionsExpr else "null";
    };
}
