# ==============================================================================
# nix/stackpanel/db/lib/data-loader.nix
#
# Data loader supporting both .nix and .json formats.
#
# JSON support uses builtins.fromJSON - no external tools needed.
# When both formats exist for the same base name, .nix takes precedence.
#
# Usage:
#   let
#     dataLoader = import ./data-loader.nix { inherit lib; };
#     data = dataLoader.loadDataDir ./data;
#   in
#   data.users  # loads from users.nix or users.json
#
# ==============================================================================
{ lib }:
let
  # ---------------------------------------------------------------------------
  # File Loading
  # ---------------------------------------------------------------------------

  # Load a single file by path (auto-detects format from extension)
  loadFile =
    path:
    let
      pathStr = toString path;
      isJson = lib.hasSuffix ".json" pathStr;
    in
    if isJson then builtins.fromJSON (builtins.readFile path) else import path;

  # Load a file if it exists, otherwise return default
  loadFileOr = default: path: if builtins.pathExists path then loadFile path else default;

  # ---------------------------------------------------------------------------
  # Directory Loading
  # ---------------------------------------------------------------------------

  # Get base name without extension
  baseName = name: lib.removeSuffix ".nix" (lib.removeSuffix ".json" name);

  # Check if a file is a data file (not internal/default)
  isDataFile =
    name: type:
    type == "regular"
    && (lib.hasSuffix ".nix" name || lib.hasSuffix ".json" name)
    && name != "default.nix"
    && !lib.hasPrefix "_" name;

  # Load all data files from a directory
  # Returns: { users = <data>; apps = <data>; ... }
  # Precedence: .nix > .json
  loadDataDir =
    dir:
    let
      entries = builtins.readDir dir;
      dataFiles = lib.filterAttrs isDataFile entries;

      # Build { baseName = path } choosing .nix over .json
      grouped = lib.foldlAttrs (
        acc: name: _:
        let
          base = baseName name;
          isNix = lib.hasSuffix ".nix" name;
          # Only add if .nix, or if .json and no .nix exists yet
          shouldAdd = isNix || !(acc ? ${base});
        in
        if shouldAdd then acc // { ${base} = dir + "/${name}"; } else acc
      ) { } dataFiles;
    in
    lib.mapAttrs (_: loadFile) grouped;

  # Load data directory with exclusion list
  loadDataDirExcept =
    dir: excludeList:
    let
      entries = builtins.readDir dir;

      isIncluded =
        name: type:
        isDataFile name type
        && !builtins.elem (baseName name) excludeList
        && !builtins.elem name excludeList;

      dataFiles = lib.filterAttrs isIncluded entries;

      grouped = lib.foldlAttrs (
        acc: name: _:
        let
          base = baseName name;
          isNix = lib.hasSuffix ".nix" name;
          shouldAdd = isNix || !(acc ? ${base});
        in
        if shouldAdd then acc // { ${base} = dir + "/${name}"; } else acc
      ) { } dataFiles;
    in
    lib.mapAttrs (_: loadFile) grouped;

  # ---------------------------------------------------------------------------
  # Utilities
  # ---------------------------------------------------------------------------

  # List all base names available in a directory
  listDataNames =
    dir:
    let
      entries = builtins.readDir dir;
      dataFiles = lib.filterAttrs isDataFile entries;
      names = lib.mapAttrsToList (name: _: baseName name) dataFiles;
    in
    lib.unique names;

  # Check if a data file exists (in either format)
  dataFileExists =
    dir: name:
    builtins.pathExists (dir + "/${name}.nix") || builtins.pathExists (dir + "/${name}.json");

  # Get the format of an existing data file
  getDataFileFormat =
    dir: name:
    if builtins.pathExists (dir + "/${name}.nix") then
      "nix"
    else if builtins.pathExists (dir + "/${name}.json") then
      "json"
    else
      null;

  # Find the actual path for a data file
  findDataFile =
    dir: name:
    let
      nixPath = dir + "/${name}.nix";
      jsonPath = dir + "/${name}.json";
    in
    if builtins.pathExists nixPath then
      nixPath
    else if builtins.pathExists jsonPath then
      jsonPath
    else
      null;

in
{
  # Core loading functions
  inherit
    loadFile
    loadFileOr
    loadDataDir
    loadDataDirExcept
    ;

  # Utilities
  inherit
    listDataNames
    dataFileExists
    getDataFileFormat
    findDataFile
    baseName
    ;
}
