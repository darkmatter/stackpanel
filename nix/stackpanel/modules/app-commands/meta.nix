# ==============================================================================
# meta.nix - App Commands Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "app-commands";

  # Display name
  name = "App Commands";

  # Short description
  description = "Nix-native app commands for build, dev, test, lint, format";

  # Category for UI grouping
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "terminal";

  # Documentation link
  homepage = null;

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "commands"
    "build"
    "dev"
    "test"
    "lint"
    "format"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = false;
    scripts = false;
    healthchecks = true;
    packages = true;      # Creates package/check derivations
    services = false;
    secrets = false;
    tasks = false;
    appModule = true;     # Adds per-app commands.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 30;
}
