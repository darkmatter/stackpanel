# ==============================================================================
# meta.nix - Module Metadata
#
# This file contains static metadata that can be read without evaluating the
# full module. This enables fast module discovery for the UI.
#
# IMPORTANT: This file should contain ONLY pure data - no imports, no lib calls,
# no function definitions. This allows it to be read with builtins.import
# without any module system evaluation.
# ==============================================================================
{
  # Unique identifier (should match directory name)
  id = "my-module";

  # Display name
  name = "My Module";

  # Short description (shown in module list)
  description = "A brief description of what this module does";

  # Category for grouping in the UI
  # Options: development | database | infrastructure | monitoring | secrets | ci-cd | deployment | language | service | integration
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name (see: https://lucide.dev/icons)
  icon = "puzzle";

  # Link to documentation
  homepage = null;

  # Author or team
  author = "Stackpanel";

  # Searchable tags
  tags = [ ];

  # Module dependencies (other module IDs that must be enabled)
  requires = [ ];

  # Conflicting modules (cannot be enabled together)
  conflicts = [ ];

  # Feature flags - declare what this module provides
  # Used for UI filtering and display
  features = {
    files = false; # Generates config files
    scripts = false; # Provides shell commands
    healthchecks = false; # Has health checks
    packages = false; # Adds packages to devshell
    services = false; # Runs background services
    secrets = false; # Manages secrets
    tasks = false; # Provides turbo/build tasks
    appModule = false; # Adds per-app configuration options
  };

  # Priority for ordering (lower = higher priority)
  priority = 100;
}
