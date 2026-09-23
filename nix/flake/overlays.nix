# ==============================================================================
# overlays.nix — Required nixpkgs overlays for Stackpanel flakes
# ==============================================================================
{ localInputs }:
[
  localInputs.gomod2nix.overlays.default
  localInputs.bun2nix.overlays.default
  (
    final: _prev:
    let
      # nixpkgs-unstable (26.11) dropped x86_64-darwin; importing it for
      # that system throws at eval time and breaks whole-flake evaluation
      # (e.g. flakehub-push enumerating every system's outputs). Fall back
      # to the previous package set's Go tools there — must be `_prev`,
      # not `final`, since `final` includes this overlay (infinite
      # recursion). The unstable set only exists for Go 1.26-compatible
      # tooling on supported platforms.
      unstablePkgs =
        if final.stdenv.hostPlatform.system == "x86_64-darwin" then
          _prev
        else
          import localInputs.nixpkgs-unstable {
            inherit (final.stdenv.hostPlatform) system;
          };
    in
    {
      inherit (unstablePkgs) delve;
      inherit (unstablePkgs) gopls;
      inherit (unstablePkgs) gotools;
      inherit (unstablePkgs) gofumpt;
      inherit (unstablePkgs) golines;
    }
  )
]
