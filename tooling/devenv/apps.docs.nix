{ pkgs, lib, config, ...}: {

  languages.javascript.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.install.enable = true;
  processes.docs = {
    exec = ''
      ${pkgs.bun}/bin/bun run dev
    '';
    cwd = "${config.git.root}/apps/docs";
  };
  profiles.docs.module = {};
}