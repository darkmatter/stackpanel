# Nix notes

This file previously sketched an experimental standalone devshell/devenv adapter design. Stackpanel now uses a single flake-parts path instead.

Use `stackpanel.lib.mkFlake` for project flakes:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = inputs @ { self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;
      stackpanelImports = [ ./stackpanel-module.nix ];
    };
}
```

Project configuration lives in `.stack/config.nix` and uses native options such as `stackpanel.languages.*`, `stackpanel.packages`, `stackpanel.devshell.*`, and `stackpanel.process-compose`.

Removed legacy APIs:

- `devenvModules`
- `lib.wrapDevenv`
- standalone devenv templates
- public `devshellModules` / `mkDevShell` examples from the old adapter design
