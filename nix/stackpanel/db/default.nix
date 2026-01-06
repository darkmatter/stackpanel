# ==============================================================================
# nix/stackpanel/db/default.nix
#
# Database schema registry for Stackpanel protobuf definitions.
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
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                    HOW TO ADD A NEW SCHEMA                                  │
# │                                                                             │
# │  1. Create your schema file in schemas/<name>.proto.nix                     │
# │     (copy schemas/_template.proto.nix as a starting point)                  │
# │                                                                             │
# │  2. Register it in STEP 1 below (schemas = { ... })                         │
# │                                                                             │
# │  3. Categorize it in STEP 2 below (dataSchemas, rootSchemas, etc.)          │
# │                                                                             │
# │  4. Register options in STEP 3 below (entity options extraction)            │
# │                                                                             │
# │  5. Export options in STEP 4 below (extend = { ... })                       │
# │                                                                             │
# │  6. Run `nix run .#generate-protos` to regenerate Go/TS types               │
# └─────────────────────────────────────────────────────────────────────────────┘
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
  # Import libraries
  proto = import ./lib/proto.nix { inherit lib; };
  optionsLib = import ./lib/options.nix { inherit lib; };

  # Re-export commonly used functions from optionsLib for convenience
  inherit (optionsLib)
    snakeToKebab
    kebabToSnake
    protoTypeToNix
    getFieldDefault
    mkOptionFromField
    mkOptionsFromMessage
    mkSubmoduleFromMessage
    mkOptionFromMessage
    mkMapOptionFromMessage
    getSchemaMessages
    mkEntityOptions
    ;

  # ============================================================================
  #
  #   STEP 1: SCHEMA IMPORTS
  #
  #   Register your .proto.nix schema files here.
  #   Each schema is imported and made available for rendering and introspection.
  #
  #   Example:
  #     myfeature = import ./schemas/myfeature.proto.nix { inherit lib; };
  #
  # ============================================================================
  schemas = {
    # ──────────────────────────────────────────────────────────────────────────
    # Core schemas (required for stackpanel to function)
    # ──────────────────────────────────────────────────────────────────────────
    config = import ./schemas/config.proto.nix { inherit lib; };
    users = import ./schemas/users.proto.nix { inherit lib; };

    # ──────────────────────────────────────────────────────────────────────────
    # Feature schemas (optional features)
    # ──────────────────────────────────────────────────────────────────────────
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

    # ──────────────────────────────────────────────────────────────────────────
    # External schemas (synced from external sources, not user-edited)
    # ──────────────────────────────────────────────────────────────────────────
    github-collaborators = import ./schemas/external/github-collaborators.proto.nix { inherit lib; };

    # ──────────────────────────────────────────────────────────────────────────
    # ADD NEW SCHEMAS HERE
    # ──────────────────────────────────────────────────────────────────────────
    # myfeature = import ./schemas/myfeature.proto.nix { inherit lib; };
  };

  # ============================================================================
  #
  #   STEP 2: SCHEMA CATEGORIZATION
  #
  #   Assign your schema to the appropriate category. This determines:
  #     - dataSchemas: Goes in .stackpanel/data/<name>.nix (user-editable data)
  #     - rootSchemas: Goes in .stackpanel/ root (project config)
  #     - externalSchemas: Synced from external sources (not user-edited)
  #
  #   Example:
  #     dataSchemas = { inherit (schemas) myfeature; };
  #
  # ============================================================================

  # Schemas that generate data files in .stackpanel/data/
  # NOTE: Only include schemas that have corresponding options in core/options/
  dataSchemas = {
    inherit (schemas)
      users
      apps
      aws
      secrets
      step-ca
      theme
      ;
    # ADD NEW DATA SCHEMAS HERE (must also have options in core/options/):
    # myfeature
  };

  # Schemas that exist but don't yet have Nix options defined.
  # These are proto schemas only - no data files are generated for them.
  # When you add options for these, move them to dataSchemas above.
  pendingSchemas = {
    inherit (schemas)
      commands
      databases
      dns
      extensions
      onboarding
      services
      shells
      ;
  };

  # Schemas for .stackpanel/ root (project-level config)
  rootSchemas = {
    inherit (schemas) config;
  };

  # External data schemas (synced, not user-edited)
  externalSchemas = {
    inherit (schemas) github-collaborators;
  };

  # ============================================================================
  #
  #   STEP 3: ENTITY OPTIONS EXTRACTION
  #
  #   For each schema, extract the "top-level" message that represents a single
  #   entity. This is used to generate Nix module options.
  #
  #   ┌─────────────────────────────────────────────────────────────────────────┐
  #   │  IMPORTANT: Choosing the "Top-Level" Message                            │
  #   │                                                                         │
  #   │  Most schemas define two message types:                                 │
  #   │                                                                         │
  #   │    1. Singular (e.g., User, App) - defines ONE entity's fields          │
  #   │    2. Plural wrapper (e.g., Users, Apps) - wraps in map<string, Entity> │
  #   │                                                                         │
  #   │  You should extract the SINGULAR form here, because Nix options         │
  #   │  are structured as:                                                     │
  #   │                                                                         │
  #   │    stackpanel.users.<username>.name = "...";                            │
  #   │                      ↑ key          ↑ User message fields               │
  #   │                                                                         │
  #   │  NOT:                                                                   │
  #   │    stackpanel.users.users.<username>.name = "...";  # redundant!        │
  #   └─────────────────────────────────────────────────────────────────────────┘
  #
  #   Example for a new schema:
  #
  #     # Get all messages from the schema (for nested type resolution)
  #     myfeatureMessages = getSchemaMessages schemas.myfeature;
  #
  #     # Extract options from the singular entity message
  #     myfeatureOptions = mkOptionsFromMessage {
  #       message = schemas.myfeature.messages.MyFeature or { fields = { }; };
  #       allMessages = myfeatureMessages;
  #     };
  #
  # ============================================================================

  # ──────────────────────────────────────────────────────────────────────────
  # AWS
  # ──────────────────────────────────────────────────────────────────────────
  awsMessages = getSchemaMessages schemas.aws;
  awsRolesAnywhereOptions = mkOptionsFromMessage {
    message = schemas.aws.messages.RolesAnywhere or { fields = { }; };
    allMessages = awsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Users
  # ──────────────────────────────────────────────────────────────────────────
  usersMessages = getSchemaMessages schemas.users;
  userOptions = mkOptionsFromMessage {
    message = schemas.users.messages.User or { fields = { }; };
    allMessages = usersMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Apps
  # ──────────────────────────────────────────────────────────────────────────
  appsMessages = getSchemaMessages schemas.apps;
  appOptions = mkOptionsFromMessage {
    message = schemas.apps.messages.App or { fields = { }; };
    allMessages = appsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Commands
  # ──────────────────────────────────────────────────────────────────────────
  commandsMessages = getSchemaMessages schemas.commands;
  commandOptions = mkOptionsFromMessage {
    message = schemas.commands.messages.Command or { fields = { }; };
    allMessages = commandsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Secrets
  # ──────────────────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────────────────
  # Step CA
  # Note: Use StepCaConfig (the flat fields) not StepCa (the wrapper)
  # ──────────────────────────────────────────────────────────────────────────
  stepCaMessages = getSchemaMessages schemas.step-ca;
  stepCaOptions = mkOptionsFromMessage {
    message = schemas.step-ca.messages.StepCaConfig or { fields = { }; };
    allMessages = stepCaMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Theme
  # ──────────────────────────────────────────────────────────────────────────
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

  # ──────────────────────────────────────────────────────────────────────────
  # DNS
  # ──────────────────────────────────────────────────────────────────────────
  dnsMessages = getSchemaMessages schemas.dns;
  dnsOptions = mkOptionsFromMessage {
    message = schemas.dns.messages.DnsRecord or { fields = { }; };
    allMessages = dnsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Databases
  # ──────────────────────────────────────────────────────────────────────────
  databasesMessages = getSchemaMessages schemas.databases;
  databaseOptions = mkOptionsFromMessage {
    message =
      schemas.databases.messages.Database or {
        fields = { };
      };
    allMessages = databasesMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Services
  # ──────────────────────────────────────────────────────────────────────────
  servicesMessages = getSchemaMessages schemas.services;
  serviceOptions = mkOptionsFromMessage {
    message = schemas.services.messages.Service or { fields = { }; };
    allMessages = servicesMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Shells
  # ──────────────────────────────────────────────────────────────────────────
  shellsMessages = getSchemaMessages schemas.shells;
  shellOptions = mkOptionsFromMessage {
    message = schemas.shells.messages.Shell or { fields = { }; };
    allMessages = shellsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Extensions
  # ──────────────────────────────────────────────────────────────────────────
  extensionsMessages = getSchemaMessages schemas.extensions;
  extensionOptions = mkOptionsFromMessage {
    message = schemas.extensions.messages.Extension or { fields = { }; };
    allMessages = extensionsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Onboarding
  # ──────────────────────────────────────────────────────────────────────────
  onboardingMessages = getSchemaMessages schemas.onboarding;
  onboardingOptions = mkOptionsFromMessage {
    message = schemas.onboarding.messages.OnboardingStep or { fields = { }; };
    allMessages = onboardingMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Config
  # ──────────────────────────────────────────────────────────────────────────
  configMessages = getSchemaMessages schemas.config;
  configOptions = mkOptionsFromMessage {
    message = schemas.config.messages.Config or { fields = { }; };
    allMessages = configMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # ADD NEW ENTITY OPTIONS HERE
  # ──────────────────────────────────────────────────────────────────────────
  #
  # myfeatureMessages = getSchemaMessages schemas.myfeature;
  # myfeatureOptions = mkOptionsFromMessage {
  #   message = schemas.myfeature.messages.MyFeature or { fields = { }; };
  #   allMessages = myfeatureMessages;
  # };

  # ============================================================================
  #
  #   STEP 4: OPTIONS EXPORT (extend object)
  #
  #   Export your options so they can be used in core/options/*.nix files.
  #   This is what other parts of the codebase import to build Nix module options.
  #
  #   Example:
  #     extend = {
  #       myfeature = myfeatureOptions;
  #       messages = {
  #         myfeature = myfeatureMessages;
  #       };
  #     };
  #
  # ============================================================================
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

    # ADD NEW OPTIONS EXPORTS HERE:
    # myfeature = myfeatureOptions;

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

      # ADD NEW MESSAGE EXPORTS HERE:
      # myfeature = myfeatureMessages;
    };
  };

  # ============================================================================
  #
  #   INTERNAL: Proto rendering and introspection utilities
  #
  #   You typically don't need to modify anything below this line.
  #
  # ============================================================================

  # Render each schema to its .proto text
  render = lib.mapAttrs (_: schema: proto.renderProtoFile schema) schemas;

  # Get list of all proto file names
  protoFiles = lib.mapAttrsToList (_: schema: schema.name) schemas;

  # Get proto file name for each schema key
  protoFileMap = lib.mapAttrs (_: schema: schema.name) schemas;

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

  # Entity name lists
  entityNames = lib.attrNames schemas;
  dataEntityNames = lib.attrNames dataSchemas;
  externalEntityNames = lib.attrNames externalSchemas;

  # ============================================================================
  #
  #   INTERNAL: Scaffolding / init file generation
  #
  # ============================================================================
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

in
{
  # ============================================================================
  # PUBLIC API
  # ============================================================================

  # Schema definitions
  inherit
    schemas
    dataSchemas
    rootSchemas
    externalSchemas
    pendingSchemas
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

  # Options library for custom option building
  inherit optionsLib;

  # Options extension for core/options
  inherit extend;

  # Type conversion utilities (re-exported from optionsLib)
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
