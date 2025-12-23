# Stackpanel CLI package
#
# Build the Go-based CLI tool for managing development services.
#
{
  pkgs,
  lib,
  ...
}:
let
  stackpanelGoSrc = pkgs.callPackage ../stackpanel-go {};
in
let
  repoRoot = ../../..;
  compositeSrc = pkgs.runCommand "stackpanel-cli-src" { } ''
    mkdir -p $out/apps/cli
    mkdir -p $out/packages/stackpanel-go
    cp -R ${repoRoot}/apps/cli/* $out/apps/cli/
    cp -R ${repoRoot}/packages/stackpanel-go/* $out/packages/stackpanel-go/
  '';
in
pkgs.buildGoModule {
  pname = "stackpanel-cli";
  version = "0.1.0";

  # Use a minimal source tree that contains both the CLI and the local module
  src = compositeSrc;
  modRoot = "apps/cli";


  # Nix will vendor deterministically from go.mod/go.sum
  vendorHash = "sha256-orEq07AQsCXLLn7bLBZQMA+KXzz3NPuFt4Uh1O8KjaI=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/darkmatter/stackpanel/cli/cmd.Version=0.1.0"
  ];

  # Rename the binary from "cli" to "stackpanel"
  postInstall = ''
    mv $out/bin/cli $out/bin/stackpanel
  '';

  meta = with lib; {
    description = "Stackpanel development CLI";
    homepage = "https://github.com/darkmatter/stackpanel";
    license = licenses.mit;
    maintainers = [];
  };
}
