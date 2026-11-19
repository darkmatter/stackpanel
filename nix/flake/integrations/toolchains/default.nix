{ localInputs, ... }:
{
  overlays = import ../../overlays.nix { inherit localInputs; };
}
