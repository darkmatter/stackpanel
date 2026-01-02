# Dev environment configuration for this app
# This file is imported by the Nix module and can be edited by the web UI
{
  # Schema additions/overrides for dev
  # These are merged with common.nix (dev values take precedence)
  schema = {
    # Example: Enable debug mode in dev
    # DEBUG = {
    #   required = false;
    #   sensitive = false;
    #   default = "true";
    # };

    # Example: Override common LOG_LEVEL for dev
    # LOG_LEVEL = {
    #   default = "debug";
    # };
  };

  # Users who can access dev secrets (from users.nix)
  users = [ ];

  # Additional AGE keys (CI systems, etc)
  extraKeys = [ ];
}
