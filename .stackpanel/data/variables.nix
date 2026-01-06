# ==============================================================================
# variables.nix
#
# Standalone environment variable definitions that can be linked to apps.
# Variables are defined once and referenced by ID in app definitions.
#
# Types:
#   - secret: Sensitive value stored encrypted (via sops/age)
#   - config: Non-sensitive configuration value
#   - computed: Derived from other config (e.g., URLs from ports)
#   - service: Auto-generated from service config (e.g., DATABASE_URL)
# ==============================================================================
{
  # Database variables
  DATABASE_URL = {
    name = "DATABASE_URL";
    description = "PostgreSQL connection string";
    type = "service";
    service = "postgres";
    required = true;
    sensitive = true;
  };

  DATABASE_HOST = {
    name = "DATABASE_HOST";
    description = "PostgreSQL host";
    type = "config";
    default = "localhost";
    required = false;
  };

  DATABASE_PORT = {
    name = "DATABASE_PORT";
    description = "PostgreSQL port";
    type = "service";
    service = "postgres";
    required = false;
  };

  DATABASE_NAME = {
    name = "DATABASE_NAME";
    description = "PostgreSQL database name";
    type = "config";
    required = true;
  };

  # Redis variables
  REDIS_URL = {
    name = "REDIS_URL";
    description = "Redis connection string";
    type = "service";
    service = "redis";
    required = false;
    sensitive = false;
  };

  # Authentication variables
  AUTH_SECRET = {
    name = "AUTH_SECRET";
    description = "Secret key for session signing";
    type = "secret";
    required = true;
    sensitive = true;
  };

  AUTH_URL = {
    name = "AUTH_URL";
    description = "Authentication service URL";
    type = "computed";
    required = false;
  };

  # API keys
  OPENAI_API_KEY = {
    name = "OPENAI_API_KEY";
    description = "OpenAI API key for AI features";
    type = "secret";
    required = false;
    sensitive = true;
  };

  STRIPE_SECRET_KEY = {
    name = "STRIPE_SECRET_KEY";
    description = "Stripe secret API key";
    type = "secret";
    required = false;
    sensitive = true;
  };

  STRIPE_PUBLISHABLE_KEY = {
    name = "STRIPE_PUBLISHABLE_KEY";
    description = "Stripe publishable API key";
    type = "config";
    required = false;
    sensitive = false;
  };

  STRIPE_WEBHOOK_SECRET = {
    name = "STRIPE_WEBHOOK_SECRET";
    description = "Stripe webhook signing secret";
    type = "secret";
    required = false;
    sensitive = true;
  };

  # Application config
  NODE_ENV = {
    name = "NODE_ENV";
    description = "Node.js environment";
    type = "config";
    required = true;
    default = "development";
    options = [
      "development"
      "staging"
      "production"
      "test"
    ];
  };

  PORT = {
    name = "PORT";
    description = "Application port";
    type = "computed";
    required = false;
  };

  HOST = {
    name = "HOST";
    description = "Application host";
    type = "config";
    default = "localhost";
    required = false;
  };

  APP_URL = {
    name = "APP_URL";
    description = "Public application URL";
    type = "computed";
    required = false;
  };

  API_URL = {
    name = "API_URL";
    description = "Backend API URL";
    type = "computed";
    required = false;
  };

  # Email
  SMTP_HOST = {
    name = "SMTP_HOST";
    description = "SMTP server host";
    type = "config";
    required = false;
  };

  SMTP_PORT = {
    name = "SMTP_PORT";
    description = "SMTP server port";
    type = "config";
    default = "587";
    required = false;
  };

  SMTP_USER = {
    name = "SMTP_USER";
    description = "SMTP username";
    type = "secret";
    required = false;
    sensitive = false;
  };

  SMTP_PASSWORD = {
    name = "SMTP_PASSWORD";
    description = "SMTP password";
    type = "secret";
    required = false;
    sensitive = true;
  };

  # Storage
  S3_BUCKET = {
    name = "S3_BUCKET";
    description = "S3 bucket name for file storage";
    type = "config";
    required = false;
  };

  S3_REGION = {
    name = "S3_REGION";
    description = "S3 bucket region";
    type = "config";
    default = "us-east-1";
    required = false;
  };

  S3_ACCESS_KEY = {
    name = "S3_ACCESS_KEY";
    description = "S3 access key ID";
    type = "secret";
    required = false;
    sensitive = true;
  };

  S3_SECRET_KEY = {
    name = "S3_SECRET_KEY";
    description = "S3 secret access key";
    type = "secret";
    required = false;
    sensitive = true;
  };

  # Logging
  LOG_LEVEL = {
    name = "LOG_LEVEL";
    description = "Application log level";
    type = "config";
    default = "info";
    options = [
      "debug"
      "info"
      "warn"
      "error"
    ];
    required = false;
  };

  # Feature flags
  ENABLE_DEBUG = {
    name = "ENABLE_DEBUG";
    description = "Enable debug mode";
    type = "config";
    default = "false";
    required = false;
  };
}
