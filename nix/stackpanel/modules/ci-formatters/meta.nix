# ==============================================================================
# meta.nix - CI Formatters Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "ci-formatters";

  # Display name
  name = "CI Formatters";

  # Short description
  description = "Flake checks for formatter tooling in CI";

  # Category for UI grouping
  category = "ci-cd";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "check-circle";

  # Documentation link
  homepage = null;

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "ci"
    "formatters"
    "checks"
    "flake"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = false;
    scripts = false;
    healthchecks = false;
    packages = false;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };

  # Priority for ordering (lower = higher priority)
  priority = 90;
}
