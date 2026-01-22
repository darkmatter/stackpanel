# ==============================================================================
# extension-src.nix
#
# Discovery and namespacing utilities for extension src/ directories.
#
# Extensions can provide scripts, healthchecks, and files via a src/ directory:
#
#   src/
#     scripts/       # Shell scripts -> stackpanel.scripts
#       deploy.sh    # -> <extName>:deploy
#       dev.sh       # -> <extName>:dev
#     checks/        # Healthchecks -> stackpanel.healthchecks
#       aws-creds.sh # -> <extName>:aws-creds
#     files/         # Files for stackpanel.files.entries
#       config.ts    # Content source for file generation
#
# Resources are auto-namespaced with the extension name using ":" separator.
# ==============================================================================
{ lib }:
let
  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Remove common script extensions from filename
  removeScriptExt =
    name:
    let
      exts = [
        ".sh"
        ".bash"
        ".zsh"
      ];
      matchingExt = lib.findFirst (ext: lib.hasSuffix ext name) null exts;
    in
    if matchingExt != null then lib.removeSuffix matchingExt name else name;

  # Check if a file is a script (has executable extension or no extension)
  isScriptFile =
    name: type:
    type == "regular"
    && (
      lib.hasSuffix ".sh" name
      || lib.hasSuffix ".bash" name
      || lib.hasSuffix ".zsh" name
      || !(lib.hasInfix "." name)
    );

  # Check if a file is a regular file (for generic file discovery)
  isRegularFile = _name: type: type == "regular";

  # Safely read directory, returning empty attrset if path doesn't exist
  safeReadDir = path: if builtins.pathExists path then builtins.readDir path else { };

in
rec {
  # ============================================================================
  # Script Discovery
  # ============================================================================

  # Discover scripts from an extension's src/scripts/ directory
  # Returns: { "<extName>:<scriptName>" = { path = /path/to/script.sh; }; ... }
  discoverScripts =
    extName: srcDir:
    let
      scriptsDir = srcDir + "/scripts";
      files = safeReadDir scriptsDir;
      scriptFiles = lib.filterAttrs isScriptFile files;
    in
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "${extName}:${removeScriptExt name}" { path = scriptsDir + "/${name}"; }
    ) scriptFiles;

  # ============================================================================
  # Healthcheck Discovery
  # ============================================================================

  # Discover healthchecks from an extension's src/checks/ directory
  # Returns: { "<extName>:<checkName>" = { path = /path/to/check.sh; }; ... }
  discoverHealthchecks =
    extName: srcDir:
    let
      checksDir = srcDir + "/checks";
      files = safeReadDir checksDir;
      checkFiles = lib.filterAttrs isScriptFile files;
    in
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "${extName}:${removeScriptExt name}" { path = checksDir + "/${name}"; }
    ) checkFiles;

  # ============================================================================
  # File Discovery
  # ============================================================================

  # Discover files from an extension's src/files/ directory
  # Returns: { "<filename>" = { path = /path/to/file; extName = "..."; }; ... }
  # Note: Files are NOT namespaced by default (they go to specific paths)
  # The extension module should handle mapping these to actual output paths
  discoverFiles =
    extName: srcDir:
    let
      filesDir = srcDir + "/files";
      files = safeReadDir filesDir;
      regularFiles = lib.filterAttrs isRegularFile files;
    in
    lib.mapAttrs (name: _: {
      path = filesDir + "/${name}";
      inherit extName;
    }) regularFiles;

  # ============================================================================
  # Combined Discovery
  # ============================================================================

  # Discover all resources from an extension's srcDir
  # Returns: { scripts = {...}; healthchecks = {...}; files = {...}; }
  discoverAll =
    extName: srcDir:
    if srcDir == null then
      {
        scripts = { };
        healthchecks = { };
        files = { };
      }
    else
      {
        scripts = discoverScripts extName srcDir;
        healthchecks = discoverHealthchecks extName srcDir;
        files = discoverFiles extName srcDir;
      };

  # ============================================================================
  # Merge Utilities
  # ============================================================================

  # Merge discovered resources with explicit definitions
  # Explicit definitions take priority (come second in merge)
  mergeWithExplicit =
    discovered: explicit:
    lib.recursiveUpdate discovered explicit;

  # Merge all extensions' discovered scripts into a single attrset
  # extensions: { extName = { srcDir = ...; ... }; ... }
  mergeAllScripts =
    extensions:
    lib.foldl' (
      acc: extName:
      let
        ext = extensions.${extName};
      in
      if ext.srcDir or null != null then acc // (discoverScripts extName ext.srcDir) else acc
    ) { } (lib.attrNames extensions);

  # Merge all extensions' discovered healthchecks into a single attrset
  mergeAllHealthchecks =
    extensions:
    lib.foldl' (
      acc: extName:
      let
        ext = extensions.${extName};
      in
      if ext.srcDir or null != null then acc // (discoverHealthchecks extName ext.srcDir) else acc
    ) { } (lib.attrNames extensions);
}
