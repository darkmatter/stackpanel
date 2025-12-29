{ pkgs, inputs, system, ... }:
pkgs.stdenvNoCC.mkDerivation {
  name = "tasks";
  buildInputs = [
    inputs.devenv.packages.${system}.devenv-tasks-fast-build
  ];
  buildCommand = ''
    mkdir -p $out/bin
    cp ${inputs.devenv.packages.${system}.devenv-tasks-fast-build}/bin/devenv-tasks-fast-build $out/bin/tasks
  '';
  # No need for any special runtime dependencies
  passthru = {};
}