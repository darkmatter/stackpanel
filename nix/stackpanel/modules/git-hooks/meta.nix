# ==============================================================================
# meta.nix - Git Hooks Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  # Unique identifier (matches directory name)
  id = "git-hooks";

  # Display name
  name = "Git Hooks";

  # Short description
  description = "Git hooks integration with pre-commit linters and formatters";

  # Category for UI grouping
  category = "development";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name
  icon = "git-branch";

  # Documentation link
  homepage = null;

  # Author
  author = "Stackpanel";

  # Searchable tags
  tags = [
    "git"
    "hooks"
    "pre-commit"
    "linting"
    "formatting"
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

  # Flake inputs required by this module
  flakeInputs = [
    {
      name = "git-hooks";
      url = "https://flakehub.com/f/cachix/git-hooks.nix/*";
      followsNixpkgs = true;
    }
  ];

  # Priority for ordering (lower = higher priority)
  priority = 80;
}
