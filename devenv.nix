{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  # Reduce the size of cachix closure by ~4GB!
  cachixBin = pkgs.cachix.bin;
  cachixSlim = {
    type = "derivation";
    name = cachixBin.name;
    outPath = cachixBin.outPath;
    outputs = [ "out" ];
    out = cachixSlim;
    outputName = "out";
  };
  isDevelopment = builtins.getEnv "STACKPANEL_ENV" == "development";
  release = !isDevelopment;
  githubActions = builtins.getEnv "GITHUB_ACTIONS" == "true";
  CI = builtins.getEnv "CI" != null && builtins.getEnv "CI" != "";
  isCI = CI || githubActions;
  baseTools = with pkgs; [
    sops
    chamber
    awscli2
   ];
   devtools = with pkgs; [
    git
    gum
    jq
    yq
    ncurses
    starship
   ];
   gotools = with pkgs; [
    delve
   ] ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.apple-sdk_15
    ];
   jstools = with pkgs; [
    turbo
   ];
   nixtools = with pkgs; [
    nil
   ];
  toolsets = {
    minimal = baseTools;
    go = baseTools ++ gotools;
    javascript = baseTools ++ jstools;
    full = baseTools ++ devtools ++ gotools ++ jstools ++ nixtools;
  };
  stackpanelAgent = pkgs.buildGoModule {
    pname = "stackpanel-agent";
    version = "dev";
    src = ./agent;  # Adjust path as needed
    vendorHash = null;
    CGO_ENABLED = if release then 0 else 1;
    ldflags = if release then [ "-s" "-w" ] else [];
  };
  stackpanelAgentContainer = pkgs.dockerTools.buildImage {
    name = "stackpanel-agent";
    tag = "latest";
    contents = [ stackpanelAgent ];
    config = {
      Cmd = [ "/bin/stackpanel-agent" "run"];
      Expose = [ "8080" ];
    };
  };
  profileGo = {
    name = "go";
    env.ENABLE_GO = "1";
    packages = toolsets.go;
    languages.go.enable = true;
  };
  profileJavascript = {
    name = "javascript";
    env.ENABLE_JAVASCRIPT = "1";
    packages = toolsets.javascript;
    languages.javascript.bun.enable = true;
    languages.javascript.bun.install.enable = true;
  };
  profileDevelopment = profileGo // profileJavascript // {
    name = "development";
    env.STACKPANEL_ENV = "development";
    env.ENABLE_DEVELOPMENT = "1";
    packages = toolsets.full;
    languages.nix.enable = true;
  };
in  {
  imports = [inputs.darkmatter.devenvModules.default];

  packages = toolsets.minimal;

  # Common environment variables
  env = {
    COMPOSE_DOCKER_CLI_BUILD = "1";
    DOCKER_BUILDKIT = "1";
    TURBO_TEAM = "darkmatterlabs";
    TURBO_UI = "true";
    AWS_PROFILE = lib.mkIf (!isCI) "darkmatter-dev";
    AWS_REGION = lib.mkDefault "us-west-2";
    AWS_DEFAULT_REGION = lib.mkDefault "us-west-2";
    AWS_START_URL = "https://dark-matter.awsapps.com/start";
    TERM = lib.mkIf (!isCI) "xterm-256color";
  };

  containers = {
    agent = {
      image = stackpanelAgentContainer;
      ports = [ "8080:8080" ];
      copyToRoot = lib.mkIf release null;
      entrypoint = [
        "/bin/stackpanel-agent"
        "run"
        "--host"
      ];
    };
  };


  # https://devenv.sh/processes/
  # processes.agent.exec = "${stackpanelAgent}/bin/stackpanel-agent run --dev";


  entersShell = let
    mkProcessComposePath = ''
      # syntax: bash
      if [ ! -d "$HOME/.config/process-compose" ]; then
        mkdir -p "$HOME/.config/process-compose"
      fi
    '';
    enterInteractiveShell = ''
      # syntax: bash
      # store user home for later use
      if [[ -z "''${DEVENV_ORIG_HOME:-}" ]]; then
        export DEVENV_ORIG_HOME="$HOME"
      fi
      ${mkProcessComposePath}
      export STARSHIP_CONFIG="$DEVENV_ROOT/tooling/nix/extra/starship.toml"
      eval "$(starship init "$SHELL")"
      # shellcheck source=/dev/null
      # source "$DEVENV_ROOT/scripts/activate.sh"
    '';
  in  ''
    # syntax: bash
    command -v node &>/dev/null && echo "✓ Node"
    command -v go &>/dev/null && echo "✓ Go"

    if [[ "''${DEVENV_CMDLINE:-}" == shell\ --\ * ]]; then
      echo "Running in script mode"
    elif [[ "''${DEVENV_CMDLINE:-}" == shell* ]]; then
      ${enterInteractiveShell}
    fi
  '';

  # profiles:
  #  enable with --profile foo --profile bar ...
  profiles = {
    # --profile development
    development.module = profileDevelopment;
    # --profile go
    go.module = profileGo;
    # --profile javascript
    javascript.module = profileJavascript;
  };

  cachix.package = cachixSlim;
  cachix.enable = true;
  cachix.pull = ["devenv" "darkmatter"];
}
