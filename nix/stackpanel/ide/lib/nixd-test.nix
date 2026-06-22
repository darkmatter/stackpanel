# ==============================================================================
# nixd-test — unit tests for ide/lib/nixd.nix `mkValues` (nixtest)
#
# Exercises the reference-selection logic that decides which Nix expression
# nixd uses for stackpanel option completion:
#   - repo detection from `project.repo` or an "owner/repo" `github` string
#   - `hasValidLocalRoot` (a null root, or one under /nix/store, is not local)
#   - local pure-eval expression vs the FlakeHub `getFlake` expression
#   - `self`-derived input options and `enableExperimental` passthrough
#
# Returns a list of { name; actual; expected; } consumed by the nixtest harness
# wired in nix/flake/default.nix (tests.nixd).
# ==============================================================================
{
  lib,
  pkgs,
  ...
}:
let
  mkValues =
    {
      enableExperimental ? false,
    }:
    args: (import ./nixd.nix { inherit lib pkgs enableExperimental; }).mkValues args;

  # stackpanel repo checked out at a real local path -> local pure-eval mode.
  localStackpanel = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = "/home/dev/stackpanel";
    self = null;
  };

  # Repo name parsed from a "owner/repo" github string instead of project.repo.
  fromGithub = mkValues { } {
    github = "darkmatter/stackpanel";
    root = "/home/dev/stackpanel";
    self = null;
  };

  # Some other project -> always use the FlakeHub reference.
  external = mkValues { } {
    project = {
      repo = "my-app";
    };
    root = "/home/dev/my-app";
    self = null;
  };

  # stackpanel sources living in the store are not a usable local root.
  storeRoot = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = "/nix/store/abc123-source";
    self = null;
  };

  # No root at all is likewise not a usable local root.
  nullRoot = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = null;
    self = null;
  };

  # A provided flake `self` feeds the stackpanel input options expression.
  withSelf = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = "/home/dev/stackpanel";
    self = {
      inputs.stackpanel.outputs.lib.getOptions = _args: "INPUT_OPTIONS";
    };
  };

  # The experimental flag is surfaced on the result only when enabled.
  experimental = mkValues { enableExperimental = true; } {
    project = {
      repo = "stackpanel";
    };
    root = "/home/dev/stackpanel";
    self = null;
  };
in
[
  {
    name = "isStackpanelRepo: true from project.repo";
    actual = localStackpanel.isStackpanelRepo;
    expected = true;
  }
  {
    name = "isStackpanelRepo: true parsed from github owner/repo";
    actual = fromGithub.isStackpanelRepo;
    expected = true;
  }
  {
    name = "isStackpanelRepo: false for a different repo";
    actual = external.isStackpanelRepo;
    expected = false;
  }
  {
    name = "hasValidLocalRoot: true for a real absolute path";
    actual = localStackpanel.hasValidLocalRoot;
    expected = true;
  }
  {
    name = "hasValidLocalRoot: false for a /nix/store path";
    actual = storeRoot.hasValidLocalRoot;
    expected = false;
  }
  {
    name = "hasValidLocalRoot: false when root is null";
    actual = nullRoot.hasValidLocalRoot;
    expected = false;
  }
  {
    name = "optionsExpr: local evalModules used for stackpanel + local root";
    actual = lib.hasInfix "evalModules" localStackpanel.optionsExpr;
    expected = true;
  }
  {
    name = "nixosOptionsExpr: local full options for stackpanel + local root";
    actual = localStackpanel.nixosOptionsExpr != "null";
    expected = true;
  }
  {
    name = "ref: local git+file used for stackpanel + local root";
    actual = lib.hasInfix "git+file:///home/dev/stackpanel" localStackpanel.flakeOptionsExpr;
    expected = true;
  }
  {
    name = "optionsExpr: FlakeHub flake expression used for external projects";
    actual =
      (external.optionsExpr == external.flakeOptionsExpr)
      && lib.hasInfix "flakehub.com" external.flakeOptionsExpr;
    expected = true;
  }
  {
    name = "nixosOptionsExpr: null for external projects";
    actual = external.nixosOptionsExpr;
    expected = "null";
  }
  {
    name = "stackpanelInputOptionsExpr: null string when self is null";
    actual = localStackpanel.stackpanelInputOptionsExpr;
    expected = "null";
  }
  {
    name = "stackpanelInputOptionsExpr: derived from self when provided";
    actual = withSelf.stackpanelInputOptionsExpr;
    expected = "INPUT_OPTIONS.options";
  }
  {
    name = "enableExperimental: surfaced on the result when enabled";
    actual = (experimental ? enableExperimental) && (experimental.enableExperimental or false);
    expected = true;
  }
  {
    name = "enableExperimental: absent from the result by default";
    actual = localStackpanel ? enableExperimental;
    expected = false;
  }
]
