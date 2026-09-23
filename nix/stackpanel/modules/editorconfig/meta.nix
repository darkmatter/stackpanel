# ==============================================================================
# meta.nix - EditorConfig Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "editorconfig";
  name = "EditorConfig";
  description = "Root .editorconfig so editors apply consistent indentation and newline rules";
  category = "development";
  version = "1.0.0";
  icon = "text-cursor-input";
  homepage = "https://editorconfig.org";
  author = "Stackpanel";
  tags = [
    "editorconfig"
    "formatting"
    "editor"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    files = true;
    scripts = false;
    healthchecks = false;
    packages = false;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  flakeInputs = [ ];
  priority = 90;
}
