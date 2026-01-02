# ==============================================================================
# stackpanel-go/default.nix
#
# Nix derivation that exposes the shared stackpanel-go module as a source
# package for use in Go module replace directives.
#
# This is NOT a built Go package - it simply copies the source files into the
# Nix store so other packages (like stackpanel-cli) can reference it during
# their build process for local module resolution.
#
# Build inputs:
#   - Source: packages/stackpanel-go (shared Go library with types, state, etc.)
#   - Output: Source files in $out (no compilation)
#
# Usage: Called by other Nix packages that need the stackpanel-go source.
# ==============================================================================
{
  pkgs,
  lib,
  ...
}:
pkgs.stdenv.mkDerivation {
  pname = "stackpanel-go-src";
  version = "0.1.0";

  src = ../../../../packages/stackpanel-go;

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p $out
    cp -R ./* $out/
  '';

  meta = with lib; {
    description = "Stackpanel shared Go module (source)";
    license = licenses.mit;
  };
}
