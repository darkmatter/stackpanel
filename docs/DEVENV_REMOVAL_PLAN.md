# Devenv Removal Status

Stackpanel no longer depends on `devenv` for its flake runtime. The root flake now uses the exported flake-parts module, and the supported extension path is:

```nix
{
  inputs.stackpanel.url = "github:darkmatter/stackpanel";

  outputs = inputs@{ self, stackpanel, ... }:
    stackpanel.lib.mkFlake {
      inherit inputs self;
    };
}
```

The previous `devenvModules` and `lib.wrapDevenv` API surfaces were removed. Native replacements live under `stackpanel.languages.*`, `stackpanel.packages`, `stackpanel.devshell.*`, and process-compose-backed services.

Intentional remaining references to `devenv` are historical/archive notes, generated compatibility ignore patterns, or third-party comparison copy.
