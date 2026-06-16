# nix/flake/devshells/

Historical notes for the old standalone devshell factory.

Active Stackpanel shells are produced by the flake-parts module in `nix/flake/default.nix` and exposed through `stackpanel.lib.mkFlake`:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem = { pkgs, ... }: {
        packages.hello = pkgs.hello;
      };
    };
}
```

Configure shell packages, environment, hooks, and language toolchains in `.stack/config.nix`:

```nix
{
  stackpanel = {
    packages = pkgs: [ pkgs.nodejs_22 pkgs.bun ];
    devshell.env.NODE_ENV = "development";
    languages.javascript.enable = true;
  };
}
```

Reusable Stackpanel extensions should be passed through `stackpanelImports`:

```nix
stackpanel.lib.mkFlake {
  inherit inputs self;
  stackpanelImports = [ ./stackpanel-module.nix ];
}
```

Legacy `inputs.stack.lib.mkDevShell` and `inputs.stack.lib.devshellModules.*` examples are no longer part of the public flake API.
