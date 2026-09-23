# ==============================================================================
# editorconfig - Root .editorconfig
#
# Formerly a file-drop init addon. As a module the file is a `files.entries`
# output, so it gains drift-checking and revert that a raw copy never had, and
# a version bump ships to every adopter on the next shell entry.
#
# The `adoption` offer is emitted outside the enable guard: `stack setup`
# suggests it to projects that have not enabled it, and accepting it writes
# `modules.editorconfig.enable = true` into .stack/config.nix.
# ==============================================================================
args:
let
  meta = import ./meta.nix;
  inherit (import ../../lib/mkModule.nix { }) mkModule;
in
(mkModule {
  name = meta.id;
  inherit meta;
  source.type = "builtin";
  inherit (meta) features;
  inherit (meta) tags;
  inherit (meta) priority;

  adoption = {
    revision = 1;
    question = {
      type = "bool";
      label = "Add a root .editorconfig?";
      description = "Generates a shared .editorconfig so editors apply consistent indentation and newline rules.";
      default = false;
      order = 20;
    };
    config.modules.editorconfig.enable = true;
  };

  config = _cfg: {
    stackpanel.files.entries.".editorconfig" = {
      format = "text";
      writer = "full";
      adopt = "backup";
      path = ./files/.editorconfig;
      source = meta.id;
      description = "Shared editor settings (indentation, charset, final newline)";
    };
  };
})
  args
