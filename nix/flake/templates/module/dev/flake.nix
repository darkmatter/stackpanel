{
  description = "Editor tools for this module (not an input of the module flake)";

  inputs.stackpanel.url = "github:darkmatter/stackpanel";
  inputs.nixpkgs.follows = "stackpanel/nixpkgs";

  outputs =
    inputs:
    let
      moduleAuthorOptions =
        inputs.stackpanel.lib.moduleAuthorOptions or (throw ''
          The SDK pinned in dev/flake.lock does not export lib.moduleAuthorOptions.
          Update it with `nix flake update stackpanel --flake ./dev`, then restart nixd.
        '');
    in
    {
      inherit moduleAuthorOptions;

      packages = builtins.mapAttrs (system: pkgs: {
        # Fail at launch on an incompatible SDK, not with empty completions.
        nixd = builtins.seq moduleAuthorOptions (
          pkgs.writeShellScriptBin "nixd" ''
            # Give nixd workers the locked dev flake, independent of their cwd.
            export NIX_PATH="stackpanel-module-dev=${inputs.self}:nixpkgs=${inputs.nixpkgs}"
            export NIX_CONFIG="''${NIX_CONFIG:-}
            pure-eval = false"
            # No NixOS configuration here. Keep package completions and add the
            # same lib.stackpanel namespace the consumer supplies to module.nix.
            exec ${pkgs.nixd}/bin/nixd \
              --nixos-options-expr '(builtins.getFlake (toString <stackpanel-module-dev>)).moduleAuthorOptions' \
              --nixpkgs-expr 'let
                inputs = (builtins.getFlake (toString <stackpanel-module-dev>)).inputs;
                pkgs = inputs.nixpkgs.legacyPackages.${system};
              in pkgs // { lib = pkgs.lib // { stackpanel = inputs.stackpanel.lib; }; }' \
              "$@"
          ''
        );
      }) inputs.nixpkgs.legacyPackages;
    };
}
