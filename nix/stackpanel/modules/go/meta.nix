# ==============================================================================
# meta.nix - Go Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "go";

  # Display name
  name = "Go";

  # Short description
  description = "Go application support with gomod2nix packaging";

  # Category for UI grouping
  category = "language";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "code";

  # Documentation link
  homepage = "https://github.com/nix-community/gomod2nix";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "go"
    "golang"
    "gomod2nix"
    "language"
    "runtime"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = true;         # Generates package.json, .air.toml, tools.go
    scripts = true;       # Provides run-<app> and test-<app> scripts
    healthchecks = true;
    packages = true;      # Builds Go applications via gomod2nix
    services = false;
    secrets = false;
    tasks = false;
    appModule = true;     # Adds per-app go.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 20;
}
