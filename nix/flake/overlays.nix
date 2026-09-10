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

  # bun: nixpkgs lags upstream bun releases (pinned nixpkgs ships 1.3.3).
  # Pin to 1.4 so `pkgs.bun` matches what `bun upgrade` installs.
  # To bump: set `version` and refresh ALL four platform hashes via
  #   nix store prefetch-file --hash-type sha256 <release-url>
  (final: prev: {
    bun =
      let
        version = "1.4.2";
        sources = {
          "aarch64-darwin" = prev.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-aarch64.zip";
            hash = "sha256-kJh6OhbX21VtiGrD1VHnttPt8KHPQ6yu1iLoZ2vh0S8=";
          };
          "aarch64-linux" = prev.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-aarch64.zip";
            hash = "sha256-VDKLvC2cjgyfiSxUTWbFeoO4QTnjSQnl7oF1jxrI/ac=";
          };
          "x86_64-darwin" = prev.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-x64-baseline.zip";
            hash = "sha256-utW71s8U0JgNEV9ZVMn/kE32GdXplNLaH/zNPzFjALA=";
          };
          "x86_64-linux" = prev.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64.zip";
            hash = "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=";
          };
        };
      in
      prev.bun.overrideAttrs (old: {
        inherit version;
        # ⚠ `src` must be overridden explicitly: the pinned nixpkgs bun
        # package uses `mkDerivation rec`, where `src` is captured at eval
        # time from the ORIGINAL 1.3.3 `passthru.sources`. `old.passthru`
        # inside overrideAttrs is the pre-override attrs, so the new
        # fetchurl must be referenced from this overlay's own `sources`,
        # not from `old.passthru.sources`.
        src = sources.${prev.stdenv.hostPlatform.system};
        __intentionallyOverridingVersion = true;
        passthru = old.passthru // {
          inherit sources;
        };
      });
  })
]
