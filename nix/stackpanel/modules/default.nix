# ==============================================================================
# modules/default.nix - Module Discovery and Auto-Import
#
# This file handles module imports in two ways:
#
# 1. AUTO-DISCOVERY: Directory modules (new structure) are auto-imported
#    - module-name/default.nix
#    - Excludes directories starting with _ or .
#
# 2. EXPLICIT IMPORTS: Legacy single-file modules are imported explicitly
#    - These are listed below and should be migrated to directory structure
#
# The `_template/` directory provides the template for new modules.
#
# For fast metadata access without full evaluation, use:
#   config.stackpanel._moduleMetas.<module-id>
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  # Read the modules directory
  modulesDir = ./.;
  dirContents = builtins.readDir modulesDir;

  # ---------------------------------------------------------------------------
  # Auto-discovery: Only import DIRECTORY modules (new structure)
  # ---------------------------------------------------------------------------
  # Exclude:
  #   - _template, _*, .* (hidden/template directories)
  #   - Files (legacy modules are imported explicitly below)
  isAutoImportable = name: type:
    let
      isHidden = lib.hasPrefix "_" name || lib.hasPrefix "." name;
      isDirectory = type == "directory";
    in
    isDirectory && !isHidden;

  autoImportDirs = lib.filterAttrs isAutoImportable dirContents;
  autoImports = lib.mapAttrsToList (name: _: ./${name}) autoImportDirs;

  # ---------------------------------------------------------------------------
  # Explicit imports: Legacy single-file modules
  # ---------------------------------------------------------------------------
  # These modules should be migrated to directory structure over time.
  # Do NOT add new modules here - create a directory module instead.
  #
  # As of 2025-01-24, all legacy modules have been migrated to directory structure:
  # - git-hooks -> git-hooks/
  # - ci-formatters -> ci-formatters/
  # - go -> go/
  # - app-commands -> app-commands/
  # - entrypoints -> entrypoints/
  # - process-compose -> process-compose/
  # - turbo -> turbo/
  #
  # NOTE: bun.nix is excluded - it has conflicts and was never imported
  # NOTE: devenv-*.nix are excluded - they require devenvSchema via wrapDevenv
  legacyImports = [
  ];

  # ---------------------------------------------------------------------------
  # Fast Metadata Discovery
  # ---------------------------------------------------------------------------
  # Read meta.nix from each directory module for fast access without full eval.
  # This is useful for the agent to list available modules quickly.

  # Try to load meta.nix from each directory, returning null if it doesn't exist
  tryLoadMeta = name:
    let
      metaPath = ./${name}/meta.nix;
    in
    if builtins.pathExists metaPath
    then import metaPath
    else null;

  moduleMetas = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs (name: _: tryLoadMeta name) autoImportDirs
  );

in
{
  imports = autoImports ++ legacyImports;

  # Expose module metadata for fast discovery
  # Access via: config.stackpanel._moduleMetas.oxlint.name
  config.stackpanel._moduleMetas = moduleMetas;
}
