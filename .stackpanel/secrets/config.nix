# Global secrets configuration for stackpanel.secrets module
# This file is imported by the Nix module and can be edited by the web UI
{
  # Enable secrets management
  enable = true;

  # Directory for encrypted secrets files
  secretsDir = "secrets";

  # Generate placeholder .yaml files for each environment
  generatePlaceholders = true;

  # Backend for secret resolution
  # Supported: "vals" (recommended), "sops"
  # vals supports SOPS files via ref+sops:// so it's backwards compatible
  backend = "vals";

  # Default environments for all apps
  # Apps can override with their own environment config
  defaultEnvironments = ["dev" "staging" "prod"];
}
