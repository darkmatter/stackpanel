args:
import ../framework.nix args {
  id = "tanstack-start";
  label = "TanStack Start";
  icon = "route";
  description = "Full-stack SSR with TanStack Router and Vite.";
  defaultTasks = {
    dev = "bun run vite dev";
    build = "bun run vite build";
  };
  deployMetadata = _: { cloudflareAdapter = "tanstack-start"; };
}
