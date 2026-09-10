# ==============================================================================
# stackpanel-cli/default.nix
#
# Nix package definition for the StackPanel CLI - a unified Go-based command-line
# tool that includes both the CLI and agent functionality.
#
# The CLI and agent have been merged into a single application at apps/stackpanel-go.
# The agent is now a subcommand: `stack agent`
#
# Build inputs:
#   - Source: apps/stackpanel-go (unified Go module with CLI, agent, and shared packages)
#   - Output: stack binary (with a `stackpanel` alias symlink)
#
# Usage:
#   - Run `stack` for interactive TUI
#   - Run `stack agent` to start the local agent server
#   - Run `stack --help` for all available commands
#   - `stackpanel` is available as an alias for `stack`
# ==============================================================================
{
  pkgs,
  lib,
  # Stackpanel flake (`localFlake` / `self`) whose rev and lastModifiedDate
  # are stamped into `stack --version`. Optional: omitted builds keep
  # GitCommit/BuildDate as "unknown" (local `go build` fills them from VCS).
  flake ? null,
  ...
}:
let
  repoRoot = ../../../..;

  # Source path - the unified stackpanel-go app
  srcPath = repoRoot + "/apps/stackpanel-go";

  version = "0.1.0";

  # Must match the Go import path of the package that declares Version/GitCommit/BuildDate.
  ldflagPkg = "github.com/darkmatter/stackpanel/stackpanel-go/cmd/cli";

  formatBuildDate =
    d:
    if builtins.isString d && builtins.stringLength d >= 14 then
      "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}T${builtins.substring 8 2 d}:${builtins.substring 10 2 d}:${builtins.substring 12 2 d}Z"
    else
      "unknown";

  gitCommit = if flake == null then "unknown" else flake.rev or flake.dirtyRev or "unknown";

  buildDate = if flake == null then "unknown" else formatBuildDate (flake.lastModifiedDate or "");
in
pkgs.buildGoApplication {
  pname = "stackpanel";
  inherit version;

  # Use repo root as src so local replace directives (../../packages/proto/gen/gopb)
  # are available in the source tree. pwd points to the app's go.mod location.
  # modRoot tells the build hook to cd into the app dir within the source.
  src = repoRoot;
  pwd = srcPath;
  modRoot = "apps/stackpanel-go";
  modules = srcPath + "/gomod2nix.toml";
  subPackages = [ "." ];

  # Skip tests during build (some tests require specific environment)
  doCheck = false;

  ldflags = [
    "-s"
    "-w"
    "-X ${ldflagPkg}.Version=${version}"
    "-X ${ldflagPkg}.GitCommit=${gitCommit}"
    "-X ${ldflagPkg}.BuildDate=${buildDate}"
  ];

  # Go names the binary after the module's last path component (stackpanel-go).
  # `stack` is the canonical command name; `stackpanel` is kept as an alias symlink.
  postInstall = ''
    mv $out/bin/stackpanel-go $out/bin/stack
    ln -s stack $out/bin/stackpanel
  '';

  meta = with lib; {
    description = "Stackpanel unified CLI and agent";
    mainProgram = "stack";
    homepage = "https://github.com/darkmatter/stackpanel";
    license = licenses.mit;
    maintainers = [ ];
  };
}
