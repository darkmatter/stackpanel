# ==============================================================================
# meta.nix - Bun Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "bun";

  # Display name
  name = "Bun";

  # Short description
  description = "Bun/TypeScript application support with bun2nix packaging";

  # Category for UI grouping
  category = "language";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "zap";

  # Documentation link
  homepage = "https://nix-community.github.io/bun2nix/building-packages/hook.html";

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "bun"
    "bun2nix"
    "typescript"
    "javascript"
    "nodejs"
    "runtime"
    "package-manager"
  ];

  # Module dependencies
  requires = [ ];

  # Conflicting modules
  conflicts = [ ];

  # Feature flags
  features = {
    files = true;         # Generates package.json with bun2nix postinstall
    scripts = true; # Provides run-<app> and test-<app> scripts
    healthchecks = true;
    packages = true; # Builds Bun applications via bun2nix
    services = false;
    secrets = false;
    tasks = false;
    appModule = true; # Adds per-app bun.* options
  };

  # Priority for ordering (lower = higher priority)
  priority = 20;
}
