{pkgs, lib, config, ...}: {

  processes.cli = {
    cwd = "${config.git.root}/apps/cli";
    exec = ''
      ${pkgs.go}/bin/go run . status
    '';
  };
  profiles.cli.module = {};
}