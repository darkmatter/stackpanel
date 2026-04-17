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
rec {
  # Unique identifier (should match directory name)
  id = "age-utils";

  # Display name
  name = "AGE Utils";

  # Short description (shown in module list)
  description = "Utilities for managing AGE secrets";

  # Category for grouping in the UI
  # Options: development | database | infrastructure | monitoring | secrets | ci-cd | deployment | language | service | integration
  category = "secrets";

  # Semantic version
  version = "1.0.0";

  # Lucide icon name (see: https://lucide.dev/icons)
  icon = "key";

  # Link to documentation
  homepage = null;

  # Author or team
  author = "Darkmatter";

  # Searchable tags
  tags = [ ];

  # Module dependencies (other module IDs that must be enabled)
  requires = [ ];

  # Conflicting modules (cannot be enabled together)
  # conflicts = [ ];

  # Feature flags - declare what this module provides
  # Used for UI filtering and display
  # features = {
  #   files = true; # Generates config files
  #   scripts = true; # Provides shell commands
  #   healthchecks = false; # Has health checks
  #   packages = false; # Adds packages to devshell
  #   services = false; # Runs background services
  #   secrets = true; # Manages secrets
  #   tasks = false; # Provides turbo/build tasks
  #   appModule = false; # Adds per-app configuration options
  # };

  # Flake inputs required by this module (for auto-installation from registry)
  # Each entry: { name = "input-name"; url = "github:..."; followsNixpkgs = true; }
  # When this module is installed via the registry, these inputs are automatically
  # added to the consumer's flake.nix using tree-sitter.
  # flakeInputs = [
  #   { name = "agenix"; url = "github:ryantm/agenix";  followsNixpkgs = true; }
  #   { name = "agenix-rekey"; url = "github:oddlama/agenix-rekey"; followsNixpkgs = true; }
  #   { name = "agenix-shell"; url = "github:aciceri/agenix-shell"; followsNixpkgs = true; }
  #  ];

  # Priority for ordering (lower = higher priority)
  priority = 100;

  # Configuration boilerplate to inject into user's config.nix when module is installed
  # This should be a commented-out example config that users can uncomment/modify
  # The boilerplate will be injected into the "# STACKPANEL_MODULES_BEGIN" section
  # @TODO this doesnt exist in schema - should it?
  # configBoilerplate = ''
  #   # ${name} - ${description}
  #   # See: ${if homepage != null then homepage else "https://darkmatter.ai/docs/modules/${id}"}
  #   # age-utils = { enable = true; };
  # '';
}
