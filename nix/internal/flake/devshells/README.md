# nix/internal/flake/devshells/

Historical notes for the old standalone devshell factory.

Active Stackpanel shells are now produced through the flake-parts module exported as `inputs.stackpanel.flakeModules.default`, normally via `stackpanel.lib.mkFlake`:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;
    };
}
```

Configure shell behavior in `.stack/config.nix`:

```nix
{
  stackpanel = {
    packages = pkgs: [ pkgs.nodejs_22 pkgs.bun ];

    devshell.env.NODE_ENV = "development";

    languages.javascript.enable = true;
    languages.go.enable = true;
  };
}
```

For reusable extensions, provide Stackpanel modules through `stackpanelImports`:

```nix
stackpanel.lib.mkFlake {
  inherit inputs self;
  stackpanelImports = [ ./stackpanel-module.nix ];
}
```

Legacy `inputs.stack.devenvModules.*`, `inputs.stack.lib.mkDevShell`, and `inputs.stack.lib.devshellModules.*` examples are no longer part of the public API.
