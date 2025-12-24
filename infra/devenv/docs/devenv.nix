{ pkgs, lib, config, ...}:
let
  # config.devenv.root is set by devenv and points to the project root
  # Fall back to "." if not available (shouldn't happen in practice)
  root = config.devenv.root or ".";
in {
  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.docs = {
    exec = ''
      ${pkgs.bun}/bin/bun run dev
    '';
    cwd = "${root}/apps/docs";
  };
  profiles.docs.module = {};
  enterShell = ''
    echo "📚 Starting docs development server..."

  '';
}