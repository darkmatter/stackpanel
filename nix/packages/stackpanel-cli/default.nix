# Stackpanel CLI package
#
# Build the Go-based CLI tool for managing development services.
#
{
  pkgs,
  lib,
  ...
}:
pkgs.buildGoModule {
  pname = "stackpanel-cli";
  version = "0.1.0";

  src = ../../../apps/cli;

  # This will need to be updated after first build
  # Run: nix-prefetch-url --unpack <url> or use lib.fakeHash
  vendorHash = null; # Uses vendored dependencies

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
