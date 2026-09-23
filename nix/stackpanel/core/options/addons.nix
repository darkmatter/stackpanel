# ==============================================================================
# addons.nix - Adoption offers
#
# An addon says "you could turn X on". It is the only authoring surface that
# is new alongside `stackpanel.doctor`, and it is deliberately tiny: metadata,
# a question, a revision, and a config mutation. Installation is NOT part of
# it - that is what a module is for. When an addon is accepted, `stack setup`
# writes `config` into `.stack/config.nix`; Nix re-evaluates; the module's own
# `files.entries` materialize through ordinary reconciliation.
#
# Addons come from two places into this one option:
#   - flake-level: nix/flake/templates/_addons/<id>/addon.nix, injected by the
#     flake adapter (and evaluable on a fresh repo via `lib.initAddons`)
#   - module-level: the `adoption` argument of lib.stackpanel.mkModule, emitted
#     OUTSIDE the module's `mkIf cfg.enable` guard so that an offer to adopt X
#     is visible to people who have not enabled X
#
# Lifecycle is tracked by the CLI in `.stack/reconcile.json`, keyed on the
# author-declared `revision`: declining records "shown, said no" - not "never".
# Bumping `revision` re-offers; fixing a typo in the label does not.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;

  choiceType = lib.types.submodule {
    options = {
      value = lib.mkOption {
        type = lib.types.str;
        description = "Stable value recorded in the ledger and passed to --addon <id>=<value>.";
        example = "fly";
      };

      label = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Label shown in the prompt. Falls back to `value`.";
        example = "Fly.io";
      };

      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Config mutation applied (in addition to the addon-level `config`) when this choice is selected.";
        example = {
          deployment.fly.enable = true;
        };
      };
    };
  };

  questionType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "bool"
          "select"
          "multiselect"
        ];
        default = "bool";
        description = "Prompt shape: yes/no, pick exactly one choice, or pick zero or more.";
        example = "select";
      };

      label = lib.mkOption {
        type = lib.types.str;
        description = "The question shown to the user.";
        example = "Add Playwright end-to-end testing?";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "One sentence explaining what accepting does.";
        example = "Generates playwright.config.ts, an e2e workflow and the test:e2e script.";
      };

      default = lib.mkOption {
        type = lib.types.anything;
        default = null;
        description = "Default answer: a bool, a choice value, or a list of choice values. Used by `--yes` and non-interactive runs.";
        example = false;
      };

      order = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Lower numbers are offered first.";
        example = 10;
      };

      choices = lib.mkOption {
        type = lib.types.listOf choiceType;
        default = [ ];
        description = "Choices for select / multiselect questions.";
      };
    };
  };

  addonType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Stable identifier; the ledger key and the value for --with / --without / --addon.";
          example = "playwright";
        };

        revision = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = ''
            Author-declared revision. A declined addon is re-offered only when this
            is bumped; the ledger stores the revision that was shown.
          '';
          example = 2;
        };

        question = lib.mkOption {
          type = questionType;
          description = "The prompt presented by `stack setup`.";
        };

        config = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            Config mutation written into `.stack/config.nix` when accepted. Paths are
            relative to the stackpanel config root (`modules.playwright.enable = true`).
            Values must be JSON-serializable. Adoption is one-way: undoing it is a
            user edit of config.nix, never a reconciler action.
          '';
          example = {
            modules.playwright.enable = true;
          };
        };

        module = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Module that contributed this offer (set by mkModule's `adoption`). Null for flake-level addons.";
          example = "playwright";
        };
      };
    }
  );

  serializeAddon = a: {
    inherit (a)
      id
      revision
      config
      module
      ;
    question = {
      inherit (a.question)
        type
        label
        description
        default
        order
        ;
      choices = map (c: {
        inherit (c) value label config;
      }) a.question.choices;
    };
  };

  addonsList = lib.sort (
    a: b:
    if a.question.order != b.question.order then a.question.order < b.question.order else a.id < b.id
  ) (map serializeAddon (lib.attrValues cfg.addons));
in
{
  options.stackpanel.addons = lib.mkOption {
    type = lib.types.attrsOf addonType;
    default = { };
    description = ''
      Adoption offers presented by `stack setup` (and listed, never applied, by
      `stack doctor`). Each offer is metadata plus a config mutation; the thing
      being adopted is a module.
    '';
    example = lib.literalExpression ''
      {
        playwright = {
          revision = 1;
          question = {
            type = "bool";
            label = "Add Playwright end-to-end testing?";
            default = false;
          };
          config.modules.playwright.enable = true;
        };
      }
    '';
  };

  options.stackpanel.addonsList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = addonsList;
    description = "Addons sorted by (question.order, id), serialized for the CLI.";
  };
}
