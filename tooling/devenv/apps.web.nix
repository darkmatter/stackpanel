{ pkgs, lib, config, ...}: {

  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.web = {
    # exec = ''
    #   ${pkgs.bun}/bin/bun run dev
    # '';
    exec = "${pkgs.bun}/bin/bun x alchemy dev";
    cwd = "${config.git.root}/apps/web";
  };
  profiles.web.module = {};
}