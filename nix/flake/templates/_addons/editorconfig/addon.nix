# EditorConfig addon (file-drop example).
#
# A pure "drop a file" addon: when selected, `stackpanel init` copies every file
# under ./files into the project (here: a root .editorconfig). No config patch
# is involved. Use this shape for addons that only add static files.
{
  id = "editorconfig";

  question = {
    type = "bool";
    label = "Add a root .editorconfig?";
    description = "Drops a shared .editorconfig so editors apply consistent indentation and newline rules.";
    default = false;
    order = 20;
  };

  # Files are taken from the sibling ./files directory automatically (see
  # editorconfig/files/.editorconfig). No `config` block is needed.
}
