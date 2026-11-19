{ lib, ... }@args:
import ../framework.nix args {
  id = "vite";
  label = "Vite";
  icon = "zap";
  description = "Build a client or server-rendered application with Vite.";
  fields = {
    ssr = lib.stackpanel.spField.bool {
      index = 2;
      description = "Use server-side rendering rather than static SPA output.";
      default = false;
    };
    assets-dir = lib.stackpanel.spField.string {
      index = 3;
      description = "Asset output directory relative to the app path.";
      default = "dist";
    };
  };
  defaultTasks = {
    dev = "bun run vite dev";
    build = "bun run vite build";
  };
  deployMetadata = app: {
    cloudflareAdapter = "vite";
    inherit (app.framework.vite) ssr;
    assetsDir = app.framework.vite.assets-dir;
  };
}
