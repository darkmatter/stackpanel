{
  lib,
  cfg,
  extensionSrc,
}:
let
  # ==========================================================================
  # Computed Values
  # ==========================================================================

  # Filter to only enabled extensions
  enabledExtensions = lib.filterAttrs (_: ext: ext.enabled) cfg.extensions;

  # Get builtin extensions
  builtinExtensions = lib.filterAttrs (_: ext: ext.builtin) cfg.extensions;

  # Get external/local extensions
  externalExtensions = lib.filterAttrs (_: ext: !ext.builtin) cfg.extensions;

  # ==========================================================================
  # Auto-Discovery from srcDir
  # ==========================================================================

  # Discover scripts from all enabled extensions with srcDir
  discoveredScripts = lib.foldl' (
    acc: extName:
    let
      ext = cfg.extensions.${extName};
    in
    if ext.enabled && ext.srcDir or null != null then
      acc // (extensionSrc.discoverScripts extName ext.srcDir)
    else
      acc
  ) { } (lib.attrNames cfg.extensions);

  # Discover healthchecks from all enabled extensions with srcDir
  discoveredHealthchecks = lib.foldl' (
    acc: extName:
    let
      ext = cfg.extensions.${extName};
    in
    if ext.enabled && ext.srcDir or null != null then
      acc // (extensionSrc.discoverHealthchecks extName ext.srcDir)
    else
      acc
  ) { } (lib.attrNames cfg.extensions);

in
{
  inherit
    enabledExtensions
    builtinExtensions
    externalExtensions
    discoveredScripts
    discoveredHealthchecks
    ;
}
