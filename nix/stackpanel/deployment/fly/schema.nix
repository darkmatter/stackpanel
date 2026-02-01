# ==============================================================================
# schema.nix - Fly.io Deployment App Configuration Schema
#
# Unified field definitions for Fly.io per-app deployment configuration.
#
# This is the SINGLE SOURCE OF TRUTH for Fly.io deployment per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields -> FlyAppConfig message (for Go/TS codegen)
#   2. Nix option source -> fly/module.nix uses asOption to create lib.mkOption
#   3. UI panel source -> fly/ui.nix uses fields for auto-generated panels
#
# Usage from module.nix:
#   let flySchema = import ./schema.nix { inherit lib; };
#   in { options = lib.mapAttrs (_: sp.asOption) flySchema.fields; }
#
# Usage from ui.nix:
#   let flySchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = flySchema.fields; ... }
# ==============================================================================
{ lib }:
let
  sp = import ../../db/lib/field.nix { inherit lib; };
  proto = import ../../db/lib/proto.nix { inherit lib; };

  # Fly.io region options for SELECT field
  regionOptions = [
    {
      value = "iad";
      label = "Ashburn, Virginia (iad)";
    }
    {
      value = "lax";
      label = "Los Angeles (lax)";
    }
    {
      value = "ord";
      label = "Chicago (ord)";
    }
    {
      value = "sea";
      label = "Seattle (sea)";
    }
    {
      value = "ewr";
      label = "Secaucus, NJ (ewr)";
    }
    {
      value = "lhr";
      label = "London (lhr)";
    }
    {
      value = "ams";
      label = "Amsterdam (ams)";
    }
    {
      value = "fra";
      label = "Frankfurt (fra)";
    }
    {
      value = "nrt";
      label = "Tokyo (nrt)";
    }
    {
      value = "sin";
      label = "Singapore (sin)";
    }
    {
      value = "syd";
      label = "Sydney (syd)";
    }
  ];

  # ===========================================================================
  # Field definitions for deployment.fly.* options
  # ===========================================================================
  fields = {
    # Fly.io app name
    appName = sp.string {
      index = 1;
      description = "Fly.io app name. Must be globally unique on Fly.io.";
      example = "my-web-app";
      ui = {
        label = "App Name";
        placeholder = "my-app";
        description = "Globally unique Fly.io app name. Defaults to the stackpanel app name.";
      };
    };

    # Deployment region
    region = sp.string {
      index = 2;
      description = "Fly.io region for deployment. Choose a region close to your users.";
      default = "iad";
      example = "lhr";
      ui = {
        label = "Region";
        type = sp.uiType.select;
        options = regionOptions;
        description = "Primary region where your app runs. Can be expanded to multiple regions later.";
      };
    };

    # Memory allocation
    memory = sp.string {
      index = 3;
      description = "Memory allocation for the Fly Machine VM.";
      default = "512mb";
      example = "1gb";
      ui = {
        label = "Memory";
        type = sp.uiType.select;
        options = [
          {
            value = "256mb";
            label = "256 MB";
          }
          {
            value = "512mb";
            label = "512 MB";
          }
          {
            value = "1gb";
            label = "1 GB";
          }
          {
            value = "2gb";
            label = "2 GB";
          }
          {
            value = "4gb";
            label = "4 GB";
          }
          {
            value = "8gb";
            label = "8 GB";
          }
        ];
        description = "RAM allocated to each machine. More memory = higher cost.";
      };
    };

    # CPU type
    cpuKind = sp.string {
      index = 4;
      description = "CPU type for the Fly Machine.";
      default = "shared";
      ui = {
        label = "CPU Type";
        type = sp.uiType.select;
        options = [
          {
            value = "shared";
            label = "Shared (cost-effective)";
          }
          {
            value = "performance";
            label = "Performance (dedicated)";
          }
        ];
        description = "Shared CPUs are cheaper. Performance CPUs provide dedicated resources.";
      };
    };

    # Number of CPUs
    cpus = sp.int32 {
      index = 5;
      description = "Number of CPU cores allocated to the machine.";
      default = 1;
      example = 2;
      ui = {
        label = "CPUs";
        placeholder = "1";
        description = "Number of CPU cores. More CPUs = better performance for CPU-bound tasks.";
      };
    };

    # Auto-stop behavior
    autoStop = sp.string {
      index = 6;
      description = "Auto-stop behavior when idle. Reduces costs for low-traffic apps.";
      default = "suspend";
      ui = {
        label = "Auto Stop";
        type = sp.uiType.select;
        options = [
          {
            value = "off";
            label = "Off (always running)";
          }
          {
            value = "stop";
            label = "Stop (full shutdown)";
          }
          {
            value = "suspend";
            label = "Suspend (fast resume)";
          }
        ];
        description = "Suspend is recommended - fast resume with cost savings when idle.";
      };
    };

    # Auto-start on request
    autoStart = sp.bool {
      index = 7;
      description = "Automatically start machines when requests arrive.";
      default = true;
      ui = {
        label = "Auto Start";
        description = "When enabled, stopped machines automatically start on incoming requests.";
      };
    };

    # Minimum machines
    minMachines = sp.int32 {
      index = 8;
      description = "Minimum number of machines to keep running.";
      default = 0;
      example = 1;
      ui = {
        label = "Min Machines";
        placeholder = "0";
        description = "Set to 1+ for production apps to avoid cold starts. 0 = scale to zero.";
      };
    };

    # Force HTTPS
    forceHttps = sp.bool {
      index = 9;
      description = "Force HTTPS for all incoming requests.";
      default = true;
      ui = {
        label = "Force HTTPS";
        description = "Redirect all HTTP requests to HTTPS. Recommended for security.";
      };
    };

    # Environment variables (hidden - complex type)
    env = sp.string {
      index = 10;
      mapKey = "string";
      description = "Environment variables for fly.toml";
      default = { };
      ui = null; # Hidden: complex attrs type
    };
  };

in
proto.mkProtoFile {
  name = "fly_app.proto";
  package = "stackpanel.deployment";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    FlyAppConfig = proto.mkMessage {
      name = "FlyAppConfig";
      description = "Fly.io per-app deployment configuration";
      fields = sp.toProtoFields fields;
    };
  };
}
// {
  inherit fields;
}
