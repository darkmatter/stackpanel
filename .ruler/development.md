# Development Guidelines

- To enter the devshell: `nix develop --impure`
- Run ALL commands in the nix shell otherwise you will be using the wrong binaries.
- After you finish a task, ALWAYS try entering the devshell either by using the `devshell` script or `nix develop --impure`
- Do NOT assume `devenv shell` will be used. 