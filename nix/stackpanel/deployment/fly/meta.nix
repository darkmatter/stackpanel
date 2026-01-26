# ==============================================================================
# meta.nix - Fly.io Deployment Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "deploy-fly";

  # Display name
  name = "Fly.io Deployment";

  # Short description
  description = "Deploy containerized applications to Fly.io with nix2container";

  # Category for UI grouping
  category = "deployment";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "rocket";

  # Documentation link
  homepage = "https://fly.io/docs/";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "fly"
    "fly.io"
    "deployment"
    "container"
    "nix2container"
    "docker"
    "cloud"
    "hosting"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = true; # Generates fly.toml and deploy scripts
    scripts = true; # Provides deploy scripts
    healthchecks = true; # Deployment health checks
    packages = true; # Creates container derivations
    services = false;
    secrets = false;
    tasks = true; # Generates turbo deploy tasks
    appModule = true; # Adds per-app deployment.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 25;
}
