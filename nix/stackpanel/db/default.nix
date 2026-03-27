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
# │  4. Run `nix develop --impure -c ./packages/proto/generate.sh`              │
# │     to regenerate Go/TS types                                               │
# │                                                                             │
# │  Options are auto-generated via mkSchemaBundle. Access via db.extend.*      │
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
  mkOptLib = import ./lib/mkOpt.nix { inherit lib; };
  fieldLib = import ./lib/field.nix { inherit lib; };

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
    # Module system
    # ──────────────────────────────────────────────────────────────────────────
    modules = import ./schemas/modules.proto.nix { inherit lib; };
  };

  # ============================================================================
  #
  #   STEP 2: SCHEMA CATEGORIZATION
  #
  #   Assign your schema to the appropriate category. This determines:
  #     - dataSchemas: User-editable data in .stack/data/<name>.nix
  #     - internalSchemas: Module-computed, not user-editable (no data file)
  #     - rootSchemas: Project config in .stack/ root
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

  # Schemas that generate data files in .stack/data/
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
      modules
      onboarding
      services
      shells
      ;
  };

  # Schemas for .stack/ root (project-level config)
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
  allOptions = lib.foldl' (acc: bundle: acc // bundle.options) { } (lib.attrValues allSchemaBundles);

  # Flatten all messages from all schemas
  # Keys are schema names: users, apps, sst, etc.
  allMessages = lib.mapAttrs (_: bundle: bundle.messages) allSchemaBundles;

  # ============================================================================
  #
  #   OPTIONS EXPORT (extend object)
  #
  #   All options are auto-generated from schemas via mkSchemaBundle.
  #   Use: db.extend.{messageName} to get options for any message.
  #   Use: db.extend.messages.{schemaName} to get all messages from a schema.
  #   Use: db.extend.none for pure Nix options with no proto schema.
  #   Use: db.asOptions db.extend.X to get options without the marker (submodule use).
  #
  #   All db.extend.* options include a marker validated by db.mkOpt to ensure
  #   deliberate option definition and prevent accidental field duplication.
  #
  #   Examples:
  #     db.mkOpt db.extend.user { }        => User options (no extensions)
  #     db.mkOpt db.extend.theme { ... }   => Theme options + extensions
  #     db.mkOpt db.extend.none { ... }    => Pure Nix options
  #     db.asOptions db.extend.app         => Options for direct submodule use
  #
  # ============================================================================
  extend =
    # All auto-generated options (from all messages in all schemas)
    # Each one gets a marker added for mkOpt validation
    lib.mapAttrs (_: opts: mkOptLib.withMarker opts) allOptions // {
      # Legacy aliases for backwards compatibility
      # (where the auto-generated name differs from the expected name)
      aws = mkOptLib.withMarker (allOptions.rolesAnywhere or { }); # aws.RolesAnywhere -> extend.aws
      stepCa = mkOptLib.withMarker (allOptions.stepCaConfig or { }); # step-ca.StepCaConfig -> extend.stepCa
      dns = mkOptLib.withMarker (allOptions.dnsRecord or { }); # dns.DnsRecord -> extend.dns

      # For pure Nix options with no proto schema
      none = mkOptLib.none;

      # All messages by schema name (no marker needed - these are for introspection)
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
  #   Generates the .stack/ directory structure for new projects.
  #   config.nix is the single source of truth (both user and agent editable).
  #
  # ============================================================================
  initFiles =
    let
      configBoilerplate = schemas.config.boilerplate or null;
      configFile = {
        ".stack/config.nix" =
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

      gitignoreBoilerplate = schemas.config.gitignoreBoilerplate or null;
      gitignoreFile =
        if gitignoreBoilerplate != null then { ".stack/.gitignore" = gitignoreBoilerplate; } else { };

    in
    configFile // gitignoreFile;
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

  # Unified field definition library (mkSpField, asOption, UI types)
  field = fieldLib;

  # Options library for custom option building
  inherit optionsLib;

  # Options extension for core/options
  inherit extend;

  # mkOpt: Helper for defining options that extend proto schemas
  # Usage:
  #   options.stackpanel.theme = db.mkOpt db.extend.theme { config-file = ...; };
  #   options.stackpanel.devshell = db.mkOpt db.extend.none { packages = ...; };
  #   { options = db.asOptions db.extend.app; }  # For direct submodule use
  inherit (mkOptLib) mkOpt asOptions mkSubmodule;

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
