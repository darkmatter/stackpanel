# ==============================================================================
# meta.nix - Turbo Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "turbo";

  # Display name
  name = "Turborepo";

  # Short description
  description = "Turborepo task orchestration with turbo.json generation";

  # Category for UI grouping
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "rocket";

  # Documentation link
  homepage = "https://turbo.build/repo";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "turbo"
    "turborepo"
    "monorepo"
    "tasks"
    "pipeline"
    "build"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = true;         # Generates turbo.json and task scripts
    scripts = false;
    healthchecks = false;
    packages = true;      # Creates task script derivations
    services = false;
    secrets = false;
    tasks = true;         # Provides turbo tasks
    appModule = true;     # Adds per-app turbo.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 15;
}
