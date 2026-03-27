---
title: Devshell
description: Create reproducible development shells with Nix using stack's mkDevShell.
icon: Terminal
---

# Devshell

Usage (Minimal):

```nix
# flake.nix
devShells.${system}.default = inputs.stack.lib.mkDevShell {
  pkgs = pkgs;
  modules = [
    ({ ... }: { devshell.packages = [ pkgs.nodejs_22 ]; })
  ];
};
```

Usage (Recommended):

```nix
devShells.${system}.default = inputs.stack.lib.mkDevShell {
  pkgs = pkgs;
  includeDefaults = true;
  modules = [
    inputs.stack.lib.devshell.features.aws
    ({ ... }: { stack.aws.enable = true; })
  ];
};
```