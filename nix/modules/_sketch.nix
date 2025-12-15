# ============================================================================
# STACKPANEL MODULE SKETCHES
# ============================================================================
# These are pseudo-code brainstorming ideas. Delete what doesn't resonate.
# The goal: find patterns that feel right before committing to structure.
#
# KEY QUESTION: What's the "unit" of stackpanel?
#   A) flake-parts module (runs at flake eval time)
#   B) devenv module (runs in devshell context)
#   C) Both - some things are flake-level, some are devenv-level
#
# My take: (C) - but devenv modules import INTO flake-parts via devenv.flakeModule
# ============================================================================

# ============================================================================
# PATTERN 1: "Minimal viable module"
# Just options + config. No magic.
# ============================================================================
/*
{ lib, config, ... }:
let cfg = config.stackpanel.secrets;
in {
  options.stackpanel.secrets = {
    enable = lib.mkEnableOption "secrets";
    users = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;  # github -> pubkey
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Just wire things up
  };
}
*/

# ============================================================================
# PATTERN 2: "Builder pattern" - module returns a function
# Useful when you need to parameterize at import time
# ============================================================================
/*
# In modules/secrets/default.nix
{ agenixInput }:  # <-- takes the input as a parameter
{ lib, config, pkgs, ... }:
let cfg = config.stackpanel.secrets;
in {
  options.stackpanel.secrets.enable = lib.mkEnableOption "secrets";

  config = lib.mkIf cfg.enable {
    # Now we have access to agenixInput
    environment.systemPackages = [ agenixInput.packages.${pkgs.system}.default ];
  };
}

# Usage in flake.nix:
imports = [
  (import ./modules/secrets { agenixInput = inputs.agenix; })
];
*/

# ============================================================================
# PATTERN 3: "Files as data" - generate files declaratively
# This is the core of stackpanel's "generate" concept
# ============================================================================
/*
{ lib, config, pkgs, ... }:
let
  cfg = config.stackpanel;

  # Collect all files from all enabled modules
  allFiles = lib.filterAttrs (_: v: v != null) cfg.generatedFiles;
in {
  options.stackpanel.generatedFiles = lib.mkOption {
    type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
    default = {};
    description = "Files to generate. Path -> content.";
  };

  # Other modules just add to this:
  # config.stackpanel.generatedFiles.".github/workflows/ci.yml" = yamlContent;
  # config.stackpanel.generatedFiles."Dockerfile" = dockerContent;

  config.packages.generate = pkgs.writeShellScriptBin "stackpanel-generate" ''
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: content: ''
      mkdir -p "$(dirname "${path}")"
      cat > "${path}" << 'STACKPANEL_EOF'
    ${content}
    STACKPANEL_EOF
      echo "Generated: ${path}"
    '') allFiles)}
  '';
}
*/

# ============================================================================
# PATTERN 4: "Layered modules" - base + feature modules
# Like NixOS profiles
# ============================================================================
/*
# modules/profiles/minimal.nix - just the essentials
{ ... }: {
  stackpanel.devenv.enable = true;
  stackpanel.vscode.enable = true;
}

# modules/profiles/full.nix - everything
{ ... }: {
  imports = [ ./minimal.nix ];
  stackpanel.secrets.enable = true;
  stackpanel.ci.github.enable = true;
  stackpanel.container.enable = true;
}

# User just picks a profile:
imports = [ inputs.stackpanel.flakeModules.profiles.full ];
*/

# ============================================================================
# PATTERN 5: "Convention over configuration"
# Auto-detect and configure based on project structure
# ============================================================================
/*
{ lib, config, ... }:
let
  cfg = config.stackpanel;
  root = cfg.projectRoot;

  # Auto-detection
  hasPackageJson = builtins.pathExists (root + "/package.json");
  hasGoMod = builtins.pathExists (root + "/go.mod");
  hasCargoToml = builtins.pathExists (root + "/Cargo.toml");

in {
  options.stackpanel = {
    projectRoot = lib.mkOption { type = lib.types.path; };
    autoDetect = lib.mkEnableOption "auto-detect project type" // { default = true; };
  };

  config = lib.mkIf cfg.autoDetect {
    stackpanel.languages.javascript.enable = lib.mkDefault hasPackageJson;
    stackpanel.languages.go.enable = lib.mkDefault hasGoMod;
    stackpanel.languages.rust.enable = lib.mkDefault hasCargoToml;
  };
}
*/

# ============================================================================
# PATTERN 6: "The escape hatch" - raw config passthrough
# When abstraction gets in the way
# ============================================================================
/*
{ lib, config, ... }:
{
  options.stackpanel.devenv.extraConfig = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Raw devenv config, merged last";
  };

  # Then in the devenv module:
  config.devenv.shells.default = lib.mkMerge [
    { /* stackpanel's managed config */ }
    config.stackpanel.devenv.extraConfig  # user's escape hatch
  ];
}
*/

# ============================================================================
# WHICH PATTERNS RESONATE?
#
# My suggestion for stackpanel v1:
# - Pattern 1 (minimal) as the base
# - Pattern 3 (files as data) for the generate system
# - Pattern 6 (escape hatch) to avoid lock-in
# - Skip Pattern 2/5 complexity until needed
# ============================================================================

{ }: { }  # This file is just for reading, does nothing
