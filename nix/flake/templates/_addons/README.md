# Stackpanel init addons

Addons are optional, prompt-gated extras that `stackpanel init` offers when
scaffolding a project. They let you ask a yes/no or multiple-choice question
(e.g. "Install VS Code integration?") and, based on the answer, drop extra files
and/or patch the project config — all declared here in Nix.

## How it works

1. Every directory `templates/_addons/<id>/` is one addon, declared by its
   `addon.nix`. The flake exposes them as `lib.initAddons`.
2. During `stackpanel init`, the CLI evaluates `lib.initAddons`, asks each
   `question`, then for every active answer:
   - copies the addon's `files` into the project (existing files are preserved
     unless `--force`),
   - patches the addon's `config` into `.stack/config.nix`, and
   - registers the addon's `jsonOps` as `stackpanel.files.entries` json-ops
     entries so the generator merges them into existing JSON files.
3. The choices are recorded in the project's `.stack/addons.json` so that
   re-running `init` doesn't re-ask. New addons added to the flake later are
   offered on the next run; `--force` re-asks everything.

Directories whose name starts with `_` (like `_template`) are scaffolding and
are never offered as real addons.

## Anatomy of an addon

```
templates/_addons/<id>/
  addon.nix     # the question + optional config patch + metadata
  files/        # optional static files copied in when selected (recursive)
```

`addon.nix` shape:

```nix
{
  id = "<id>";                       # must match the directory name
  question = {
    type = "bool";                   # "bool" | "select" | "multiselect"
    label = "Enable X?";
    description = "What this does.";
    default = true;                  # bool | choice value | list of values
    order = 10;                      # lower is prompted first (optional)
    # choices = [ { value; label; config ? {}; files ? {}; } ... ];  # select/*
  };
  config = { ide.vscode.enable = true; };  # patched into .stack/config.nix
  # files = { "path" = "contents"; };       # inline files (in addition to files/)
  # jsonOps = {                              # surgical JSON merges (see below)
  #   "package.json" = [
  #     { op = "merge"; path = [ "scripts" ]; value = { check = "biome check ."; }; }
  #   ];
  # };
}
```

`config` values must be JSON-serialisable (strings, bools, numbers, lists,
attrsets). Nested attrsets become dot-paths, e.g. `ide.vscode.enable` is applied
as `ide.vscode.enable = true;`.

### JSON ops (merging into existing JSON files)

Use `jsonOps` to surgically edit JSON files (e.g. add a script to `package.json`)
instead of overwriting them. Keyed by target file, each op is one of `set`,
`merge`, `remove`, `append`, or `appendUnique`:

```nix
jsonOps = {
  "package.json" = [
    { op = "merge"; path = [ "scripts" ]; value = { check = "biome check ."; }; }
    { op = "appendUnique"; path = [ "workspaces" ]; value = "packages/*"; }
  ];
};
```

When the addon is active, each target becomes a `stackpanel.files.entries.<file>`
entry of `type = "json-ops"` in `.stack/config.nix`, and the file generator
applies the merge on the next devshell entry (creating/backing up the file as
needed). This reuses the same json-ops engine that powers `stackpanel nixify
package.json`.

## Examples in this directory

- **`vscode`** — config-driven. Answering yes patches `ide.vscode.enable = true`
  so the file generator emits a `.vscode/` workspace. No static files.
- **`editorconfig`** — file-drop. Answering yes copies `files/.editorconfig`
  into the project root. No config patch.
- **`_template`** — copy this to start a new addon. Documents all three question
  types and both capabilities. Never offered to users.

## Adding a new addon

```bash
cp -r nix/flake/templates/_addons/_template nix/flake/templates/_addons/<id>
# edit <id>/addon.nix (set id, question, config), put any files under <id>/files/
```

Verify it evaluates:

```bash
nix eval .#lib.initAddons --json | jq 'keys'
```

## Non-interactive / CI

`stackpanel init` resolves answers without prompting when run with
`--non-interactive` (or no TTY):

- `--with <id>` — answer the addon's question affirmatively (bool → true).
- `--without <id>` — decline it.
- `--addon <id>=<value>` — set an explicit answer: `true`/`false` for bool, a
  choice `value` for select, or a comma-separated list for multiselect.

Anything not specified falls back to the question's `default`.
