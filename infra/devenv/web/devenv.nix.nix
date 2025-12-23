{ pkgs, lib, config, ...}: 
let
  root = config.devenv.root or ".";
in {
  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.web = {
    # exec = ''
    #   ${pkgs.bun}/bin/bun run dev
    # '';
    exec = "${pkgs.bun}/bin/bun x alchemy dev";
    cwd = root;
  };
  profiles.web.module = {};
}