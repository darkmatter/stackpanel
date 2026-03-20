# Nix Templating: Avoid Large Inline Strings

## Rule

Do NOT embed large multi-line strings (shell scripts, TypeScript, JSON, YAML, config files, etc.) directly inside Nix expressions. Instead, use the **stack files and scripts systems** which support reading content from real files on disk.

Large inline strings in Nix:
- Lose syntax highlighting and IDE support (linting, type-checking, formatting)
- Are painful to read, edit, and diff
- Make Nix modules unnecessarily long and hard to review
- Cannot be validated by external tooling (shellcheck, tsc, jq)

## What counts as "large"

Anything over ~5-10 lines of non-Nix content inlined in a Nix string should be extracted to a file. One-liners and short snippets are fine inline.

## The Stack File and Script Systems

Stack provides two systems that support loading content from real files:

### 1. `stack.files.entries` -- Generate files into the repo

Use this to generate config files, scripts, workflows, etc. into the project tree on devshell entry.

**Option reference** (defined in `nix/stack/core/options/devshell.nix`):

| Field         | Type                                           | Description                                        |
|---------------|------------------------------------------------|----------------------------------------------------|
| `type`        | `"text"` / `"json"` / `"derivation"` / `"symlink"` | Content source type                               |
| `text`        | `string`                                       | Inline text (for short content only)               |
| `path`        | `path`                                         | Read content from a real file at eval time         |
| `jsonValue`   | `attrsOf anything`                             | Nix attrset serialized to JSON; deep-merges across modules |
| `drv`         | `package`                                      | Copy content from a Nix derivation                 |
| `target`      | `string`                                       | Symlink target (type="symlink")                    |
| `mode`        | `string`                                       | chmod mode, e.g. `"0755"`                          |
| `source`      | `string`                                       | Originating module name (shown in UI)              |
| `description` | `string`                                       | Human-readable purpose (shown in UI)               |

`text` and `path` are **mutually exclusive** for `type = "text"` entries.

### 2. `stack.scripts` -- Shell commands available in devshell

Use this for shell commands that should be on `$PATH` inside the devshell.

| Field           | Type              | Description                            |
|-----------------|-------------------|----------------------------------------|
| `exec`          | `string`          | Inline shell command (for short scripts)|
| `path`          | `path`            | Read script content from a real file   |
| `description`   | `string`          | Shown in help output                   |
| `runtimeInputs` | `listOf package`  | Packages added to script's PATH        |
| `env`           | `attrsOf str`     | Environment variables for the script   |
| `timeout`       | `int`             | Timeout in seconds (default: 300)      |

`exec` and `path` are **mutually exclusive**.

### 3. Template files with placeholder substitution

For generated files that need dynamic values injected into otherwise-static content, use a **template file** with `builtins.replaceStrings`:

- Name the file `*.tmpl.<ext>` (e.g., `infra.tmpl.ts`) so the real extension is preserved for IDE support
- Use `{{PLACEHOLDER}}` syntax for substitution points
- Read with `builtins.readFile`, substitute with `builtins.replaceStrings`

## Quick Tutorial

### Generating a config file from a real file on disk

Bad -- large inline YAML in Nix:

```nix
stack.files.entries.".github/workflows/ci.yml" = {
  type = "text";
  text = ''
    name: CI
    on:
      push:
        branches: [main]
      pull_request:
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: DeterminateSystems/nix-installer-action@main
          - run: nix flake check
          # ... 50 more lines ...
  '';
};
```

Good -- keep the YAML in a real file:

```nix
# The YAML lives at .stack/src/files/.github/workflows/ci.yml
# where it gets full YAML syntax highlighting, schema validation, etc.
stack.files.entries.".github/workflows/ci.yml" = {
  type = "text";
  path = ./.stack/src/files/.github/workflows/ci.yml;
  source = "ci";
  description = "CI workflow";
};
```

### Generating JSON with deep-merge support

Instead of building JSON as an inline Nix string, use `type = "json"` which gives you proper serialization and lets multiple modules contribute to the same file:

```nix
stack.files.entries."apps/web/package.json" = {
  type = "json";
  jsonValue = {
    name = "web";
    private = true;
    scripts.dev = "vite dev";
    scripts.build = "vite build";
    dependencies.react = "^19.0.0";
  };
  source = "web";
  description = "Web app package.json";
};
```

Another module can merge into the same file:

```nix
# In a different module -- values are deep-merged automatically
stack.files.entries."apps/web/package.json" = {
  type = "json";
  jsonValue = {
    scripts.test = "vitest";
    devDependencies.vitest = "^3.0.0";
  };
};
```

### Shell scripts via the scripts system

Bad -- large inline shell script:

```nix
stack.scripts.deploy = {
  exec = ''
    set -euo pipefail
    echo "Building..."
    bun run build
    echo "Running migrations..."
    bun run db:migrate
    echo "Deploying to Cloudflare..."
    wrangler deploy --env "$DEPLOY_ENV"
    echo "Purging CDN cache..."
    curl -X POST "https://api.cloudflare.com/..." \
      -H "Authorization: Bearer $CF_TOKEN"
    # ... 30 more lines ...
  '';
  description = "Deploy to production";
};
```

Good -- keep the script in a real file:

```nix
# The script lives at .stack/src/scripts/deploy.sh
# where it gets shellcheck, syntax highlighting, etc.
stack.scripts.deploy = {
  path = ./.stack/src/scripts/deploy.sh;
  description = "Deploy to production";
  runtimeInputs = [ pkgs.wrangler pkgs.curl ];
};
```

### Template files with placeholders

For files that are mostly static but need a few dynamic values:

```
# File: nix/my-module/templates/config.tmpl.ts
export const config = {
  projectName: "{{PROJECT_NAME}}",
  apiPort: {{API_PORT}},
  features: {{FEATURES_JSON}},
} as const;
```

```nix
# In the Nix module:
let
  template = builtins.readFile ./templates/config.tmpl.ts;
  rendered = builtins.replaceStrings
    [ "{{PROJECT_NAME}}" "{{API_PORT}}" "{{FEATURES_JSON}}" ]
    [ sp.name (toString sp.apps.api.port) (builtins.toJSON cfg.features) ]
    template;
in {
  stack.files.entries."src/generated/config.ts" = {
    type = "text";
    text = rendered;
    source = "my-module";
    description = "Generated project config";
  };
}
```

### Using derivations for complex generation

When you need `pkgs` utilities (e.g., `writeText`, `runCommand`) to build file content:

```nix
stack.files.entries."scripts/setup.sh" = {
  type = "derivation";
  drv = pkgs.writeScript "setup" (builtins.readFile ./templates/setup.sh);
  mode = "0755";
  source = "setup";
  description = "Project setup script";
};
```

## File organization convention

Keep source files for templates and scripts under `.stack/src/`:

```
.stack/
  src/
    files/           # Static files loaded via path = ...
    scripts/         # Shell scripts loaded via path = ...
    templates/       # Template files (*.tmpl.*)
```

Or colocate them with the module that uses them:

```
nix/stack/modules/my-module/
  module.nix
  templates/
    config.tmpl.ts
    setup.sh
```
