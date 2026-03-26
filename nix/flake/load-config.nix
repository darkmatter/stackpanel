# ==============================================================================
# load-config.nix - Stackpanel config discovery and normalization
#
# Discovers the stackpanel config file and exposes helpers for the two supported
# config shapes:
#   1. plain attrset
#   2. module-style function: { config, lib, pkgs, ... }: { ... }
#
# Discovery order:
#   1. .stack/_internal.nix      (machine-generated, full module context)
#   2. .stack/config.nix         (human-editable)
#   3. .stackpanel/_internal.nix (legacy path)
#   4. .stackpanel/config.nix    (legacy path)
# ==============================================================================
{ self }:
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
in
rec {
  inherit path raw;

  exists = path != null;

  mkStackpanelModule =
    {
      lib,
      pkgs,
    }:
    if raw == null then
      {}
    else if builtins.isFunction raw then
      {
        config,
        ...
      }: {
        stackpanel = raw {
          config = config.stackpanel;
          inherit lib pkgs;
        };
      }
    else
      { stackpanel = raw; };

  evalResolved =
    {
      lib,
      pkgs,
      config ? {},
    }:
    if raw == null then
      {}
    else if builtins.isFunction raw then
      raw {
        inherit lib pkgs config;
      }
    else
      raw;
}