# ==============================================================================
# load-config.nix - Stackpanel config discovery and normalization
#
# Discovers the stackpanel config and exposes helpers for the supported
# config shapes:
#   1. plain attrset
#   2. module-style function: { config, lib, pkgs, ... }: { ... }
#   3. tree layout (".stack/config/" loaded via haumea)
#
# Discovery (first match wins for the "file" path; the tree always
# overlays on top when ".stack/config/" exists):
#   1. .stack/_internal.nix      (machine-generated, full module context)
#   2. .stack/config.nix         (human-editable single file)
#   3. .stackpanel/_internal.nix (legacy path)
#   4. .stackpanel/config.nix    (legacy path)
#   + .stack/config/             (optional tree, overlays the file shape)
#
# Tree layout semantics:
#   Each top-level config key may be a `<key>.nix` file or a `<key>/`
#   subdirectory containing one `.nix` file per map entry (apps/web.nix,
#   variables/<id>.nix, ...). Files are loaded with haumea's default loader
#   so they may be plain attrsets *or* `{ config, lib, pkgs, ... }: { ... }`
#   functions. Visibility rules apply (`_foo.nix` hidden outside its dir).
#
#   Map keys with characters that are illegal in filenames (e.g. "/") use
#   `--` as a separator -- a transformer rewrites the attrset key on the
#   way out so the runtime sees the original key. Example:
#     .stack/config/variables/--dev--postgres-url.nix
#       -> stackpanel.variables."/dev/postgres-url"
#
#   `--` is used (not `__`) because haumea reserves underscore-prefixed
#   filenames for visibility scoping; `__dev--...` would be hidden from
#   the loader. See EncodeTreeFileKey in apps/stackpanel-go/pkg/nixdata.
# ==============================================================================
{
  self,
  inputs ? { },
}:
let
  internal = self + "/.stack/_internal.nix";
  simple = self + "/.stack/config.nix";
  legacyInternal = self + "/.stackpanel/_internal.nix";
  legacySimple = self + "/.stackpanel/config.nix";

  path =
    if builtins.pathExists internal then internal
    else if builtins.pathExists simple then simple
    else if builtins.pathExists legacyInternal then legacyInternal
    else if builtins.pathExists legacySimple then legacySimple
    else null;

  raw = if path != null then import path else null;

  treeDir =
    if builtins.pathExists (self + "/.stack/config") then self + "/.stack/config"
    else if builtins.pathExists (self + "/.stackpanel/config") then self + "/.stackpanel/config"
    else null;

  hasTree = treeDir != null;
  haumea = inputs.haumea or null;

  # Decode `--` -> `/` in map-entry filenames. Matches what the Go
  # writer encodes when materialising entity files (EncodeTreeFileKey
  # in apps/stackpanel-go/pkg/nixdata/paths.go).
  decodeKey =
    name:
    builtins.replaceStrings [ "--" ] [ "/" ] name;

  # Apply `decodeKey` to attribute names for one level of an attrset.
  # Used to remap map-entity directories (apps/, variables/, ...) where
  # the on-disk filename has been encoded.
  remapMapEntityKeys =
    attrs:
    builtins.listToAttrs (
      map (n: {
        name = decodeKey n;
        value = attrs.${n};
      }) (builtins.attrNames attrs)
    );

  # Names of map entities whose entries may have keys containing `/`.
  # Must stay roughly in sync with apps/stackpanel-go/pkg/nixdata
  # (PrefersConsolidatedConfig + IsMapEntity).
  mapEntities = [
    "apps"
    "variables"
    "users"
    "envs"
  ];

  # Transformer that rewrites encoded filenames back to their canonical
  # keys for any directory that maps a known map entity. Cursor is the
  # path of the directory being transformed; cursor == [ entity ] means
  # we're inside that entity's directory.
  decodeMapEntityTransformer =
    cursor: attrs:
    if (builtins.length cursor) == 1 && (builtins.elem (builtins.head cursor) mapEntities) then
      remapMapEntityKeys attrs
    else
      attrs;

  loadTree =
    args:
    if !hasTree then
      { }
    else if haumea == null then
      throw ''
        load-config.nix: ${toString treeDir} exists but the haumea flake
        input is not available. Either:
          1. add haumea to your flake inputs (see this repo's flake.nix
             for the pinned version), or
          2. inline your config back into .stack/config.nix.
      ''
    else
      haumea.lib.load {
        src = treeDir;
        inputs = args;
        transformer = [
          decodeMapEntityTransformer
        ];
      };

  fileResult =
    args:
    if raw == null then
      { }
    else if builtins.isFunction raw then
      raw args
    else
      raw;

  # Top-level merge: tree entries override file entries. For map
  # entities the loader produces an attrset of entries; users who
  # define the same map across both layers get the tree's view of
  # missing entries plus the file's own. Keeping this shallow at the
  # top level is intentional -- mixing the same entity across both
  # layouts is unusual and trying to deep-merge silently is worse
  # than just preferring one shape.
  mergeFileAndTree =
    args:
    let
      file = fileResult args;
      tree = loadTree args;
    in
    file // tree;

in
rec {
  inherit
    path
    raw
    treeDir
    hasTree
    ;

  exists = path != null || hasTree;

  mkStackpanelModule =
    {
      lib,
      pkgs,
    }:
    if !exists then
      { }
    else
      {
        config,
        ...
      }:
      {
        stackpanel = mergeFileAndTree {
          config = config.stackpanel;
          inherit lib pkgs;
        };
      };

  evalResolved =
    {
      lib,
      pkgs,
      config ? { },
    }:
    if !exists then
      { }
    else
      mergeFileAndTree {
        inherit lib pkgs config;
      };
}
