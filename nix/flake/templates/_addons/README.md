# Stackpanel addons (adoption offers)

An addon says **"you could turn X on"**. It is metadata, a question, a
revision, and a config mutation - roughly six lines. It is the only new
authoring surface next to modules, and it deliberately cannot install anything:
installation is what a module is for.

`stack setup` offers every addon the user has not decided on yet. Accepting
writes the addon's `config` into `.stack/config.nix`; Nix re-evaluates; the
module's own `files.entries` materialize through ordinary reconciliation.
`stack doctor` lists pending offers but never applies them.

## Where addons come from

Two places, one list:

- **Flake-level** - one directory per addon under `templates/_addons/<id>/`,
  declared by `addon.nix`. Exposed as `lib.initAddons` so a fresh repo with no
  evaluable config can still be offered them, and injected into every
  stackpanel evaluation as `stackpanel.addons` so inside a project they sit
  next to module-contributed offers.
- **Module-level** - the `adoption` argument of `lib.stackpanel.mkModule`
  (see `nix/stackpanel/modules/playwright/default.nix`). It is emitted
  *outside* the module's `mkIf cfg.enable` guard on purpose: a suggestion to
  adopt X must be visible to people who have not enabled X.

Directories whose name starts with `_` (like `_template`) are scaffolding and
are never offered.

## Which surface do I want?

| You want to... | Use | Why |
|---|---|---|
| Define what it means to have X (files, scripts, packages, checks) | a **module** (`files.entries`, guarded by `mkIf cfg.enable`) | Installation belongs in one place; reconciliation delivers every later change to every adopter. |
| Suggest turning X on | an **addon** (`adoption = { ... }` or `_addons/<id>/addon.nix`) | Six lines of metadata plus a config mutation. Never files. |
| Observe something and report it | a **doctor check** (`stackpanel.doctor.<module>.<name>`) | Build scope for CI, runtime scope (with an optional `fixCommand`) for machine state, repo scope for the checkout. Never installs. |
| Fix repo state | nothing new - edit the module's `files.entries` | Repo state is fixed by reconciliation (`stack setup`), not by checks or addons. |

## Anatomy of an addon

```
templates/_addons/<id>/
  addon.nix     # the question + config mutation + revision
```

`addon.nix` shape:

```nix
{
  id = "<id>";                       # must match the directory name
  revision = 1;                      # bump to re-offer to users who declined
  question = {
    type = "bool";                   # "bool" | "select" | "multiselect"
    label = "Enable X?";
    description = "What accepting does.";
    default = true;                  # bool | choice value | list of values
    order = 10;                      # lower is offered first (optional)
    # choices = [ { value; label; config ? {}; } ... ];  # select / multiselect
  };
  config = { ide.vscode.enable = true; };  # written into .stack/config.nix
}
```

`config` values must be JSON-serialisable (strings, bools, numbers, lists,
attrsets). Nested attrsets become dot-paths relative to the stackpanel config
root, e.g. `ide.vscode.enable` is applied as `ide.vscode.enable = true;`.

There is no `files` payload any more. Anything worth shipping is a module -
which also gains drift-checking and revert that a raw file drop never had.
The former `editorconfig` file-drop addon is now
`nix/stackpanel/modules/editorconfig`, six lines of `adoption` included.

## Lifecycle and the ledger

Decisions are recorded in the project's `.stack/reconcile.json`:

```json
{ "version": 1, "seen": { "playwright": { "revision": 1, "answer": false, "at": "2026-09-04T01:22:11Z" } } }
```

It records **what the user has been shown**, not what they want. Declining
writes one ledger entry and nothing else - in particular no `enable = false`,
because "not now" is not "never". An addon is offered again only when its
author bumps `revision`; fixing a typo in the label does not re-nag.
`stack setup --reconsider` re-offers everything that was declined.

Adoption is one-way: the reconciler cannot undo it, because config is the input
that decides what the reconciler does. Undoing adoption is a user edit of
`.stack/config.nix`.

`.stack/addons.json` from older releases is migrated automatically on the
first `stack setup`.

## Examples in this directory

- **`vscode`** / **`zed`** - config-driven. Answering yes patches
  `ide.<editor>.enable = true`, so the file generator emits the workspace.
- **`_template`** - copy this to start a new addon. Documents all three
  question types. Never offered to users.

## Adding a new addon

```bash
cp -r nix/flake/templates/_addons/_template nix/flake/templates/_addons/<id>
# edit <id>/addon.nix (set id, question, config)
```

Verify it evaluates:

```bash
nix eval .#lib.initAddons --json | jq 'keys'
```

## Non-interactive / CI

`stack setup` resolves answers without prompting when run with `--yes`
(or `--non-interactive`, or no TTY):

- `--with <id>` - answer affirmatively (bool -> true; select -> its default;
  multiselect -> every choice).
- `--without <id>` - decline.
- `--addon <id>=<value>` - explicit: `true`/`false` for bool, a choice `value`
  for select, or a comma-separated list for multiselect.

Anything not specified falls back to the question's `default`.
