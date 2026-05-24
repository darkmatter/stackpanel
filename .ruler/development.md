# Development Guidelines

- To enter the devshell: `nix develop` or `direnv allow`.
- Avoid `--impure` by default. Do not add features that require impure Nix evaluation.
- When you find an existing source of impurity, call it out explicitly with the file/command and why it is impure.
- Run ALL commands in the nix shell otherwise you will be using the wrong binaries.
- After you finish a task, ALWAYS try entering the devshell either by using the `devshell` script or `nix develop`.
- Do NOT assume `devenv shell` will be used.
