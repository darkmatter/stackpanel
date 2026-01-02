# ==============================================================================
# packages.nix
#
# Package definitions for stackpanel.
# Defines the CLI, agent, and other packages built by this flake.
# ==============================================================================
{ pkgs, inputs }:
let
  stackpanel-cli-unwrapped = pkgs.callPackage ../stackpanel/packages/stackpanel-cli { };
  
  # Only build agent if gomod2nix.toml exists
  agentGomod2nixExists = builtins.pathExists ../../apps/agent/gomod2nix.toml;
  stackpanel-agent = if agentGomod2nixExists
    then pkgs.callPackage ../stackpanel/packages/stackpanel-agent { }
    else null;
  
  # CLI paths with optional agent
  cliPaths = [ stackpanel-cli-unwrapped ]
    ++ pkgs.lib.optional agentGomod2nixExists stackpanel-agent;
  
  # Agent PATH wrapper (only if agent exists)
  agentPathWrap = if agentGomod2nixExists
    then "--prefix PATH : ${stackpanel-agent}/bin"
    else "";
in
{
  # CLI package (wrapped to include agent in PATH if available)
  stackpanel-cli = pkgs.symlinkJoin {
    name = "stackpanel-cli-${stackpanel-cli-unwrapped.version}";
    paths = cliPaths;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/stackpanel ${agentPathWrap}
    '';
  };

  # Agent package is built into CLI via PATH wrapping
  # If you need to expose it separately, uncomment below (only if gomod2nix.toml exists)
  # stackpanel-agent = stackpanel-agent;

  # Default package (placeholder)
  default = pkgs.hello;
}
