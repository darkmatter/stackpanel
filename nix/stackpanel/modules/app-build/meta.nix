# ==============================================================================
# meta.nix - App Build Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "app-build";

  # Display name
  name = "App Build";

  # Short description
  description = "Nix-based app packaging and flake derivation routing";

  # Category for UI grouping
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "package";

  # Documentation link
  homepage = "";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "build"
    "packaging"
    "derivations"
    "flake"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    appModule = true;     # Adds per-app build.*, package, checkPackage options
    packages = true;      # Routes app packages to flake outputs
    files = false;
    scripts = false;
    healthchecks = false;
    services = false;
    secrets = false;
    tasks = false;
  };

  # Priority for ordering (lower = higher priority)
  # High priority - runs before language modules (go=20, bun=20)
  priority = 5;
}
