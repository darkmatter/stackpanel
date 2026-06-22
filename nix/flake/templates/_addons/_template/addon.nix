# ==============================================================================
# Addon template — copy this directory to templates/_addons/<your-id>/ and edit.
#
# Directories under templates/_addons/ whose name starts with "_" (like this
# one) are scaffolding only and are NEVER offered to users.
#
# An addon is declared entirely here in Nix. `stackpanel init`:
#   1. reads lib.initAddons (this file + ./files),
#   2. asks `question`,
#   3. copies the selected `files` into the project (existing files are kept),
#   4. patches the selected `config` into .stack/config.nix,
#   5. records the choice in .stack/addons.json so re-runs don't re-ask.
# ==============================================================================
{
  # Stable identifier. Must match the directory name. Used as the marker key and
  # as the value for the --with / --without / --addon flags.
  id = "example";

  # The prompt shown during init.
  question = {
    # "bool"        -> yes / no               (default: a boolean)
    # "select"      -> pick exactly one        (default: a choice value)
    # "multiselect" -> pick zero or more       (default: a list of choice values)
    type = "bool";

    label = "Enable the example addon?";
    description = "One sentence explaining what selecting this does.";
    default = false;

    # Lower numbers are prompted first. Optional (defaults to 0).
    order = 100;

    # For "select" / "multiselect", enumerate the choices. Each choice may carry
    # its own files/config, applied only when that choice is picked. Delete the
    # `choices` block for "bool" addons.
    #
    # choices = [
    #   { value = "none"; label = "None"; }
    #   {
    #     value = "cloudflare";
    #     label = "Cloudflare Workers";
    #     config = { deployment.alchemy.deploy.enable = true; };
    #     # files = { "wrangler.toml" = "name = \"my-worker\"\n"; };
    #   }
    #   {
    #     value = "fly";
    #     label = "Fly.io";
    #     config = { deployment.fly.enable = true; };
    #   }
    # ];
  };

  # Config patched into .stack/config.nix when the addon is active (bool = true,
  # or any non-empty select/multiselect answer). Nested attrsets become
  # dot-paths (ide.vscode.enable -> `ide.vscode.enable = true;`). Values must be
  # JSON-serialisable. Omit entirely if the addon only adds files.
  config = {
    # myFeature.enable = true;
  };

  # Static files are taken from the sibling ./files directory automatically
  # (recursively, preserving subdirectories). You may also inline extra files:
  #
  # files = {
  #   "path/in/project.txt" = "literal contents\n";
  # };

  # JSON merge operations ("json-ops"). Use these to surgically edit existing
  # JSON files (e.g. add a script to package.json) instead of overwriting them.
  # When the addon is active, each target file is registered as a
  # `stackpanel.files.entries.<file>` json-ops entry, and the generator merges
  # the ops into the file on the next devshell entry.
  #
  # Keyed by target file (relative to the project root). Each op is one of:
  #   set          - set the value at `path`
  #   merge        - deep-merge `value` into the object at `path`
  #   remove       - delete the value at `path` (no `value`)
  #   append       - append `value` to the array at `path`
  #   appendUnique - append `value` only if not already present
  #
  # jsonOps = {
  #   "package.json" = [
  #     { op = "merge"; path = [ "scripts" ]; value = { check = "biome check ."; }; }
  #     { op = "appendUnique"; path = [ "workspaces" ]; value = "packages/*"; }
  #   ];
  # };
}
