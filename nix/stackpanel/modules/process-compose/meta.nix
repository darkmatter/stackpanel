# ==============================================================================
# meta.nix - Process Compose Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "process-compose";

  # Display name
  name = "Process Compose";

  # Short description
  description = "Process orchestration with auto-generated app processes";

  # Category for UI grouping
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "layers";

  # Documentation link
  homepage = "https://f1bonacc1.github.io/process-compose/";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "process-compose"
    "processes"
    "dev"
    "orchestration"
    "turbo"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = false;
    scripts = true;       # Provides `dev` command
    healthchecks = false;
    packages = true;      # Creates dev wrapper package
    services = false;
    secrets = false;
    tasks = false;
    appModule = true;     # Adds per-app process-compose.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 25;
}
