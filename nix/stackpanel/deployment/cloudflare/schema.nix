# ==============================================================================
# schema.nix - Cloudflare Workers Deployment App Configuration Schema
#
# Unified field definitions for Cloudflare Workers per-app deployment configuration.
#
# This is the SINGLE SOURCE OF TRUTH for Cloudflare deployment per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields -> CloudflareAppConfig message (for Go/TS codegen)
#   2. Nix option source -> cloudflare/module.nix uses asOption to create lib.mkOption
#   3. UI panel source -> cloudflare/ui.nix uses fields for auto-generated panels
#
# Usage from module.nix:
#   let cloudflareSchema = import ./schema.nix { inherit lib; };
#   in { options = lib.mapAttrs (_: sp.asOption) cloudflareSchema.fields; }
#
# Usage from ui.nix:
#   let cloudflareSchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = cloudflareSchema.fields; ... }
# ==============================================================================
{ lib }:
let
  sp = import ../../db/lib/field.nix { inherit lib; };
  proto = import ../../db/lib/proto.nix { inherit lib; };

  # ===========================================================================
  # Field definitions for deployment.cloudflare.* options
  # ===========================================================================
  fields = {
    # Worker name
    workerName = sp.string {
      index = 1;
      description = "Cloudflare Worker name. Must be unique within your account.";
      example = "my-web-worker";
      ui = {
        label = "Worker Name";
        placeholder = "my-app";
        description = "Unique name for the Worker. Defaults to the stackpanel app name.";
      };
    };

    # Deployment type
    type = sp.string {
      index = 2;
      description = "Cloudflare deployment type determines how your app is built and deployed.";
      default = "tanstack-start";
      ui = {
        label = "Type";
        type = sp.uiType.select;
        options = [
          {
            value = "tanstack-start";
            label = "TanStack Start (full-stack SSR)";
          }
          {
            value = "vite";
            label = "Vite (SPA)";
          }
          {
            value = "worker";
            label = "Worker (plain)";
          }
          {
            value = "pages";
            label = "Pages (static + functions)";
          }
        ];
        description = "TanStack Start for full-stack SSR apps, Vite for SPAs, Worker for APIs, Pages for static sites.";
      };
    };

    # Custom domain route
    route = sp.string {
      index = 3;
      description = "Custom domain route pattern for the Worker.";
      optional = true;
      example = "app.example.com/*";
      ui = {
        label = "Route";
        placeholder = "app.example.com/*";
        description = "Custom domain pattern. Leave empty to use the default workers.dev subdomain.";
      };
    };

    # Compatibility mode
    compatibility = sp.string {
      index = 4;
      description = "Worker runtime compatibility mode.";
      default = "node";
      ui = {
        label = "Compatibility";
        type = sp.uiType.select;
        options = [
          {
            value = "node";
            label = "Node.js APIs";
          }
          {
            value = "browser";
            label = "Browser APIs";
          }
        ];
        description = "Node.js mode enables Node.js built-in APIs. Browser mode for web-only APIs.";
      };
    };

    # Environment bindings (hidden - complex type)
    bindings = sp.string {
      index = 5;
      mapKey = "string";
      description = "Environment variable bindings for the Worker";
      default = { };
      ui = null; # Hidden: complex attrs type
    };

    # Secrets (hidden - list)
    secrets = sp.string {
      index = 6;
      repeated = true;
      description = "Secret names to inject at deploy time";
      default = [ ];
      example = [
        "DATABASE_URL"
        "API_KEY"
      ];
      ui = null; # Hidden: list, better managed via CLI
    };

    # KV namespaces (hidden - list)
    kvNamespaces = sp.string {
      index = 7;
      repeated = true;
      description = "KV namespace bindings";
      default = [ ];
      ui = null; # Hidden: list of resources
    };

    # D1 databases (hidden - list)
    d1Databases = sp.string {
      index = 8;
      repeated = true;
      description = "D1 database bindings";
      default = [ ];
      ui = null; # Hidden: list of resources
    };

    # R2 buckets (hidden - list)
    r2Buckets = sp.string {
      index = 9;
      repeated = true;
      description = "R2 bucket bindings";
      default = [ ];
      ui = null; # Hidden: list of resources
    };
  };

in
proto.mkProtoFile {
  name = "cloudflare_app.proto";
  package = "stackpanel.deployment";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    CloudflareAppConfig = proto.mkMessage {
      name = "CloudflareAppConfig";
      description = "Cloudflare Workers per-app deployment configuration";
      fields = sp.toProtoFields fields;
    };
  };
}
// {
  inherit fields;
}
