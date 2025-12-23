# stackpanel-go as a source derivation for use in replace directives
{
  pkgs,
  lib,
  ...
}:
pkgs.stdenv.mkDerivation {
  pname = "stackpanel-go-src";
  version = "0.1.0";

  src = ../../../packages/stackpanel-go;

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
