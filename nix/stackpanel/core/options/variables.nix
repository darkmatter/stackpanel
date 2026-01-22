# ==============================================================================
# variables.nix
#
# Workspace variables management - literals, secrets, vals refs, and exec commands.
#
# This module imports options from the proto schema (db/schemas/variables.proto.nix)
# and extends them with computed attributes for runtime resolution.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Secrets directory relative to project root
  secretsDir = config.stackpanel.secrets.secrets-dir or ".stackpanel/secrets";

  # Convert variable ID to a safe filename
  # "/prod/api-key" -> "prod-api-key"
  idToFilename =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      replaced = builtins.replaceStrings [ "/" ] [ "-" ] cleaned;
    in
    replaced;

  # Variable submodule that uses proto-derived options + computed attributes
  variableModule =
    { config, name, ... }:
    {
      options =
        # Base options from proto schema (id, key, description, type, value, master-keys, etc.)
        db.extend.variable
        // {
          # Computed: vals-compatible reference for runtime resolution
          ref = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              A vals-compatible reference for runtime resolution.
              
              - LITERAL: returns the value directly
              - SECRET: returns ref+sops://path/to/secret.age
              - VALS: returns the value (already a vals ref)
              - EXEC: returns ref+exec://command
            '';
          };

          # Computed: environment variable reference (shell expansion)
          envRef = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              An environment variable reference: ''${KEY_NAME}
            '';
          };

          # Computed: path to the .age file (for SECRET type)
          agePath = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              Path to the encrypted .age file (only meaningful for SECRET type).
            '';
          };

          # Computed: safe value accessor
          safeValue = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = ''
              Safe accessor for the variable value.
              
              - LITERAL: returns the actual value
              - SECRET: returns "__SECRET_<KEY>__" placeholder
              - VALS: returns the vals reference
              - EXEC: returns "__EXEC_<KEY>__" placeholder
            '';
          };
        };

      config = {
        # Default id to the attribute name if not specified
        id = lib.mkDefault name;

        # Default master-keys to ["local"] for SECRET type
        master-keys = lib.mkDefault [ "local" ];

        # Compute the vals-compatible reference
        ref =
          let
            varType = config.type;
            filename = idToFilename config.id;
          in
          if varType == "LITERAL" || varType == 0 then
            config.value
          else if varType == "SECRET" || varType == 1 then
            "ref+sops://${secretsDir}/${filename}.age#${config.key}"
          else if varType == "VALS" || varType == 2 then
            config.value
          else if varType == "EXEC" || varType == 3 then
            "ref+exec://${lib.escapeShellArg config.value}"
          else
            config.value;

        # Compute environment variable reference
        envRef = "\${${config.key}}";

        # Compute .age file path
        agePath =
          let
            filename = idToFilename config.id;
          in
          "${secretsDir}/${filename}.age";

        # Compute safe value
        safeValue =
          let
            varType = config.type;
          in
          if varType == "LITERAL" || varType == 0 then
            config.value
          else if varType == "SECRET" || varType == 1 then
            "__SECRET_${config.key}__"
          else if varType == "VALS" || varType == 2 then
            config.value
          else if varType == "EXEC" || varType == 3 then
            "__EXEC_${config.key}__"
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
      Workspace variables - literals, secrets, vals refs, and exec commands.
      
      Each variable is keyed by a globally unique identifier. Recommended format:
      /path/based/variable-name (e.g., /prod/postgres-url).
      
      Variable types:
        - LITERAL: Plain text value, embedded directly
        - SECRET: Encrypted with AGE master keys
        - VALS: Reference to external secret store (AWS SSM, Vault, etc.)
        - EXEC: Shell command that outputs the value
      
      Accessing values:
        - .value     - Raw value (ONLY use for LITERAL type!)
        - .ref       - Vals-compatible reference for runtime resolution
        - .envRef    - Shell variable reference (''${KEY})
        - .agePath   - Path to .age file (for SECRET type)
        - .safeValue - Safe accessor (placeholder for secrets)
    '';
    example = lib.literalExpression ''
      {
        "/dev/postgres-url" = {
          key = "POSTGRES_URL";
          type = "LITERAL";
          value = "postgresql://localhost:5432/dev";
        };
        
        "/prod/postgres-url" = {
          key = "POSTGRES_URL";
          type = "SECRET";
          master-keys = [ "prod" ];
        };
        
        "/prod/stripe-key" = {
          key = "STRIPE_SECRET_KEY";
          type = "VALS";
          value = "ref+awsssm://prod/stripe/secret-key";
        };
        
        "/dev/git-commit" = {
          key = "GIT_COMMIT";
          type = "EXEC";
          value = "git rev-parse --short HEAD";
        };
      }
    '';
  };
}
