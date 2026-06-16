# nix/internal/flake/

Historical notes for earlier flake output experiments.

Active stackpanel flake integration now lives in `nix/flake/default.nix` and is exposed as `inputs.stackpanel.flakeModules.default`. Most consumers should use the higher-level wrapper:

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

For extension modules, pass flake-parts modules through `imports` and Stackpanel modules through `stackpanelImports`:

```nix
stackpanel.lib.mkFlake {
  inherit inputs self;
  imports = [ inputs.some-extension.flakeModules.default ];
  stackpanelImports = [ ./stackpanel-module.nix ];
}
```

Configuration belongs in `.stack/config.nix` using native options such as `stackpanel.languages.*`, `stackpanel.packages`, `stackpanel.devshell.*`, and `stackpanel.process-compose`.

Legacy `devenvModules`, `lib.wrapDevenv`, and standalone devenv template APIs were removed during the flake-parts migration.
