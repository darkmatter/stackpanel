# ==============================================================================
# nix/stackpanel/db/default.nix
#
# Database schema module for Stackpanel protobuf definitions.
#
# This module aggregates all .proto.nix schemas and provides utilities for:
#   - Proto file generation (Nix → .proto)
#   - Buf integration for Go/TypeScript codegen
#   - Schema introspection for tooling
#   - Nix option generation from proto messages
#
# The .proto.nix files are the SINGLE SOURCE OF TRUTH for data types.
# Generated code lives in packages/proto/gen/{go,ts}.
#
# Usage:
#   # List all schemas
#   nix eval --json -f nix/stackpanel/db '.schemas' --apply builtins.attrNames
#
#   # Render a single proto file
#   nix eval --raw -f nix/stackpanel/db '.render.users'
#
#   # Get all proto file names
#   nix eval --json -f nix/stackpanel/db '.protoFiles'
# ==============================================================================
{
  lib ? (import <nixpkgs> { }).lib,
}:
let
  # Import the proto library
  proto = import ./lib/proto.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Schema imports - all .proto.nix files
  # ---------------------------------------------------------------------------
  schemas = {
    # Core schemas
    config = import ./schemas/config.proto.nix { inherit lib; };
    users = import ./schemas/users.proto.nix { inherit lib; };

    # Feature schemas
    apps = import ./schemas/apps.proto.nix { inherit lib; };
    aws = import ./schemas/aws.proto.nix { inherit lib; };
    commands = import ./schemas/commands.proto.nix { inherit lib; };
    databases = import ./schemas/databases.proto.nix { inherit lib; };
    dns = import ./schemas/dns.proto.nix { inherit lib; };
    extensions = import ./schemas/extensions.proto.nix { inherit lib; };
    onboarding = import ./schemas/onboarding.proto.nix { inherit lib; };
    secrets = import ./schemas/secrets.proto.nix { inherit lib; };
    services = import ./schemas/services.proto.nix { inherit lib; };
    shells = import ./schemas/shells.proto.nix { inherit lib; };
    step-ca = import ./schemas/step-ca.proto.nix { inherit lib; };
    theme = import ./schemas/theme.proto.nix { inherit lib; };

    # External schemas (synced from external sources)
    github-collaborators = import ./schemas/external/github-collaborators.proto.nix { inherit lib; };
  };

  # ---------------------------------------------------------------------------
  # Schema categorization
  # ---------------------------------------------------------------------------

  # Schemas that go in .stackpanel/data/
  dataSchemas = {
    inherit (schemas)
      users
      apps
      aws
      commands
      databases
      dns
      extensions
      onboarding
      secrets
      services
      shells
      step-ca
      theme
      ;
  };

  # Schemas for .stackpanel/ root
  rootSchemas = {
    inherit (schemas) config;
  };

  # External data schemas (synced, not user-edited)
  externalSchemas = {
    inherit (schemas) github-collaborators;
  };

  # ---------------------------------------------------------------------------
  # Proto rendering utilities
  # ---------------------------------------------------------------------------

  # Render each schema to its .proto text
  render = lib.mapAttrs (_: schema: proto.renderProtoFile schema) schemas;

  # Get list of all proto file names
  protoFiles = lib.mapAttrsToList (_: schema: schema.name) schemas;

  # Get proto file name for each schema key
  protoFileMap = lib.mapAttrs (_: schema: schema.name) schemas;

  # ---------------------------------------------------------------------------
  # Schema introspection for tooling
  # ---------------------------------------------------------------------------

  # Extract message names from a schema
  getMessageNames = schema: lib.attrNames (schema.messages or { });

  # Extract enum names from a schema
  getEnumNames = schema: lib.attrNames (schema.enums or { });

  # Get all message names across all schemas (prefixed with schema name)
  allMessages = lib.concatLists (
    lib.mapAttrsToList (
      schemaName: schema: map (msgName: "${schemaName}.${msgName}") (getMessageNames schema)
    ) schemas
  );

  # Get all enum names across all schemas
  allEnums = lib.concatLists (
    lib.mapAttrsToList (
      schemaName: schema: map (enumName: "${schemaName}.${enumName}") (getEnumNames schema)
    ) schemas
  );

  # ---------------------------------------------------------------------------
  # Entity names for iteration
  # ---------------------------------------------------------------------------
  entityNames = lib.attrNames schemas;
  dataEntityNames = lib.attrNames dataSchemas;
  externalEntityNames = lib.attrNames externalSchemas;

  # ---------------------------------------------------------------------------
  # Init files for scaffolding
  # Generates default/empty data files for each entity
  # ---------------------------------------------------------------------------
  initFiles =
    let
      # Generate an empty data file for a data schema
      mkDataFile = name: _schema: {
        name = ".stackpanel/data/${snakeToKebab name}.nix";
        value = ''
          # ${snakeToKebab name}.nix - Auto-generated by stackpanel scaffold
          # Edit this file to configure ${name}
          { }
        '';
      };

      # Config file template
      configFile = {
        ".stackpanel/config.nix" = ''
          # Stackpanel project configuration
          # See: https://stackpanel.dev/docs/config
          {
            enable = true;
            name = "my-project";
            github = "owner/repo";
          }
        '';
      };

      # Generate data files from dataSchemas
      dataFiles = lib.listToAttrs (lib.mapAttrsToList mkDataFile dataSchemas);
    in
    configFile // dataFiles;

  # ---------------------------------------------------------------------------
  # Nix option type builders from proto schemas
  #
  # These helpers allow core/options to derive Nix module options from proto
  # message definitions, maintaining the proto as the source of truth.
  # ---------------------------------------------------------------------------

  # Convert snake_case to kebab-case
  snakeToKebab = str: builtins.replaceStrings [ "_" ] [ "-" ] str;

  # Convert kebab-case to snake_case
  kebabToSnake = str: builtins.replaceStrings [ "-" ] [ "_" ] str;

  # Map proto field types to Nix types
  protoTypeToNix =
    {
      field,
      allMessages ? { },
    }:
    let
      # Check if it's a message reference
      isMessageRef =
        !(builtins.elem field.type [
          "string"
          "int32"
          "int64"
          "uint32"
          "uint64"
          "bool"
          "double"
          "float"
          "bytes"
        ]);

      baseType =
        if isMessageRef then
          # For message references, create a submodule if we have the message definition
          if allMessages ? ${field.type} then
            lib.types.submodule {
              options = mkOptionsFromMessage {
                message = allMessages.${field.type};
                inherit allMessages;
              };
            }
          else
            # Fallback to attrs if message not found
            lib.types.attrs
        else
          {
            string = lib.types.str;
            int32 = lib.types.int;
            int64 = lib.types.int;
            uint32 = lib.types.ints.unsigned;
            uint64 = lib.types.ints.unsigned;
            bool = lib.types.bool;
            double = lib.types.float;
            float = lib.types.float;
            bytes = lib.types.str; # Base64 encoded
          }
          .${field.type} or lib.types.str;
    in
    if field.mapKey != null then
      lib.types.attrsOf baseType
    else if field.repeated then
      lib.types.listOf baseType
    else if field.optional then
      lib.types.nullOr baseType
    else
      baseType;

  # Get default value for a proto field
  getFieldDefault =
    field:
    if field.optional then
      null
    else if field.repeated then
      [ ]
    else if field.mapKey != null then
      { }
    else if field.type == "bool" then
      false
    else if field.type == "string" then
      ""
    else if
      builtins.elem field.type [
        "int32"
        "int64"
        "uint32"
        "uint64"
      ]
    then
      0
    else if
      builtins.elem field.type [
        "float"
        "double"
      ]
    then
      0.0
    else
      { }; # message type defaults to empty attrset

  # Build a single Nix option from a proto field
  mkOptionFromField =
    {
      field,
      allMessages ? { },
    }:
    lib.mkOption {
      type = protoTypeToNix { inherit field allMessages; };
      description = field.description or "";
      default = getFieldDefault field;
    };

  # Build Nix options from a proto message's fields
  # Converts field names from snake_case to kebab-case
  mkOptionsFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
    }:
    lib.mapAttrs' (
      fieldName: field:
      let
        nixFieldName = if useKebabCase then snakeToKebab fieldName else fieldName;
      in
      {
        name = nixFieldName;
        value = mkOptionFromField { inherit field allMessages; };
      }
    ) (message.fields or { });

  # Build a submodule type from a proto message
  mkSubmoduleFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
    }:
    lib.types.submodule {
      options = mkOptionsFromMessage { inherit message allMessages useKebabCase; };
    };

  # Build a complete option (with type, description, default) from a proto message
  # This is the main entry point for core/options to use
  mkOptionFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
      description ? message.description or "",
      default ? { },
      example ? null,
    }:
    lib.mkOption {
      type = mkSubmoduleFromMessage { inherit message allMessages useKebabCase; };
      inherit description default;
    }
    // (if example != null then { inherit example; } else { });

  # Build an attrsOf option for map-style messages (like Users, Apps, etc.)
  mkMapOptionFromMessage =
    {
      message, # The value message (e.g., User, App)
      allMessages ? { },
      useKebabCase ? true,
      description ? "",
      default ? { },
      example ? null,
    }:
    lib.mkOption {
      type = lib.types.attrsOf (mkSubmoduleFromMessage {
        inherit message allMessages useKebabCase;
      });
      inherit description default;
    }
    // (if example != null then { inherit example; } else { });

  # ---------------------------------------------------------------------------
  # Pre-built option sets from proto messages
  # These can be imported directly in core/options files
  # ---------------------------------------------------------------------------

  # Helper to get all messages from a schema for nested resolution
  getSchemaMessages = schema: schema.messages or { };

  # AWS options
  awsMessages = getSchemaMessages schemas.aws;
  awsRolesAnywhereOptions = mkOptionsFromMessage {
    message = schemas.aws.messages.RolesAnywhere or { fields = { }; };
    allMessages = awsMessages;
  };

  # Users options
  usersMessages = getSchemaMessages schemas.users;
  userOptions = mkOptionsFromMessage {
    message = schemas.users.messages.User or { fields = { }; };
    allMessages = usersMessages;
  };

  # Apps options
  appsMessages = getSchemaMessages schemas.apps;
  appOptions = mkOptionsFromMessage {
    message = schemas.apps.messages.App or { fields = { }; };
    allMessages = appsMessages;
  };

  # Commands options
  commandsMessages = getSchemaMessages schemas.commands;
  commandOptions = mkOptionsFromMessage {
    message = schemas.commands.messages.Command or { fields = { }; };
    allMessages = commandsMessages;
  };

  # Secrets options
  secretsMessages = getSchemaMessages schemas.secrets;
  secretsOptions = mkOptionsFromMessage {
    message = schemas.secrets.messages.Secrets or { fields = { }; };
    allMessages = secretsMessages;
  };
  secretsEnvironmentOptions = mkOptionsFromMessage {
    message = schemas.secrets.messages.SecretsEnvironment or { fields = { }; };
    allMessages = secretsMessages;
  };
  secretsCodegenOptions = mkOptionsFromMessage {
    message = schemas.secrets.messages.Codegen or { fields = { }; };
    allMessages = secretsMessages;
  };

  # Step CA options
  stepCaMessages = getSchemaMessages schemas.step-ca;
  stepCaOptions = mkOptionsFromMessage {
    message = schemas.step-ca.messages.StepCaConfig or { fields = { }; };
    allMessages = stepCaMessages;
  };

  # Theme options
  themeMessages = getSchemaMessages schemas.theme;
  themeOptions = mkOptionsFromMessage {
    message = schemas.theme.messages.Theme or { fields = { }; };
    allMessages = themeMessages;
  };
  colorSchemeOptions = mkOptionsFromMessage {
    message = schemas.theme.messages.ColorScheme or { fields = { }; };
    allMessages = themeMessages;
  };
  starshipOptions = mkOptionsFromMessage {
    message = schemas.theme.messages.Starship or { fields = { }; };
    allMessages = themeMessages;
  };

  # DNS options
  dnsMessages = getSchemaMessages schemas.dns;
  dnsOptions = mkOptionsFromMessage {
    message = schemas.dns.messages.Dns or schemas.dns.messages.DNS or { fields = { }; };
    allMessages = dnsMessages;
  };

  # Databases options
  databasesMessages = getSchemaMessages schemas.databases;
  databaseOptions = mkOptionsFromMessage {
    message =
      schemas.databases.messages.DatabaseInstance or schemas.databases.messages.Database or {
        fields = { };
      };
    allMessages = databasesMessages;
  };

  # Services options
  servicesMessages = getSchemaMessages schemas.services;
  serviceOptions = mkOptionsFromMessage {
    message = schemas.services.messages.Service or { fields = { }; };
    allMessages = servicesMessages;
  };

  # Shells options
  shellsMessages = getSchemaMessages schemas.shells;
  shellOptions = mkOptionsFromMessage {
    message = schemas.shells.messages.Shell or { fields = { }; };
    allMessages = shellsMessages;
  };

  # Extensions options
  extensionsMessages = getSchemaMessages schemas.extensions;
  extensionOptions = mkOptionsFromMessage {
    message = schemas.extensions.messages.Extension or { fields = { }; };
    allMessages = extensionsMessages;
  };

  # Onboarding options
  onboardingMessages = getSchemaMessages schemas.onboarding;
  onboardingOptions = mkOptionsFromMessage {
    message = schemas.onboarding.messages.Onboarding or { fields = { }; };
    allMessages = onboardingMessages;
  };

  # Config options
  configMessages = getSchemaMessages schemas.config;
  configOptions = mkOptionsFromMessage {
    message = schemas.config.messages.Config or { fields = { }; };
    allMessages = configMessages;
  };

  # ---------------------------------------------------------------------------
  # Extension object - for use in core/options
  # ---------------------------------------------------------------------------
  extend = {
    # Pre-built option sets (can be spread into options)
    aws = awsRolesAnywhereOptions;
    user = userOptions;
    app = appOptions;
    command = commandOptions;
    secrets = secretsOptions;
    secretsEnvironment = secretsEnvironmentOptions;
    secretsCodegen = secretsCodegenOptions;
    stepCa = stepCaOptions;
    theme = themeOptions;
    colorScheme = colorSchemeOptions;
    starship = starshipOptions;
    dns = dnsOptions;
    database = databaseOptions;
    service = serviceOptions;
    shell = shellOptions;
    extension = extensionOptions;
    onboarding = onboardingOptions;
    config = configOptions;

    # Message definitions for custom option building
    messages = {
      aws = awsMessages;
      users = usersMessages;
      apps = appsMessages;
      commands = commandsMessages;
      secrets = secretsMessages;
      stepCa = stepCaMessages;
      theme = themeMessages;
      dns = dnsMessages;
      databases = databasesMessages;
      services = servicesMessages;
      shells = shellsMessages;
      extensions = extensionsMessages;
      onboarding = onboardingMessages;
      config = configMessages;
    };
  };

in
{
  # Schema definitions
  inherit
    schemas
    dataSchemas
    rootSchemas
    externalSchemas
    ;

  # Entity name lists
  inherit entityNames dataEntityNames externalEntityNames;

  # Scaffolding
  inherit initFiles;

  # Proto rendering
  inherit render protoFiles protoFileMap;

  # Introspection
  inherit
    getMessageNames
    getEnumNames
    allMessages
    allEnums
    ;

  # Proto library for direct use
  inherit proto;
  lib = proto;

  # Options extension for core/options
  inherit extend;

  # Type conversion utilities
  inherit
    snakeToKebab
    kebabToSnake
    protoTypeToNix
    getFieldDefault
    mkOptionFromField
    mkOptionsFromMessage
    mkSubmoduleFromMessage
    mkOptionFromMessage
    mkMapOptionFromMessage
    ;
}
