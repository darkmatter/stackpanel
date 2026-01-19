# ==============================================================================
# variables.nix
#
# Workspace variables management - environment variables, secrets, and vals refs.
#
# This module imports options from the proto schema (db/schemas/variables.proto.nix)
# and provides the `stackpanel.variables` option for defining workspace-level
# variables that can be used across apps and environments.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
#
# SECRET HANDLING:
# ----------------
# Secrets cannot be decrypted at Nix evaluation time (the Nix store is
# world-readable). Instead, this module provides several resolution strategies:
#
#   1. `ref` - A vals-compatible reference for runtime resolution
#      Usage: env.FOO = config.stackpanel.variables."/my/secret".ref;
#      Result: FOO="ref+sops://.stackpanel/secrets/my/secret.age"
#
#   2. `envRef` - Environment variable reference (for direnv/dotenv workflows)
#      Usage: env.FOO = config.stackpanel.variables."/my/secret".envRef;
#      Result: FOO="${MY_SECRET}" (resolved by shell)
#
#   3. `fileRef` - Path to decrypted file (for runtime file-based secrets)
#      Usage: secretsFile = config.stackpanel.variables."/my/secret".fileRef;
#      Result: /run/secrets/my-secret (decrypted at activation)
#
# For VARIABLE type (non-secrets), you can use `.value` directly since
# there's nothing sensitive to protect.
#
# ==============================================================================
{
  lib,
  ...
}:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Secrets directory relative to project root
  secretsDir = ".stackpanel/secrets";

  # Convert variable ID to a safe filename
  # "/prod/api-key" -> "prod-api-key"
  idToFilename =
    id:
    let
      # Remove leading slash, replace remaining slashes with dashes
      cleaned = lib.removePrefix "/" id;
      replaced = builtins.replaceStrings [ "/" ] [ "-" ] cleaned;
    in
    replaced;

  # Variable submodule that uses proto-derived options + computed attributes
  variableModule =
    { config, name, ... }:
    {
      options =
        db.extend.variable
        // {
          # Computed: vals-compatible reference for runtime resolution
          ref = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              A vals-compatible reference for runtime secret resolution.
              
              - For VARIABLE: returns the value directly
              - For SECRET: returns ref+sops://path/to/secret.age
              - For VALS: returns the value (already a vals ref)
              
              Use this when you need the secret value at runtime, not eval time.
              A runtime resolver (vals, sops, or wrapper script) will decrypt it.
            '';
          };

          # Computed: environment variable reference (shell expansion)
          envRef = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              An environment variable reference that expands at shell runtime.
              Useful with direnv or when secrets are pre-loaded into the environment.
              
              Returns: ''${KEY_NAME}
            '';
          };

          # Computed: path to decrypted secret file (for file-based secrets)
          fileRef = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              Path where the decrypted secret file will be available at runtime.
              Useful for secrets that need to be read from files (e.g., TLS certs).
              
              Returns: /run/secrets/<secret-name> or similar
            '';
          };

          # Computed: safe value accessor
          # For VARIABLE type, returns value. For SECRET/VALS, returns a placeholder.
          safeValue = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              Safe accessor for the variable value.
              
              - For VARIABLE: returns the actual value (safe to embed in Nix store)
              - For SECRET: returns "__SECRET_<KEY>__" placeholder
              - For VALS: returns the vals reference
              
              Use this when you need a value at eval time but want to avoid
              accidentally exposing secrets. The placeholder can be replaced
              at runtime by a wrapper script.
            '';
          };
        };

      config = {
        # Default id to the attribute name if not specified
        id = lib.mkDefault name;

        # Compute the vals-compatible reference
        ref =
          let
            varType = config.type;
            filename = idToFilename config.id;
          in
          if varType == "VARIABLE" || varType == 0 then
            config.value
          else if varType == "SECRET" || varType == 1 then
            "ref+sops://${secretsDir}/${filename}.age#${config.key}"
          else if varType == "VALS" || varType == 2 then
            config.value
          else
            config.value;

        # Compute environment variable reference
        envRef = "\${${config.key}}";

        # Compute file reference path
        fileRef =
          let
            filename = idToFilename config.id;
          in
          "/run/secrets/${filename}";

        # Compute safe value
        safeValue =
          let
            varType = config.type;
          in
          if varType == "VARIABLE" || varType == 0 then
            config.value
          else if varType == "SECRET" || varType == 1 then
            "__SECRET_${config.key}__"
          else if varType == "VALS" || varType == 2 then
            config.value
          else
            config.value;
      };
    };
in
{
  options.stackpanel.variables = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule variableModule);
    default = { };
    description = ''
      Workspace variables - environment variables, secrets, and external refs.
      
      Each variable is keyed by a globally unique identifier. The id should be
      descriptive and can use path-style naming (e.g., "/dev/postgres-url").
      
      Variable types:
        - VARIABLE: Plain text value, passed as-is
        - SECRET: Encrypted with AGE, stored in secrets directory
        - VALS: Reference to external secret store (AWS SSM, Vault, etc.)
      
      Accessing values:
        - `.value`     - Raw value (ONLY use for VARIABLE type!)
        - `.ref`       - Vals-compatible reference for runtime resolution
        - `.envRef`    - Shell variable reference (''${KEY})
        - `.fileRef`   - Path to decrypted file
        - `.safeValue` - Safe accessor (placeholder for secrets)
      
      Example:
        stackpanel.variables = {
          "/dev/postgres-url" = {
            key = "POSTGRES_URL";
            type = "VARIABLE";
            value = "postgresql://localhost:5432/dev";
          };
          "/prod/api-key" = {
            key = "API_KEY";
            type = "SECRET";
            environments = [ "production" ];
          };
        };
        
        # In app config:
        stackpanel.apps.myapp.environments.prod.variables = {
          # Use .ref for runtime resolution (recommended for secrets)
          API_KEY = config.stackpanel.variables."/prod/api-key".ref;
          
          # Use .value directly for non-secrets
          DATABASE_URL = config.stackpanel.variables."/dev/postgres-url".value;
        };
    '';
    example = lib.literalExpression ''
      {
        "/dev/database-url" = {
          key = "DATABASE_URL";
          type = "VARIABLE";
          value = "postgresql://localhost:5432/myapp";
        };
        "/prod/api-key" = {
          key = "API_KEY";
          type = "SECRET";
          environments = [ "production" ];
        };
      }
    '';
  };
}
