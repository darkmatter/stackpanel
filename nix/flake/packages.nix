# ==============================================================================
# packages.nix
#
# Package definitions for stackpanel.
# Defines the CLI, agent, and other packages built by this flake.
# ==============================================================================
{ pkgs, inputs }:
let
  stackpanel-cli-unwrapped = pkgs.callPackage ../stackpanel/packages/stackpanel-cli { };
  stackpanel-agent = pkgs.callPackage ../stackpanel/packages/stackpanel-agent { };
in
{
  # CLI package (wrapped to include agent in PATH)
  stackpanel-cli = pkgs.symlinkJoin {
    name = "stackpanel-cli-${stackpanel-cli-unwrapped.version}";
    paths = [
      stackpanel-cli-unwrapped
      stackpanel-agent
    ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/stackpanel \
        --prefix PATH : ${stackpanel-agent}/bin
    '';
  };

  # Agent package (also exposed separately)
  inherit stackpanel-agent;

  # Default package (placeholder)
  default = pkgs.hello;
}
