# ==============================================================================
# nixd-test — unit tests for ide/lib/nixd.nix `mkValues` (nixtest)
#
# Exercises the reference-selection logic that decides which Nix expression
# nixd uses for stackpanel option completion:
#   - repo detection from `project.repo` or an "owner/repo" `github` string
#   - `hasValidLocalRoot` (a null root, or one under /nix/store, is not local)
#   - the three-way `optionsExpr` fallback: local evalModules -> a `self`-provided
#     stackpanel input -> the `getFlake` expression
#
# `self` is an import-level argument (fixed per workspace); `project`/`github`/
# `root` are per-call arguments to `mkValues`.
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
      self ? null,
    }:
    args: (import ./nixd.nix { inherit lib pkgs self; }).mkValues args;

  # stackpanel repo checked out at a real local path -> local pure-eval mode.
  localStackpanel = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = "/home/dev/stackpanel";
  };

  # Repo name parsed from a "owner/repo" github string instead of project.repo.
  fromGithub = mkValues { } {
    github = "darkmatter/stackpanel";
    root = "/home/dev/stackpanel";
  };

  # Some other project, no flake self -> fall back to the getFlake expression.
  external = mkValues { } {
    project = {
      repo = "my-app";
    };
    root = "/home/dev/my-app";
  };

  # stackpanel sources living in the store are not a usable local root.
  storeRoot = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = "/nix/store/abc123-source";
  };

  # No root at all is likewise not a usable local root.
  nullRoot = mkValues { } {
    project = {
      repo = "stackpanel";
    };
    root = null;
  };

  # A flake `self` exposing the stackpanel input feeds its options through
  # `stackpanelInputOptionsExpr` (and `optionsExpr` when not in local mode).
  withSelf =
    mkValues
      {
        self = {
          inputs.stackpanel.outputs.lib.getOptions = _args: "INPUT_OPTIONS";
        };
      }
      {
        project = {
          repo = "my-app";
        };
        root = "/home/dev/my-app";
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
    name = "optionsExpr: local evalModules for stackpanel + local root";
    actual = lib.hasInfix "evalModules" localStackpanel.optionsExpr;
    expected = true;
  }
  {
    name = "nixosOptionsExpr: local full options for stackpanel + local root";
    actual = localStackpanel.nixosOptionsExpr != "null";
    expected = true;
  }
  {
    name = "nixosOptionsExpr: null string for non-local projects";
    actual = external.nixosOptionsExpr;
    expected = "null";
  }
  {
    name = "flakeOptionsExpr: resolves stackpanel via the getFlake input";
    actual = lib.hasInfix "flake.inputs.stackpanel" external.flakeOptionsExpr;
    expected = true;
  }
  {
    name = "optionsExpr: falls back to flakeOptionsExpr without local root or self";
    actual = external.optionsExpr == external.flakeOptionsExpr;
    expected = true;
  }
  {
    name = "stackpanelInputOptionsExpr: null when self lacks the stackpanel input";
    actual = external.stackpanelInputOptionsExpr;
    expected = null;
  }
  {
    name = "stackpanelInputOptionsExpr: derived from self when the input is present";
    actual = withSelf.stackpanelInputOptionsExpr;
    expected = "INPUT_OPTIONS.options";
  }
  {
    name = "optionsExpr: uses the self input options when present and not local";
    actual = withSelf.optionsExpr;
    expected = "INPUT_OPTIONS.options";
  }
]
