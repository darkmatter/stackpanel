# Common/shared secrets schema for this app
# These are inherited by ALL environments
# Environment-specific files (dev.nix, prod.nix) can override these
#
# This file is imported by the Nix module and can be edited by the web UI
{
  # Example: Database connection (required everywhere)
  # DATABASE_URL = {
  #   required = true;
  #   sensitive = true;
  #   description = "PostgreSQL connection string";
  # };

  # Example: Log level with default (can be overridden per-env)
  # LOG_LEVEL = {
  #   required = false;
  #   sensitive = false;
  #   default = "info";
  # };
}
