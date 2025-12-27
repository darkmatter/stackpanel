# ==============================================================================
# schemas.nix
#
# JSON Schema definitions for secrets configuration validation.
# These schemas enable IDE autocompletion and validation for YAML config files.
#
# Schemas provided:
# - configSchema: Global secrets config (.stackpanel/secrets/config.yaml)
# - usersSchema: Team members with AGE keys (.stackpanel/secrets/users.yaml)
# - appConfigSchema: Per-app codegen config (.stackpanel/secrets/apps/*/config.yaml)
# - schemaSchema: Secret variable definitions (.stackpanel/secrets/apps/*/common.yaml)
# - envSchema: Environment-specific secrets (.stackpanel/secrets/apps/*/{dev,staging,prod}.yaml)
#
# Usage: Import this module and access schemas via the `allSchemas` attribute
# for iteration, or individual schema attributes for specific access.
# ==============================================================================
{ lib, ... }:

let
  # config.schema.json - Global secrets configuration
  configSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "Stackpanel Secrets Configuration";
    description = "Global secrets configuration (.stackpanel/secrets/config.yaml)";
    type = "object";
    properties = {
      backend = {
        type = "string";
        enum = ["sops" "vals"];
        default = "sops";
        description = "Secrets backend to use (sops or vals)";
      };
      default-environments = {
        type = "array";
        items = { type = "string"; };
        default = ["dev" "staging" "prod"];
        description = "Default environments created for new apps";
      };
    };
    additionalProperties = false;
  };

  # users.schema.json - Team members with access to secrets
  usersSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "Stackpanel Users";
    description = "Team members with access to secrets (.stackpanel/secrets/users.yaml)";
    type = "object";
    additionalProperties = {
      type = "object";
      properties = {
        pubkey = {
          type = "string";
          pattern = "^age1[a-z0-9]{58}$";
          description = "AGE public key (starts with age1...)";
        };
        github = {
          type = "string";
          description = "GitHub username (for key lookup)";
        };
        admin = {
          type = "boolean";
          default = false;
          description = "Admins can decrypt secrets for all environments";
        };
      };
      required = ["pubkey"];
      additionalProperties = false;
    };
  };

  # app-config.schema.json - Per-app secrets and codegen configuration
  appConfigSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "App Secrets Configuration";
    description = "Per-app secrets and codegen config (.stackpanel/secrets/apps/*/config.yaml)";
    type = "object";
    properties = {
      codegen = {
        type = "object";
        description = "Code generation settings for type-safe env access";
        properties = {
          language = {
            type = "string";
            enum = ["typescript" "python" "go"];
            description = "Target language for generated code";
          };
          path = {
            type = "string";
            description = "Output path relative to project root (e.g., packages/api/src/env.ts)";
          };
        };
        required = ["language" "path"];
        additionalProperties = false;
      };
    };
    additionalProperties = false;
  };

  # schema.schema.json - Secret variable schema definition
  schemaSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "Secret Schema";
    description = "Schema for secret variables (.stackpanel/secrets/apps/*/common.yaml)";
    type = "object";
    additionalProperties = {
      type = "object";
      description = "Secret variable definition";
      properties = {
        required = {
          type = "boolean";
          default = false;
          description = "Whether this secret must be set";
        };
        sensitive = {
          type = "boolean";
          default = true;
          description = "Whether to mask value in logs and output";
        };
        description = {
          type = "string";
          description = "Human-readable description of this secret";
        };
        default = {
          type = "string";
          description = "Default value (only for non-sensitive secrets)";
        };
      };
      additionalProperties = false;
    };
  };

  # env.schema.json - Environment-specific secrets and access
  envSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "Environment Secrets";
    description = "Environment-specific secrets (.stackpanel/secrets/apps/*/{dev,staging,prod}.yaml)";
    type = "object";
    properties = {
      users = {
        type = "array";
        items = { type = "string"; };
        description = "Usernames (from users.yaml) who can access this environment";
      };
      schema = {
        type = "object";
        description = "Environment-specific schema overrides (merged with common.yaml)";
        additionalProperties = {
          type = "object";
          properties = {
            required = { type = "boolean"; };
            sensitive = { type = "boolean"; };
            description = { type = "string"; };
            default = { type = "string"; };
          };
          additionalProperties = false;
        };
      };
    };
    additionalProperties = false;
  };

in {
  inherit configSchema usersSchema appConfigSchema schemaSchema envSchema;

  # All schemas as an attrset for easy iteration
  allSchemas = {
    "config.schema.json" = configSchema;
    "users.schema.json" = usersSchema;
    "app-config.schema.json" = appConfigSchema;
    "schema.schema.json" = schemaSchema;
    "env.schema.json" = envSchema;
  };
}
