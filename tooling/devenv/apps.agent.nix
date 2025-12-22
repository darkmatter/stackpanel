{ pkgs, lib, config, ...}: {
  languages.go.enable = true;
  # processes.agent = {
  #   cwd = "${config.git.root}/apps/agent";
  #   exec = ''
  #     ${pkgs.go}/bin/go run . --config ${config.git.root}/apps/agent/config.example.yaml
  #   '';
  # };
  profiles.agent.module = {};
}