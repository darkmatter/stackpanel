# ==============================================================================
# schema.nix
#
# Canonical schema definition for stackpanel configuration.
#
# This module defines the SINGLE SOURCE OF TRUTH for stackpanel config types.
# Types are exported as JSON Schema that quicktype uses to generate:
#   - TypeScript types for the web app
#   - Go types for the CLI and agent
#
# The schema uses JSON Schema format for precise type control, ensuring
# quicktype generates correct types (maps vs objects, nullable fields, etc.).
#
# Usage:
#   nix eval --json -f nix/stackpanel/core/schema.nix jsonSchema
#
# This output is piped to quicktype:
#   nix eval --json -f ... jsonSchema | bun x quicktype -s schema -o types.ts --lang typescript -
# ==============================================================================
{
  lib ? (import <nixpkgs> { }).lib,
  ...
}:
let
  # JSON Schema definitions for all types
  # App type - represents a single application
  appSchema = {
    type = "object";
    properties = {
      port = {
        type = "integer";
        description = "Port number for the app";
      };
      domain = {
        type = [
          "string"
          "null"
        ];
        description = "Domain for the app (e.g., 'app.localhost')";
      };
      url = {
        type = [
          "string"
          "null"
        ];
        description = "Full URL for the app";
      };
      tls = {
        type = "boolean";
        description = "Whether TLS is enabled";
      };
    };
    required = [
      "port"
      "tls"
    ];
    additionalProperties = false;
  };

  # Service type - represents an infrastructure service
  serviceSchema = {
    type = "object";
    properties = {
      key = {
        type = "string";
        description = "Unique key (e.g., 'POSTGRES')";
      };
      name = {
        type = "string";
        description = "Human-readable name";
      };
      port = {
        type = "integer";
        description = "Port number";
      };
      envVar = {
        type = "string";
        description = "Environment variable name";
      };
    };
    required = [
      "key"
      "name"
      "port"
      "envVar"
    ];
    additionalProperties = false;
  };

  # Paths type
  pathsSchema = {
    type = "object";
    properties = {
      root = {
        type = "string";
      };
      state = {
        type = "string";
      };
      gen = {
        type = "string";
      };
      data = {
        type = "string";
      };
      config = {
        type = "string";
      };
    };
    required = [
      "root"
      "state"
      "gen"
      "data"
      "config"
    ];
    additionalProperties = false;
  };

  # Step CA config
  stepSchema = {
    type = "object";
    properties = {
      enable = {
        type = "boolean";
      };
      caUrl = {
        type = [
          "string"
          "null"
        ];
      };
    };
    required = [ "enable" ];
    additionalProperties = false;
  };

  # Network config
  networkSchema = {
    type = "object";
    properties = {
      step = stepSchema;
    };
    required = [ "step" ];
    additionalProperties = false;
  };

  # MOTD Command
  motdCommandSchema = {
    type = "object";
    properties = {
      name = {
        type = "string";
      };
      description = {
        type = "string";
      };
    };
    required = [
      "name"
      "description"
    ];
    additionalProperties = false;
  };

  # MOTD config
  motdSchema = {
    type = "object";
    properties = {
      enable = {
        type = "boolean";
      };
      commands = {
        type = "array";
        items = motdCommandSchema;
      };
      features = {
        type = "array";
        items = {
          type = "string";
        };
      };
      hints = {
        type = "array";
        items = {
          type = "string";
        };
      };
    };
    required = [ "enable" ];
    additionalProperties = false;
  };

  # Main Config schema
  configSchema = {
    "$schema" = "http://json-schema.org/draft-07/schema#";
    title = "Config";
    description = "Stackpanel configuration produced by Nix evaluation";
    type = "object";
    properties = {
      version = {
        type = "integer";
        description = "Schema version";
      };
      projectName = {
        type = "string";
        description = "Project name";
      };
      projectRoot = {
        type = [
          "string"
          "null"
        ];
        description = "Absolute path to project root";
      };
      basePort = {
        type = "integer";
        description = "Base port for the project";
      };

      paths = pathsSchema;

      # Apps is a map of string -> App
      apps = {
        type = "object";
        additionalProperties = appSchema;
        description = "Map of app name to app configuration";
      };

      # Services is a map of string -> Service
      services = {
        type = "object";
        additionalProperties = serviceSchema;
        description = "Map of service name to service configuration";
      };

      network = networkSchema;

      motd = {
        anyOf = [
          motdSchema
          { type = "null"; }
        ];
        description = "Message of the day configuration";
      };

      # Optional error fields
      error = {
        type = [
          "string"
          "null"
        ];
      };
      hint = {
        type = [
          "string"
          "null"
        ];
      };
    };
    required = [
      "version"
      "projectName"
      "basePort"
      "paths"
      "apps"
      "services"
      "network"
    ];
    additionalProperties = false;
  };
in
{
  # Export the JSON Schema for quicktype consumption
  jsonSchema = configSchema;

  # Also export individual type schemas for reference
  types = {
    app = appSchema;
    service = serviceSchema;
    paths = pathsSchema;
    network = networkSchema;
    motd = motdSchema;
    motdCommand = motdCommandSchema;
  };

  # JSON output
  json = builtins.toJSON configSchema;
}
