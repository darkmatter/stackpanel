# Secrets module JSON Schema generation
# Generates JSON schemas for YAML config files (IDE intellisense)
{lib, genDir ? ".stackpanel/gen"}: let
  # JSON Schema draft version
  schemaVersion = "http://json-schema.org/draft-07/schema#";
  baseUri = "https://stackpanel.dev/schemas/secrets";

  # Convert Nix types to JSON Schema types
  nixTypeToJsonSchema = type:
    if type == "string"
    then {type = "string";}
    else if type == "bool"
    then {type = "boolean";}
    else if type == "int"
    then {type = "integer";}
    else if type == "list"
    then {type = "array";}
    else if type == "attrs"
    then {type = "object";}
    else {type = "string";}; # default

  # SecretEntry definition (used in schema.schema.json and env.schema.json)
  secretEntryDef = {
    type = "object";
    properties = {
      required = {
        type = "boolean";
        default = true;
        description = "Whether this secret is required";
      };
      sensitive = {
        type = "boolean";
        default = true;
        description = "Whether this secret is sensitive (masked in logs)";
      };
      description = {
        type = "string";
        description = "Description of what this secret is for";
      };
      default = {
        type = "string";
        description = "Default value (only for non-required secrets)";
      };
    };
    additionalProperties = false;
  };

  # AGE key pattern
  ageKeyPattern = "^age1[a-z0-9]{58}$";
in {
  # Generate all JSON schemas
  generateSchemas = {
    # config.schema.json - Global secrets configuration
    "config.schema.json" = builtins.toJSON {
      "$schema" = schemaVersion;
      "$id" = "${baseUri}/config.json";
      title = "Stackpanel Secrets Config";
      description = "Global configuration for the stackpanel secrets module";
      type = "object";
      properties = {
        backend = {
          type = "string";
          enum = ["vals" "sops"];
          default = "vals";
          description = ''
            Backend for secret resolution.
            - vals: Multi-backend resolver (SOPS, AWS, 1Password, Vault, Doppler)
            - sops: Direct SOPS usage only'';
        };
        secretsDir = {
          type = "string";
          default = "secrets";
          description = "Directory for encrypted secrets files (relative to repo root)";
        };
        generatePlaceholders = {
          type = "boolean";
          default = true;
          description = "Generate placeholder .yaml files for each app/environment";
        };
        defaultEnvironments = {
          type = "array";
          items.type = "string";
          default = ["dev" "staging" "prod"];
          description = "Default environments for all apps";
        };
      };
      additionalProperties = false;
    };

    # users.schema.json - Team members and AGE keys
    "users.schema.json" = builtins.toJSON {
      "$schema" = schemaVersion;
      "$id" = "${baseUri}/users.json";
      title = "Stackpanel Secrets Users";
      description = "Team members and their AGE public keys for secrets access";
      type = "object";
      additionalProperties = {"$ref" = "#/definitions/User";};
      definitions = {
        User = {
          type = "object";
          required = ["pubkey"];
          properties = {
            pubkey = {
              type = "string";
              pattern = ageKeyPattern;
              description = "AGE public key (starts with age1...)";
            };
            github = {
              type = "string";
              description = "GitHub username (for display/lookup)";
            };
            admin = {
              type = "boolean";
              default = false;
              description = "Admins can decrypt all secrets across all environments";
            };
          };
          additionalProperties = false;
        };
      };
      examples = [
        {
          alice = {
            pubkey = "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p";
            github = "alice";
            admin = true;
          };
          bob = {
            pubkey = "age1tpqft77pxl5qm7d7u0j5gsyvxzrxdg4krqjr3uvps7y0vfsueyeqg5ztsa";
            github = "bobdev";
          };
        }
      ];
    };

    # app-config.schema.json - Per-app codegen settings
    "app-config.schema.json" = builtins.toJSON {
      "$schema" = schemaVersion;
      "$id" = "${baseUri}/app-config.json";
      title = "Stackpanel App Secrets Config";
      description = "Per-app configuration for codegen and settings";
      type = "object";
      properties = {
        codegen = {
          type = "object";
          description = "Code generation settings for typed env access";
          properties = {
            language = {
              type = ["string" "null"];
              enum = ["typescript" "python" "go" null];
              description = "Target language for generated code (null to disable)";
            };
            path = {
              type = "string";
              description = "Output path for generated code (relative to repo root)";
              examples = [
                "packages/api/src/env.ts"
                "apps/server/env.py"
                "internal/env/env.go"
              ];
            };
          };
          required = ["language" "path"];
          additionalProperties = false;
        };
      };
      additionalProperties = false;
      examples = [
        {
          codegen = {
            language = "typescript";
            path = "packages/api/src/env.ts";
          };
        }
      ];
    };

    # schema.schema.json - Secret schema definition (common.yaml)
    "schema.schema.json" = builtins.toJSON {
      "$schema" = schemaVersion;
      "$id" = "${baseUri}/schema.json";
      title = "Stackpanel Secrets Schema";
      description = "Schema for secrets entries (common.yaml)";
      type = "object";
      additionalProperties = {"$ref" = "#/definitions/SecretEntry";};
      definitions = {
        SecretEntry = secretEntryDef;
      };
      examples = [
        {
          DATABASE_URL = {
            required = true;
            sensitive = true;
            description = "PostgreSQL connection string";
          };
          LOG_LEVEL = {
            required = false;
            sensitive = false;
            default = "info";
          };
        }
      ];
    };

    # env.schema.json - Per-environment config (dev.yaml, staging.yaml, prod.yaml)
    "env.schema.json" = builtins.toJSON {
      "$schema" = schemaVersion;
      "$id" = "${baseUri}/env.json";
      title = "Stackpanel Environment Config";
      description = "Per-environment configuration (dev.yaml, staging.yaml, prod.yaml)";
      type = "object";
      properties = {
        schema = {
          type = "object";
          description = "Environment-specific schema additions/overrides";
          additionalProperties = {"$ref" = "#/definitions/SecretEntry";};
        };
        users = {
          type = "array";
          items.type = "string";
          description = "User names (from users.yaml) who can access this environment's secrets";
        };
        extraKeys = {
          type = "array";
          items = {
            type = "string";
            pattern = ageKeyPattern;
          };
          description = "Additional AGE keys for CI systems, servers, etc.";
        };
      };
      definitions = {
        SecretEntry = secretEntryDef;
      };
      additionalProperties = false;
      examples = [
        {
          schema = {
            DEBUG = {
              required = false;
              sensitive = false;
            };
            LOG_LEVEL = {
              default = "debug";
            };
          };
          users = ["alice" "bob" "charlie"];
          extraKeys = [];
        }
        {
          schema = {
            SENTRY_DSN = {
              required = true;
              sensitive = true;
            };
          };
          users = ["alice"];
          extraKeys = ["age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p"];
        }
      ];
    };
  };

  # Generate devenv.files entries for schemas
  generateSchemaFiles = schemas:
    lib.mapAttrs' (name: content:
      lib.nameValuePair "${genDir}/schemas/secrets/${name}" {
        text = content;
      })
    schemas;
}
