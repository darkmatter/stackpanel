# Prelude quick start

This page is the demo target for Stackpanel’s default shell DX
([Prelude](https://github.com/darkmatter/prelude)). After `nix develop`, run
`docs` and open **Quick start**.

## 1. Enter the shell

```bash
nix develop
# or: direnv allow  (then cd into the project)
```

You should see **one** Prelude MOTD — project name, Getting Started commands,
feature chips, and live status lights (agent / services / health).

## 2. Reprint the welcome banner

```bash
motd
```

Use `motd --pure` to skip live preflight probes (useful in CI or when the agent
is down).

## 3. Browse the command catalogue

```bash
menu          # interactive picker (arrows / filter / enter)
x --list      # non-interactive list
x <key>       # dispatch a catalogue command
```

Commands come from Stackpanel modules via the `stackpanel.motd.commands` façade
(for example turbo tasks, network helpers, deploy scripts). First five get
Getting Started slots on the MOTD.

## 4. Read project docs in the TUI

```bash
docs
```

Prelude’s viewer loads Markdown from the project root:

- `README.md`
- `docs/quick-start.md` (this file)

Fumadocs `.mdx` pages on the website are separate; they are not auto-registered
here.

## 5. Wire a command into the MOTD (optional)

In `.stack/config.nix`:

```nix
{
  motd.commands = [
    {
      name = "dev";
      description = "Start all local services";
    }
  ];
}
```

Reload the shell (`direnv reload` or re-enter `nix develop`). The command
appears on the MOTD and under `menu` / `x`.

## 6. Disable the shell banner

```nix
{
  prelude.enable = false;
}
```

Skips Prelude packages (`motd` / `menu` / `docs`) and the shell-entry banner.
Status data remains available via `stackpanel motd --json` / `--minimal`.

## Cheat sheet

| Command | What it does |
| --------- | ---------------- |
| `motd` | Welcome banner |
| `menu` / `x` | Command catalogue |
| `docs` | Markdown docs TUI |
| `stackpanel motd --json` | Status JSON for Studio / preflight |

More detail: [Prelude module docs](https://stackpanel.com/docs/modules/prelude)
(or `apps/docs/content/docs/modules/prelude.mdx` in this repo).
