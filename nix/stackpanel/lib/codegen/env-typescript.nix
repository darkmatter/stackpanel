# ==============================================================================
# env-typescript.nix - DEPRECATED
#
# This module has been superseded by env-package.nix which generates the
# complete packages/gen/env structure including:
#   - .sops.yaml configuration
#   - TypeScript znv modules
#   - Entrypoint loaders
#
# This file is kept for backwards compatibility but delegates to env-package.nix.
# ==============================================================================
{ lib, config, ... }:
let
  envPackage = import ./env-package.nix { inherit lib config; };
in
{
  # Re-export everything from env-package
  inherit (envPackage) generatedFiles fileEntries enabled;

  # Backwards compatibility: filter to just TypeScript files
  tsGeneratedFiles = lib.filterAttrs (path: _: lib.hasSuffix ".ts" path) envPackage.generatedFiles;

  tsFileEntries = lib.filterAttrs (path: _: lib.hasSuffix ".ts" path) envPackage.fileEntries;
}
