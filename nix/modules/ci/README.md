# ci/

CI/CD workflow generation for GitHub Actions.

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Module entrypoint |
| `github-actions.nix` | Workflow generation |

## Options

```nix
stackpanel.ci.github = {
  enable = true;

  # High-level: common CI pattern
  checks = {
    enable = true;
    branches = [ "main" "develop" ];
    commands = [ "nix flake check" "nix build" ];
  };

  # Escape hatch: raw workflow definitions
  workflows = {
    deploy = {
      name = "Deploy";
      on.push.branches = [ "main" ];
      jobs.deploy = { /* ... */ };
    };
  };
};
```

## Generated Files

- `.github/workflows/ci.yml` - from `checks` options
- `.github/workflows/*.yml` - from `workflows` attrset

## TODO

- [ ] Add `deploy` high-level option (CD)
- [ ] Add `release` workflow (semantic release, changelogs)
- [ ] Support GitLab CI
- [ ] Support other CI systems (CircleCI, etc.)
- [ ] Add matrix builds option
- [ ] Add caching configuration
