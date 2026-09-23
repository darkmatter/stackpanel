# ==============================================================================
# Addon template - copy this directory to templates/_addons/<your-id>/ and edit.
#
# Directories under templates/_addons/ whose name starts with "_" (like this
# one) are scaffolding only and are NEVER offered to users.
#
# An addon is an adoption offer: metadata, a question, a revision and a config
# mutation. `stack setup`:
#   1. reads the offer (lib.initAddons on a fresh repo, stackpanel.addons in
#      an evaluated project),
#   2. asks `question` unless the ledger says it was already decided at this
#      revision,
#   3. previews what accepting generates (one speculative evaluation),
#   4. writes `config` into .stack/config.nix on acceptance,
#   5. records the decision in .stack/reconcile.json.
#
# There is no files payload: anything worth shipping is a module. If your addon
# needs files, write a module under nix/stackpanel/modules/<id>/ and give it an
# `adoption` argument instead (see modules/playwright/default.nix).
# ==============================================================================
{
  # Stable identifier. Must match the directory name. Used as the ledger key and
  # as the value for the --with / --without / --addon flags.
  id = "example";

  # Author-declared revision. Users who declined are asked again only when this
  # is bumped; a typo fix in the label must not re-nag.
  revision = 1;

  # The prompt shown during setup.
  question = {
    # "bool"        -> yes / no               (default: a boolean)
    # "select"      -> pick exactly one        (default: a choice value)
    # "multiselect" -> pick zero or more       (default: a list of choice values)
    type = "bool";

    label = "Enable the example addon?";
    description = "One sentence explaining what accepting this does.";
    default = false;

    # Lower numbers are offered first. Optional (defaults to 0).
    order = 100;

    # For "select" / "multiselect", enumerate the choices. Each choice may carry
    # its own config, applied only when that choice is picked. Delete the
    # `choices` block for "bool" addons.
    #
    # choices = [
    #   { value = "none"; label = "None"; }
    #   {
    #     value = "cloudflare";
    #     label = "Cloudflare Workers";
    #     config = { deployment.alchemy.deploy.enable = true; };
    #   }
    #   {
    #     value = "fly";
    #     label = "Fly.io";
    #     config = { deployment.fly.enable = true; };
    #   }
    # ];
  };

  # Config written into .stack/config.nix when the addon is accepted (bool =
  # true, or any non-empty select/multiselect answer). Nested attrsets become
  # dot-paths relative to the stackpanel config root
  # (modules.example.enable -> `modules.example.enable = true;`). Values must be
  # JSON-serialisable.
  config = {
    # modules.example.enable = true;
  };
}
