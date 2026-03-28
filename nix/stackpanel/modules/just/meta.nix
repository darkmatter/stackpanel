# ==============================================================================
# meta.nix - Just Module Metadata
# ==============================================================================
{
  id = "just";
  name = "Just";
  description = "Justfile task runner with module-contributed recipes";
  category = "development";
  version = "1.0.0";
  icon = "terminal";
  homepage = "https://just.systems";
  author = "Stackpanel";
  tags = [
    "just"
    "tasks"
    "runner"
    "justfile"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    files = true;
    scripts = false;
    healthchecks = false;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  flakeInputs = [ ];
  priority = 80;
}
