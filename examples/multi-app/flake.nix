{
  description = "Stackpanel example: multi-app monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs = { self, stackpanel, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs self; };
}
