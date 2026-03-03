# ==============================================================================
# eval.nix
#
# Stackpanel configuration evaluator for Go CLI/agent integration.
#
# This file evaluates the stackpanel configuration from devenv.nix and outputs
# it as JSON for use by the Go CLI/agent. It eliminates state drift by allowing
# tools to read live configuration directly from Nix.
#
# Configuration sources (in priority order):
#   1. configJson arg  - Nix store path to JSON config (passed by caller)
#   2. stateDir arg    - directory containing stackpanel.json (passed by caller)
#   3. root arg        - project root, state file derived as root/.stackpanel/state/stackpanel.json
#   4. env fallbacks   - STACKPANEL_CONFIG_JSON / STACKPANEL_STATE_DIR / STACKPANEL_ROOT / PWD
#                        (only used when args are null, requires --impure)
#
# Preferred usage (pure — no --impure needed):
#   nix eval --json -f eval.nix --argstr root /path/to/project
#
# Legacy usage (impure — reads env vars):
#   nix eval --impure --json -f eval.nix
#
# The Go agent passes --argstr root <path> so evaluation is pure whenever
# the project root is known.
# ==============================================================================
{
  root ? null,
  configJson ? null,
  stateDir ? null,
}:
let
  # ===========================================================================
  # Resolve effective values — prefer explicit args, fall back to env vars
  # ===========================================================================

  # Project root: arg > STACKPANEL_ROOT env > PWD-based search
  envRoot = builtins.getEnv "STACKPANEL_ROOT";
  envPwd = builtins.getEnv "PWD";

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

  dirOf =
    path:
    let
      parts = builtins.filter (x: x != "") (builtins.split "/" path);
      parent = builtins.concatStringsSep "/" (
        builtins.genList (i: builtins.elemAt parts i) (builtins.length parts - 1)
      );
    in
    if builtins.length parts <= 1 then "/" else "/" + parent;

  effectiveRoot =
    if root != null then
      root
    else if envRoot != "" then
      envRoot
    else
      findProjectRoot envPwd;

  # Config JSON path: arg > STACKPANEL_CONFIG_JSON env
  envConfigJson = builtins.getEnv "STACKPANEL_CONFIG_JSON";
  effectiveConfigJson =
    if configJson != null then
      configJson
    else if envConfigJson != "" then
      envConfigJson
    else
      null;

  # State dir: arg > STACKPANEL_STATE_DIR env > derived from root
  envStateDir = builtins.getEnv "STACKPANEL_STATE_DIR";
  effectiveStateDir =
    if stateDir != null then
      stateDir
    else if envStateDir != "" then
      envStateDir
    else
      null;

  # ===========================================================================
  # Priority 1: Read from config JSON (Nix store path set by devenv enterShell)
  # ===========================================================================
  configFromJson =
    if effectiveConfigJson != null && builtins.pathExists effectiveConfigJson then
      let
        raw = builtins.fromJSON (builtins.readFile effectiveConfigJson);
        # Replace $STACKPANEL_ROOT placeholder with actual value
        fixProjectRoot =
          config:
          if config.projectRoot == "$STACKPANEL_ROOT" && effectiveRoot != null then
            config // { projectRoot = effectiveRoot; }
          else
            config;
      in
      fixProjectRoot raw
    else
      null;

  # ===========================================================================
  # Priority 2: Read from state file
  # Try explicit stateDir first, then derive from root (.stack/profile, then .stackpanel/state)
  # ===========================================================================
  stateFileCandidates =
    if effectiveStateDir != null then
      [ (effectiveStateDir + "/stackpanel.json") ]
    else if effectiveRoot != null then
      [
        (effectiveRoot + "/.stack/profile/stackpanel.json")
        (effectiveRoot + "/.stackpanel/state/stackpanel.json")
      ]
    else
      [ ];

  stateFile =
    let
      existing = builtins.filter (p: builtins.pathExists p) stateFileCandidates;
    in
    if existing != [ ] then builtins.head existing else null;

  configFromState =
    if stateFile != null && builtins.pathExists stateFile then
      builtins.fromJSON (builtins.readFile stateFile)
    else
      null;

in
if configFromJson != null then
  configFromJson
else if configFromState != null then
  configFromState
else
  {
    error = "No stackpanel configuration found";
    hint =
      if root == null then
        "Pass --argstr root /path/to/project, or run from within a devenv shell"
      else
        "No config at ${effectiveRoot}/.stack/profile/stackpanel.json (or .stackpanel/state) — run 'stackpanel preflight' first";
    projectRoot = effectiveRoot;
    stateFile = stateFile;
    configJsonPath = effectiveConfigJson;
  }
