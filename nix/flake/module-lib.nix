# The same SDK namespace is available to project config functions, imports
# resolution, modules and public flake consumers. Preserve the caller's lib.
lib: lib // { stackpanel = import ../stackpanel/lib/sdk.nix { inherit lib; }; }
