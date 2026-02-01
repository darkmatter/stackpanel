# ==============================================================================
# schema.nix - Container App Configuration Schema
#
# Unified field definitions for container per-app configuration.
#
# This is the SINGLE SOURCE OF TRUTH for container module per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields -> ContainerAppConfig message (for Go/TS codegen)
#   2. Nix option source -> containers/module.nix uses asOption to create lib.mkOption
#   3. UI panel source -> containers/ui.nix uses fields for auto-generated panels
#
# NOTE: Complex type options (startupCommand, copyToRoot, env) remain as manual
# lib.mkOption definitions in module.nix since SpFields don't support these types.
#
# Usage from module.nix:
#   let containerSchema = import ./schema.nix { inherit lib; };
#   in { options = lib.mapAttrs (_: sp.asOption) containerSchema.fields; }
#
# Usage from ui.nix:
#   let containerSchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = containerSchema.fields; ... }
# ==============================================================================
{ lib }:
let
  sp = import ../db/lib/field.nix { inherit lib; };
  proto = import ../db/lib/proto.nix { inherit lib; };

  # ===========================================================================
  # Field definitions (camelCase keys - zero conversion to Nix/JSON/Go/TS)
  # ===========================================================================
  fields = {
    # Whether this app has container building enabled (hidden from UI)
    enable = sp.bool {
      index = 1;
      description = "Enable container building for this app";
      default = false;
      ui = null; # Hidden: controlled by module, not user-editable in panels
    };

    # Container image name override
    name = sp.string {
      index = 2;
      description = "Override the container image name. When empty, uses the app name.";
      optional = true;
      example = "my-web-app";
      ui = {
        label = "Image Name";
        placeholder = "my-app";
        description = "Override the container image name. Leave empty to use the app name.";
      };
    };

    # Image tag/version
    version = sp.string {
      index = 3;
      description = "Container image tag used when pushing to registry.";
      default = "latest";
      example = "v1.2.3";
      ui = {
        label = "Version";
        placeholder = "latest";
        description = "Image tag for registry pushes. Use semantic versions for production.";
      };
    };

    # App type for base image and startup command defaults
    type = sp.string {
      index = 4;
      description = "App runtime type. Determines the base image and default startup command.";
      default = "bun";
      ui = {
        label = "Type";
        type = sp.uiType.select;
        description = "Select the runtime for your app. This determines the base image and startup command.";
        options = [
          {
            value = "bun";
            label = "Bun";
          }
          {
            value = "node";
            label = "Node.js";
          }
          {
            value = "go";
            label = "Go";
          }
          {
            value = "static";
            label = "Static";
          }
          {
            value = "custom";
            label = "Custom";
          }
        ];
      };
    };

    # Port the app listens on inside the container
    port = sp.int32 {
      index = 5;
      description = "The port your application listens on inside the container.";
      default = 3000;
      example = 8080;
      ui = {
        label = "Port";
        placeholder = "3000";
        description = "Internal container port. Must match what your app binds to.";
      };
    };

    # Container registry to push to
    registry = sp.string {
      index = 6;
      description = "Container registry URL for pushing images.";
      optional = true;
      example = "docker://registry.fly.io/my-org";
      ui = {
        label = "Registry";
        placeholder = "docker://registry.fly.io/";
        description = "Registry URL in skopeo format. Uses default registry if empty.";
      };
    };

    # Working directory inside the container
    workingDir = sp.string {
      index = 7;
      description = "Working directory inside the container where your app runs.";
      default = "/app";
      ui = {
        label = "Working Directory";
        placeholder = "/app";
        description = "The directory where your application code is placed and executed from.";
      };
    };

    # Path to pre-built output directory
    buildOutputPath = sp.string {
      index = 8;
      description = "Path to pre-built output directory relative to project root.";
      optional = true;
      example = "apps/web/.output";
      ui = {
        label = "Build Output Path";
        placeholder = "apps/web/.output";
        description = "Path to your build output. Run 'bun run build' before container-build.";
      };
    };

    # Maximum layers for nix2container
    maxLayers = sp.int32 {
      index = 9;
      description = "Maximum OCI layers for nix2container backend. Ignored by dockerTools.";
      default = 100;
      example = 50;
      ui = {
        label = "Max Layers";
        placeholder = "100";
        description = "More layers = better caching but larger manifest. Only affects nix2container.";
      };
    };

    # ---------------------------------------------------------------------------
    # Complex type fields - hidden from UI panels
    # These require manual lib.mkOption definitions in module.nix
    # ---------------------------------------------------------------------------

    # Custom startup command (string or list of strings)
    startupCommand = sp.string {
      index = 10;
      description = "Custom startup command. When null, auto-detected based on type.";
      optional = true;
      ui = null; # Hidden: complex type (string | list)
    };

    # Additional paths to copy to container root
    copyToRoot = sp.string {
      index = 11;
      description = "Additional paths to copy to the container root";
      optional = true;
      ui = null; # Hidden: complex type (path | list of paths)
    };

    # Default arguments to pass to skopeo copy
    defaultCopyArgs = sp.string {
      index = 12;
      repeated = true;
      description = "Default arguments to pass to skopeo copy";
      default = [ ];
      ui = null; # Hidden: list of strings, not typically user-edited
    };

    # Environment variables for the container
    env = sp.string {
      index = 13;
      mapKey = "string";
      description = "Environment variables for the container";
      default = { };
      ui = null; # Hidden: attrs type, complex editing
    };
  };

in
# Return the proto file object directly (generate.sh expects schema.name),
# with fields merged in (module.nix / ui.nix use schema.fields).
proto.mkProtoFile {
  name = "container_app.proto";
  package = "stackpanel.containers";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    ContainerAppConfig = proto.mkMessage {
      name = "ContainerAppConfig";
      description = "Container per-app configuration";
      fields = sp.toProtoFields fields;
    };
  };

  readme = ''
    Build OCI containers for your apps using Nix.

    **Workflow:**
    1. Build your app: `bun run build`
    2. Build container: `container-build <app>`
    3. Push to registry: `container-copy <app>`

    Uses **nix2container** for efficient layer caching and streaming pushes.
  '';
}
// {
  inherit fields;
}
