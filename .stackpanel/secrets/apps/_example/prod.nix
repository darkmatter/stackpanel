# Production environment configuration for this app
# This file is imported by the Nix module and can be edited by the web UI
{
  # Schema additions/overrides for production
  schema = {
    # Example: Sentry for error tracking in prod
    # SENTRY_DSN = {
    #   required = true;
    #   sensitive = true;
    #   description = "Sentry error tracking DSN";
    # };
  };

  # Users who can access production secrets (should be limited!)
  users = [];

  # Additional AGE keys (CI/CD systems for deployment)
  extraKeys = [];
}
