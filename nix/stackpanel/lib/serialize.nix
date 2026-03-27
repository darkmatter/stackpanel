# ==============================================================================
# serialize.nix
#
# Serialization helpers for ensuring config values are JSON-safe.
#
# Nix configs can contain derivations, functions, and other non-serializable
# values. This module provides utilities to filter these out, ensuring the
# resulting attrset can be safely converted to JSON.
#
# Usage:
#   let
#     serializeLib = import ./serialize.nix { inherit lib; };
#   in
#   serializeLib.filterSerializable config.stackpanel
#
#   # Or with skip list for problematic attributes:
#   serializeLib.filterSerializableWithSkip [ "users" "devshell" ] config.stackpanel
#
# ==============================================================================
{ lib }:
let
  # Check if a value is serializable to JSON
  # Returns true for: strings, numbers, bools, null, lists, attrsets (non-derivation)
  # Returns false for: functions, derivations, paths (store paths are ok as strings)
  isSerializable =
    value:
    let
      type = builtins.typeOf value;
    in
    if type == "null" then
      true
    else if type == "bool" then
      true
    else if type == "int" then
      true
    else if type == "float" then
      true
    else if type == "string" then
      true
    else if type == "path" then
      # Paths become strings when serialized, but can cause issues
      # We convert them to strings explicitly
      true
    else if type == "list" then
      # Lists are serializable if all elements are
      builtins.all isSerializable value
    else if type == "set" then
      # Attrsets are serializable if they're not derivations and all values are serializable
      # Derivations have a `type` attr set to "derivation"
      !(value ? type && value.type == "derivation")
      && !(value ? _type) # Also filter out internal module system types
      && !(value ? __functor) # Filter out functors
    else if type == "lambda" then
      false
    else
      # Unknown types are not serializable
      false;

  # Safely access a value, returning null if it throws (e.g., module type errors)
  # Note: We use shallow tryEval to avoid stack overflow on circular/deep structures
  safeAccess =
    value:
    let
      result = builtins.tryEval value;
    in
    if result.success then result.value else null;

  # Check if a value can be safely accessed without throwing
  canAccess =
    value:
    let
      result = builtins.tryEval value;
    in
    result.success;

  # Attributes that are known to cause issues during serialization
  # (contain module system internals, circular refs, or type validation errors)
  defaultSkipAttrs = [
    "users"
    "appModules"
    "commandModules"
    "appsComputed"
    "commandsComputed"
    "extensionsComputed"
    "modulesComputed"
    "modulesComputedAll"
    "modulesList"
    "modulesListAll"
    "modulesBuiltin"
    "modulesExternal"
    "userPackages"
    # Skip outputs: contains Nix derivations (packages for `nix build`). Forcing
    # them during serialization instantiates every input derivation — very slow
    # for large lockfiles (e.g. bun.nix with ~5000 fetchurl calls).
    "outputs"
    # Skip bun: packages.apps contains stdenv.mkDerivation results that pull in
    # fetchBunDeps, which instantiates thousands of FODs from bun.nix.
    "bun"
  ];

  # Attributes within devshell that should be serialized
  # (most devshell attrs contain packages which aren't serializable)
  devshellSerializableAttrs = [
    "_commandsSerializable"
    "env"
  ];

  # Helper to serialize a package derivation to JSON-safe format
  serializePackage =
    pkg:
    if builtins.isAttrs pkg && pkg ? name then
      {
        name = pkg.pname or pkg.name or "unknown";
        version = pkg.version or "";
        attrPath = pkg.meta.mainProgram or pkg.pname or pkg.name or "";
        source = "devshell";
      }
    else if builtins.isString pkg then
      {
        name = pkg;
        version = "";
        attrPath = pkg;
        source = "devshell";
      }
    else
      {
        name = "unknown";
        version = "";
        attrPath = "";
        source = "devshell";
      };

  # Special handling for devshell - only serialize specific attributes
  filterDevshell =
    devshell: lib.filterAttrs (name: _: builtins.elem name devshellSerializableAttrs) devshell;

  # Recursively filter an attrset to only include serializable values
  # Non-serializable values are removed entirely
  # Uses tryEval to handle module system type errors gracefully
  filterSerializableAttrsWithSkip =
    skipAttrs: attrs:
    let
      # First, filter to only attributes we can safely access
      accessiblePairs = lib.filterAttrs (
        name: value:
        # Skip internal/private attributes (except _commandsSerializable), skip list, and inaccessible values
        !(lib.hasPrefix "_" name && name != "_commandsSerializable")
        && !(builtins.elem name skipAttrs)
        && canAccess value
      ) attrs;
      # Then filter to only serializable values
      filteredPairs = lib.filterAttrs (name: value: isSerializable value) accessiblePairs;
    in
    lib.mapAttrs (
      name: value:
      let
        safeValue = safeAccess value;
      in
      if safeValue == null then
        null
      # Special handling for devshell - only serialize specific attributes
      else if name == "devshell" && builtins.typeOf safeValue == "set" then
        filterSerializableAttrsWithSkip skipAttrs (filterDevshell safeValue)
      else if
        builtins.typeOf safeValue == "set" && !(safeValue ? type && safeValue.type == "derivation")
      then
        filterSerializableAttrsWithSkip skipAttrs safeValue
      else if builtins.typeOf safeValue == "list" then
        filterSerializableList safeValue
      else if builtins.typeOf safeValue == "path" then
        # Convert paths to strings
        toString safeValue
      else
        safeValue
    ) filteredPairs;

  # Default version using defaultSkipAttrs
  filterSerializableAttrs = filterSerializableAttrsWithSkip defaultSkipAttrs;

  # Filter a list to only include serializable values
  filterSerializableList =
    lst:
    let
      # Filter to accessible and serializable values
      filtered = builtins.filter (value: canAccess value && isSerializable value) lst;
    in
    map (
      value:
      let
        safeValue = safeAccess value;
      in
      if safeValue == null then
        null
      else if builtins.typeOf safeValue == "set" then
        filterSerializableAttrs safeValue
      else if builtins.typeOf safeValue == "list" then
        filterSerializableList safeValue
      else if builtins.typeOf safeValue == "path" then
        toString safeValue
      else
        safeValue
    ) filtered;

  # Main entry point: filter any value to be serializable
  filterSerializable =
    value:
    let
      type = builtins.typeOf value;
    in
    if type == "set" then
      filterSerializableAttrs value
    else if type == "list" then
      filterSerializableList value
    else if isSerializable value then
      if type == "path" then toString value else value
    else
      null;

  # Filter with custom skip list
  filterSerializableWithSkip =
    skipAttrs: value:
    let
      type = builtins.typeOf value;
    in
    if type == "set" then
      filterSerializableAttrsWithSkip skipAttrs value
    else if type == "list" then
      filterSerializableList value
    else if isSerializable value then
      if type == "path" then toString value else value
    else
      null;

  # Validate that a value is fully serializable (throws on failure)
  # Useful for catching issues early
  assertSerializable =
    name: value:
    let
      check =
        v: path:
        let
          type = builtins.typeOf v;
        in
        if type == "lambda" then
          throw "Value at ${path} is a function and cannot be serialized to JSON"
        else if type == "set" && v ? type && v.type == "derivation" then
          throw "Value at ${path} is a derivation and cannot be serialized to JSON"
        else if type == "set" && v ? _type then
          throw "Value at ${path} has _type attribute (module system internal) and cannot be serialized to JSON"
        else if type == "set" then
          lib.mapAttrsToList (k: val: check val "${path}.${k}") v
        else if type == "list" then
          lib.imap0 (i: val: check val "${path}[${toString i}]") v
        else
          true;
    in
    check value name;

  # Try to serialize to JSON, returning null on failure
  # Useful for testing if a value is serializable
  trySerialize =
    value:
    let
      result = builtins.tryEval (builtins.toJSON value);
    in
    if result.success then result.value else null;
in
{
  inherit
    isSerializable
    filterSerializable
    filterSerializableWithSkip
    filterSerializableAttrs
    filterSerializableAttrsWithSkip
    filterSerializableList
    assertSerializable
    trySerialize
    safeAccess
    canAccess
    defaultSkipAttrs
    serializePackage
    ;
}
