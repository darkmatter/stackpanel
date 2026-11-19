# ==============================================================================
# schema.nix - Cloudflare Workers Deployment App Configuration Schema
#
# Unified field definitions for Cloudflare Workers per-app deployment configuration.
#
# Both the per-app Nix options and the Studio panel use these runtime SpFields.
# ==============================================================================
{ lib }:
let
  sp = lib.stackpanel.spField;

in
{
  # ===========================================================================
  # Field definitions for deployment.cloudflare.* options
  # ===========================================================================
  fields = {
    # Worker name
    workerName = sp.string {
      index = 1;
      description = "Cloudflare Worker name. Must be unique within your account.";
      example = "stackpanel-studio";
      ui = {
        label = "Worker Name";
        placeholder = "stackpanel-studio";
        description = "Unique name for the Worker. Defaults to the stackpanel app name.";
      };
    };

    # Custom domain route
    route = sp.string {
      index = 3;
      description = "Custom domain route pattern for the Worker.";
      optional = true;
      example = "stackpanel-demo.localhost/*";
      ui = {
        label = "Route";
        placeholder = "stackpanel-demo.localhost/*";
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
}
