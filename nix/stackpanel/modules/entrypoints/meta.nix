# ==============================================================================
# meta.nix - Entrypoints Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "entrypoints";

  # Display name
  name = "Entrypoints";

  # Short description
  description = "Per-app sourceable scripts for environment setup (devshell, secrets)";

  # Category for UI grouping
  category = "deployment";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "play";

  # Documentation link
  homepage = null;

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "entrypoints"
    "scripts"
    "deployment"
    "secrets"
    "devshell"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = true;         # Generates entrypoint scripts
    scripts = false;
    healthchecks = false;
    packages = true;      # Creates entrypoint derivations
    services = false;
    secrets = false;
    tasks = false;
    appModule = true;     # Adds per-app entrypoint.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 40;
}
