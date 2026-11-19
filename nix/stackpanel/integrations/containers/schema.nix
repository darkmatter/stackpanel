# ==============================================================================
# schema.nix - Container App Configuration Schema
#
# Runtime SpFields shared by the app module and the Studio panel. Complex Nix
# options (startupCommand and copyToRoot) are declared directly by the module.
# ==============================================================================
{
  lib,
  builderIds ? null,
}:
let
  sp = lib.stackpanel.spField;

  # ===========================================================================
  # Runtime field definitions
  # ===========================================================================
  fields = {
    # Whether this app contributes an image
    enable = sp.bool {
      index = 1;
      description = "Enable container building for this app";
      default = false;
      ui.label = "Build Container";
    };

    # Container image name override
    name = sp.string {
      index = 2;
      description = "Override the container image name. When empty, uses the app name.";
      optional = true;
      example = "stackpanel-web";
      ui = {
        label = "Image Name";
        placeholder = "stackpanel-web";
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

    # The field is a string; the evaluated panel offers installed providers.
    type = sp.string {
      index = 4;
      description = "ID of the image builder registered in stackpanel.containerBuilders.";
      default = "bun";
      ui = {
        label = "Image Builder";
        type = if builderIds == null then sp.uiType.text else sp.uiType.select;
        options = map (id: {
          value = id;
          label = id;
        }) (if builderIds == null then [ ] else builderIds);
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
      example = "docker://registry.fly.io/stackpanel-demo";
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
        description = "Path to build output used by the selected builder.";
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
{
  inherit fields;
  readme = ''
    Build OCI containers for your apps using Nix.

    **Workflow:**
    1. Select a registered builder in `container.type` and prepare its app output.
    2. Build container: `container-build <app>`
    3. Push to registry: `container-copy <app>`

    Images and copy commands use `containers.settings.backend` (nix2container or dockerTools).
  '';
}
