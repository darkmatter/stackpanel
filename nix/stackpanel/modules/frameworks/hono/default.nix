{ lib, ... }@args:
import ../framework.nix args {
  id = "hono";
  label = "Hono";
  icon = "flame";
  description = "HTTP APIs and Workers built with Hono.";
  fields.entrypoint = lib.stackpanel.spField.string {
    index = 2;
    default = "src/index.ts";
    description = "Entrypoint file for the Hono worker.";
  };
  defaultTasks = {
    dev = "bun run dev";
    build = "bun run build";
  };
  deployMetadata = app: {
    cloudflareAdapter = "worker";
    inherit (app.framework.hono) entrypoint;
  };
}
