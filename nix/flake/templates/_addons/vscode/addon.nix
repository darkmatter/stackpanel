# VS Code integration addon (config-driven example).
#
# When accepted during `stackpanel init`, the CLI patches the project config so
# the file generator emits a .vscode/ workspace on the next devshell entry. This
# is the canonical, config-driven way to wire VS Code — we deliberately do NOT
# drop static .vscode/* files here (the generator owns them).
{
  id = "vscode";

  question = {
    type = "bool";
    label = "Install VS Code integration?";
    description = "Generates a .vscode/ workspace (settings, tasks, recommended extensions) wired to the devshell environment.";
    default = true;
    order = 10;
  };

  # Merged into .stack/config.nix when the answer is "yes". Nested attrsets
  # become dot-paths (ide.vscode.enable -> `ide.vscode.enable = true;`). Values
  # must be JSON-serialisable (strings, bools, numbers, lists, attrsets).
  config = {
    ide.vscode.enable = true;
  };
}
