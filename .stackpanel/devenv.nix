{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  packages = with pkgs; [
    bun
    nodejs_22
    go
    air # Go live reload for CLI development
    jq
    git
    nixd
    nixfmt
  ];

  languages = {
    javascript = {
      enable = true;
      bun.enable = true;
      bun.install.enable = true;
    };
    typescript.enable = true;
    go = {
      enable = true;
      package = pkgs.go;
    };
  };

  env = {
    STACKPANEL_SHELL_ID = "1";
    EDITOR = "vim";
    STEP_CA_URL = "https://ca.internal:443";
    STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
  };

  enterShell = ''
    echo "✅ Devenv for the stackpanel repository"
  '';
  git-hooks = {
    enable = true;
    git-hooks.package = pkgs.prek;
    # package = pkgs.prek;
    alejandra.enable = true;
    nixfmt.enable = true;

    # Add hook configurations here, e.g.:
    # nixfmt-rfc-style.enable = true;
    gofmt.enable = true;
  };
}
