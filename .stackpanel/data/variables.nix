{
  AOU-KEY = {
    description = "ad";
    name = "AOU_KEY";
    type = "config";
  };
  API-URL = {
    description = "Backend API URL";
    key = "API_URL";
    type = "VARIABLE";
    value = "http://localhost:3001";
  };
  APP-URL = {
    description = "Public application URL";
    key = "APP_URL";
    type = "VARIABLE";
    value = "http://localhost:3000";
  };
  AUTH-SECRET = {
    description = "Secret key for session signing";
    key = "AUTH_SECRET";
    type = "SECRET";
    value = "";
  };
  AUTH-URL = {
    description = "Authentication service URL";
    key = "AUTH_URL";
    type = "VARIABLE";
    value = "http://localhost:3000/api/auth";
  };
  COOL-VAR = {
    default = "asd";
    description = "cool var";
    name = "COOL_VAR";
    sensitive = true;
    type = "secret";
  };
  DATABASE-HOST = {
    description = "PostgreSQL host";
    key = "DATABASE_HOST";
    type = "VARIABLE";
    value = "localhost";
  };
  DATABASE-NAME = {
    description = "PostgreSQL database name";
    key = "DATABASE_NAME";
    type = "VARIABLE";
    value = "stackpanel";
  };
  DATABASE-PORT = {
    description = "PostgreSQL port";
    key = "DATABASE_PORT";
    type = "VARIABLE";
    value = "5432";
  };
  DATABASE-URL = {
    description = "PostgreSQL connection string";
    key = "DATABASE_URL";
    type = "SECRET";
    value = "";
  };
  ENABLE-DEBUG = {
    description = "Enable debug mode";
    key = "ENABLE_DEBUG";
    type = "VARIABLE";
    value = "false";
  };
  HOST = {
    description = "Application host";
    key = "HOST";
    type = "VARIABLE";
    value = "localhost";
  };
  LOG-LEVEL = {
    description = "Application log level";
    key = "LOG_LEVEL";
    type = "VARIABLE";
    value = "info";
  };
  NODE-ENV = {
    description = "Node.js environment";
    key = "NODE_ENV";
    type = "VARIABLE";
    value = "development";
  };
  OPENAI-API-KEY = {
    description = "OpenAI API key for AI features";
    key = "OPENAI_API_KEY";
    type = "SECRET";
    value = "";
  };
  PORT = {
    description = "Application port";
    key = "PORT";
    type = "VARIABLE";
    value = "3000";
  };
  REDIS-URL = {
    description = "Redis connection string";
    key = "REDIS_URL";
    type = "VARIABLE";
    value = "redis://localhost:6379";
  };
  REDIS-URL-PRODUCTION = {
    default = "postgresql://guser:password@localhost:5432/app";
    description = "stable port";
    name = "REDIS_URL_PRODUCTION";
    type = "secret";
  };
  S3-ACCESS-KEY = {
    description = "S3 access key ID";
    key = "S3_ACCESS_KEY";
    type = "SECRET";
    value = "";
  };
  S3-BUCKET = {
    description = "S3 bucket name for file storage";
    key = "S3_BUCKET";
    type = "VARIABLE";
    value = "";
  };
  S3-REGION = {
    description = "S3 bucket region";
    key = "S3_REGION";
    type = "VARIABLE";
    value = "us-east-1";
  };
  S3-SECRET-KEY = {
    description = "S3 secret access key";
    key = "S3_SECRET_KEY";
    type = "SECRET";
    value = "";
  };
  SMTP-HOST = {
    description = "SMTP server host";
    key = "SMTP_HOST";
    type = "VARIABLE";
    value = "";
  };
  SMTP-PASSWORD = {
    description = "SMTP password";
    key = "SMTP_PASSWORD";
    type = "SECRET";
    value = "";
  };
  SMTP-PORT = {
    description = "SMTP server port";
    key = "SMTP_PORT";
    type = "VARIABLE";
    value = "587";
  };
  SMTP-USER = {
    description = "SMTP username";
    key = "SMTP_USER";
    type = "SECRET";
    value = "";
  };
  STRIPE-PUBLISHABLE-KEY = {
    description = "Stripe publishable API key";
    key = "STRIPE_PUBLISHABLE_KEY";
    type = "VARIABLE";
    value = "";
  };
  STRIPE-SECRET-KEY = {
    description = "Stripe secret API key";
    key = "STRIPE_SECRET_KEY";
    type = "SECRET";
    value = "";
  };
  STRIPE-WEBHOOK-SECRET = {
    description = "Stripe webhook signing secret";
    key = "STRIPE_WEBHOOK_SECRET";
    type = "SECRET";
    value = "";
  };
}
