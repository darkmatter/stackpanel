# ==============================================================================
# evalconfig.nix
#
# Stackpanel configuration evaluator for Go CLI/agent integration.
#
# This file evaluates the stackpanel configuration from devenv.nix and outputs
# it as JSON for use by the Go CLI/agent. It eliminates state drift by allowing
# tools to read live configuration directly from Nix.
#
# Configuration sources (in priority order):
#   1. STACKPANEL_NIX_CONFIG - Nix store path (set by devenv enterShell)
#   2. State file - .stackpanel/state/stackpanel.json (fallback)
#
# Usage (must be run with --impure to read STACKPANEL_* env vars):
#   nix eval --impure --json -f nix/stackpanel/core/lib/evalconfig.nix
#
# Or from any directory:
#   nix eval --impure --json -f /path/to/project/nix/stackpanel/core/lib/evalconfig.nix
#
# The Go agent/CLI can call this to get live config without state.json,
# eliminating state drift entirely.
# ==============================================================================
let
  # Get project root from environment (set by stackpanel enterShell)
  # Falls back to searching for devenv.nix from PWD
  envRoot = builtins.getEnv "STACKPANEL_ROOT";
  pwd = builtins.getEnv "PWD";

  findProjectRoot =
    dir:
    if dir == "" then
      null
    else if builtins.pathExists (dir + "/devenv.nix") then
      dir
    else if dir == "/" || dir == "" then
      null
    else
      findProjectRoot (dirOf dir);

  # Convert string path to actual path for dirOf
  dirOf =
    path:
    let
      parts = builtins.filter (x: x != "") (builtins.split "/" path);
      parent = builtins.concatStringsSep "/" (
        builtins.genList (i: builtins.elemAt parts i) (builtins.length parts - 1)
      );
    in
    if builtins.length parts <= 1 then "/" else "/" + parent;

  projectRoot = if envRoot != "" then envRoot else findProjectRoot pwd;

  # Priority 1: Read from Nix store config (set by devenv enterShell)
  # This is the most authoritative source when inside a devenv shell
  nixConfigPath = builtins.getEnv "STACKPANEL_NIX_CONFIG";

  configFromNixStore =
    if nixConfigPath != "" && builtins.pathExists nixConfigPath then
      let
        raw = builtins.fromJSON (builtins.readFile nixConfigPath);
        # Replace $STACKPANEL_ROOT placeholder with actual value
        fixProjectRoot =
          config:
          if config.projectRoot == "$STACKPANEL_ROOT" && envRoot != "" then
            config // { projectRoot = envRoot; }
          else
            config;
      in
      fixProjectRoot raw
    else
      null;

  # Priority 2: Read from state file as fallback
  stateDir = builtins.getEnv "STACKPANEL_STATE_DIR";
  stateFile =
    if stateDir != "" then
      stateDir + "/stackpanel.json"
    else if projectRoot != null then
      projectRoot + "/.stackpanel/state/stackpanel.json"
    else
      null;

  configFromState =
    if stateFile != null && builtins.pathExists stateFile then
      builtins.fromJSON (builtins.readFile stateFile)
    else
      null;
in
if configFromNixStore != null then
  configFromNixStore
else if configFromState != null then
  configFromState
else
  {
    error = "No stackpanel configuration found";
    hint = "Run this from within a devenv shell, or ensure STACKPANEL_STATE_DIR is set";
    projectRoot = projectRoot;
    envRoot = envRoot;
    stateFile = stateFile;
    nixConfigPath = nixConfigPath;
  }
