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
    mkAllOptionsFromSchema
    mkSchemaBundle
    pascalToCamel
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
    databases = import ./schemas/databases.proto.nix { inherit lib; };
    dns = import ./schemas/dns.proto.nix { inherit lib; };
    extensions = import ./schemas/extensions.proto.nix { inherit lib; };
    files = import ./schemas/files.proto.nix { inherit lib; };
    onboarding = import ./schemas/onboarding.proto.nix { inherit lib; };
    secrets = import ./schemas/secrets.proto.nix { inherit lib; };
    services = import ./schemas/services.proto.nix { inherit lib; };
    shells = import ./schemas/shells.proto.nix { inherit lib; };
    step-ca = import ./schemas/step-ca.proto.nix { inherit lib; };
    scripts = import ./schemas/scripts.proto.nix { inherit lib; };
    tasks = import ./schemas/tasks.proto.nix { inherit lib; };
    theme = import ./schemas/theme.proto.nix { inherit lib; };
    variables = import ./schemas/variables.proto.nix { inherit lib; };
    healthchecks = import ./schemas/healthchecks.proto.nix { inherit lib; };
    sst = import ./schemas/sst.proto.nix { inherit lib; };

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
  #     - dataSchemas: User-editable data in .stackpanel/data/<name>.nix
  #     - internalSchemas: Module-computed, not user-editable (no data file)
  #     - rootSchemas: Project config in .stackpanel/ root
  #     - externalSchemas: Synced from external sources (read-only)
  #
  #   ALL schemas get auto-generated Nix options via mkSchemaBundle.
  #   The difference is whether users edit a data file for that schema.
  #
  #   Example:
  #     dataSchemas = { inherit (schemas) myfeature; };  # Has boilerplate
  #     internalSchemas = { inherit (schemas) runtime; }; # No boilerplate
  #
  # ============================================================================

  # Schemas that generate data files in .stackpanel/data/
  # NOTE: Only include schemas that have corresponding options in core/options/
  dataSchemas = {
    inherit (schemas)
      users
      apps
      aws
      scripts
      secrets
      step-ca
      tasks
      theme
      variables
      ;
    # ADD NEW DATA SCHEMAS HERE (must also have options in core/options/):
    # myfeature
  };

  # Internal/runtime schemas - not user-editable data files.
  # These have proto definitions and auto-generated options, but no boilerplate
  # because they're computed by modules at runtime, not edited by users.
  #
  # Examples:
  #   - files: Generated files are defined in Nix modules, not data files
  #   - healthchecks: Runtime state computed by modules
  #   - services: Defined in Nix config (postgres, redis, etc.)
  #
  # If you're adding a schema that SHOULD have a user-editable data file,
  # add a `boilerplate` definition to the .proto.nix and move it to dataSchemas.
  internalSchemas = {
    inherit (schemas)
      databases
      dns
      extensions
      files
      healthchecks
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
  #   AUTO-GENERATED OPTIONS
  #
  #   All options are now auto-generated from schemas using mkSchemaBundle.
  #   This replaces the manual extraction that was previously required.
  #
  #   Access pattern:
  #     allSchemaBundles.users.options.user   => User message options
  #     allSchemaBundles.users.messages       => all messages for nested resolution
  #
  # ============================================================================
  allSchemaBundles = lib.mapAttrs (_: mkSchemaBundle) schemas;

  # Flatten all options from all schemas into a single attrset
  # Keys are camelCase message names: user, app, sstKms, etc.
  allOptions = lib.foldl' (
    acc: bundle: acc // bundle.options
  ) { } (lib.attrValues allSchemaBundles);

  # Flatten all messages from all schemas
  # Keys are schema names: users, apps, sst, etc.
  allMessages = lib.mapAttrs (_: bundle: bundle.messages) allSchemaBundles;

  # ============================================================================
  #
  #   LEGACY: MANUAL ENTITY OPTIONS EXTRACTION
  #
  #   These manual definitions are kept for backwards compatibility.
  #   New code should use allOptions.{messageName} or allSchemaBundles.{schema}.
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
  # Scripts
  # ──────────────────────────────────────────────────────────────────────────
  scriptsMessages = getSchemaMessages schemas.scripts;
  scriptOptions = mkOptionsFromMessage {
    message = schemas.scripts.messages.Script or { fields = { }; };
    allMessages = scriptsMessages;
  };
  scriptsConfigOptions = mkOptionsFromMessage {
    message = schemas.scripts.messages.ScriptsConfig or { fields = { }; };
    allMessages = scriptsMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Tasks
  # ──────────────────────────────────────────────────────────────────────────
  tasksMessages = getSchemaMessages schemas.tasks;
  taskOptions = mkOptionsFromMessage {
    message = schemas.tasks.messages.Task or { fields = { }; };
    allMessages = tasksMessages;
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
  # Variables
  # ──────────────────────────────────────────────────────────────────────────
  variablesMessages = getSchemaMessages schemas.variables;
  variableOptions = mkOptionsFromMessage {
    message = schemas.variables.messages.Variable or { fields = { }; };
    allMessages = variablesMessages;
  };
  variableActionOptions = mkOptionsFromMessage {
    message = schemas.variables.messages.VariableAction or { fields = { }; };
    allMessages = variablesMessages;
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
  extensionPanelOptions = mkOptionsFromMessage {
    message = schemas.extensions.messages.ExtensionPanel or { fields = { }; };
    allMessages = extensionsMessages;
  };
  panelFieldOptions = mkOptionsFromMessage {
    message = schemas.extensions.messages.PanelField or { fields = { }; };
    allMessages = extensionsMessages;
  };
  extensionAppDataOptions = mkOptionsFromMessage {
    message = schemas.extensions.messages.ExtensionAppData or { fields = { }; };
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
  # Files
  # ──────────────────────────────────────────────────────────────────────────
  filesMessages = getSchemaMessages schemas.files;
  generatedFileOptions = mkOptionsFromMessage {
    message = schemas.files.messages.GeneratedFile or { fields = { }; };
    allMessages = filesMessages;
  };
  generatedFilesOptions = mkOptionsFromMessage {
    message = schemas.files.messages.GeneratedFiles or { fields = { }; };
    allMessages = filesMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Healthchecks
  # ──────────────────────────────────────────────────────────────────────────
  healthchecksMessages = getSchemaMessages schemas.healthchecks;
  healthcheckOptions = mkOptionsFromMessage {
    message = schemas.healthchecks.messages.Healthcheck or { fields = { }; };
    allMessages = healthchecksMessages;
  };
  healthcheckResultOptions = mkOptionsFromMessage {
    message = schemas.healthchecks.messages.HealthcheckResult or { fields = { }; };
    allMessages = healthchecksMessages;
  };
  moduleHealthOptions = mkOptionsFromMessage {
    message = schemas.healthchecks.messages.ModuleHealth or { fields = { }; };
    allMessages = healthchecksMessages;
  };
  healthSummaryOptions = mkOptionsFromMessage {
    message = schemas.healthchecks.messages.HealthSummary or { fields = { }; };
    allMessages = healthchecksMessages;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # SST
  # ──────────────────────────────────────────────────────────────────────────
  sstMessages = getSchemaMessages schemas.sst;
  sstOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.Sst or { fields = { }; };
    allMessages = sstMessages;
  };
  sstKmsOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstKms or { fields = { }; };
    allMessages = sstMessages;
  };
  sstOidcOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstOidc or { fields = { }; };
    allMessages = sstMessages;
  };
  sstGithubActionsOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstGithubActions or { fields = { }; };
    allMessages = sstMessages;
  };
  sstFlyioOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstFlyio or { fields = { }; };
    allMessages = sstMessages;
  };
  sstRolesAnywhereOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstRolesAnywhere or { fields = { }; };
    allMessages = sstMessages;
  };
  sstIamOptions = mkOptionsFromMessage {
    message = schemas.sst.messages.SstIam or { fields = { }; };
    allMessages = sstMessages;
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
  #   Options are now auto-generated from all schemas.
  #   Use: db.extend.{messageName} to get options for any message.
  #   Use: db.extend.messages.{schemaName} to get all messages from a schema.
  #
  #   Examples:
  #     db.extend.user           => User message options
  #     db.extend.sstKms         => SstKms message options
  #     db.extend.messages.users => all messages from users schema
  #
  # ============================================================================
  extend =
    # All auto-generated options (from all messages in all schemas)
    allOptions
    // {
      # Legacy aliases for backwards compatibility
      # (where the auto-generated name differs from the expected name)
      aws = allOptions.rolesAnywhere or { }; # aws.RolesAnywhere -> extend.aws
      stepCa = allOptions.stepCaConfig or { }; # step-ca.StepCaConfig -> extend.stepCa
      dns = allOptions.dnsRecord or { }; # dns.DnsRecord -> extend.dns

      # All messages by schema name
      messages = allMessages;
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
  allMessageNames = lib.concatLists (
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
  #   INTERNAL: Boilerplate validation
  #
  # ============================================================================

  # Validate that all data schemas have boilerplate defined
  schemasWithoutBoilerplate = lib.filterAttrs (
    _name: schema: schema.boilerplate or null == null
  ) dataSchemas;

  boilerplateValidation =
    let
      missing = lib.attrNames schemasWithoutBoilerplate;
    in
    if missing == [ ] then
      true
    else
      throw ''
        The following data schemas are missing boilerplate templates:
          ${lib.concatStringsSep "\n  " missing}

        Each data schema must define a 'boilerplate' attribute in its .proto.nix file.
        This template is used by 'stackpanel scaffold' to generate initial data files.

        Example:
          proto.mkProtoFile {
            name = "myschema.proto";
            package = "stackpanel.db";
            boilerplate = '''
              # myschema.nix - Description
              # See: https://stackpanel.dev/docs/myschema
              {
                # Example configuration here
              }
            ''';
            # ... rest of schema
          }
      '';

  # ============================================================================
  #
  #   INTERNAL: Scaffolding / init file generation
  #
  # ============================================================================
  initFiles =
    assert boilerplateValidation;
    let
      # Generate a data file using the schema's boilerplate
      mkDataFile = name: schema: {
        name = ".stackpanel/data/${snakeToKebab name}.nix";
        value = schema.boilerplate;
      };

      # Config file uses the config schema's boilerplate if available,
      # otherwise falls back to a default template
      configBoilerplate = schemas.config.boilerplate or null;
      configFile = {
        ".stackpanel/config.nix" =
          if configBoilerplate != null then
            configBoilerplate
          else
            ''
              # Stackpanel project configuration
              # See: https://stackpanel.dev/docs/config
              {
                enable = true;
                name = "my-project";
                github = "owner/repo";
              }
            '';
      };

      # Internal merging logic file (not user-editable)
      internalBoilerplate = schemas.config.internalBoilerplate or null;
      internalFile =
        if internalBoilerplate != null then { ".stackpanel/_internal.nix" = internalBoilerplate; } else { };

      # Generate data files from dataSchemas using their boilerplate
      dataFiles = lib.listToAttrs (lib.mapAttrsToList mkDataFile dataSchemas);
    in
    configFile // internalFile // dataFiles;
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
    internalSchemas
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
