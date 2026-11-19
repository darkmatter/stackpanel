# 0009 — Module distribution is flake-native; Studio extensions use declared capabilities

- **Status**: Accepted
- **Date**: 2026-11-17

## Context

A module needs to work the same way whether it ships with Stackpanel, lives in the project, or comes from a registry. Requiring Stackpanel's source tree, a generated protocol for each runtime, or a custom agent route for each integration makes out-of-tree modules second-class. A mutable catalog or machine-local configuration must not become an input to pure Nix evaluation.

## Decision

- `flake.nix` selects external modules and `flake.lock` pins them. A versioned JSON catalog is a discovery mechanism, never an evaluation input. A linked working copy is an explicit local override, not a change to the project's lock.
- Modules receive `lib.stackpanel`. The common schema distinguishes an available module from enabled behavior, an app runtime from a framework, and a build provider from a deployment backend. Output ownership is declared, not inferred from command names.
- One module registry (`stackpanel.modules`) and one panel registry (`stackpanel.panels`) describe the project. A panel belongs to a module by ID. Enablement and settings are AST edits to the evaluated project configuration, not agent-side state.
- The CLI and Studio use the same project operations. Stable wire fields are typed in the versioned Connect service. Values whose structure is defined by the *installed module*, such as action arguments and settings, carry JSON data checked against the declared runtime schema. Adding a module does not regenerate Stackpanel's protocol.
- Prefer declarative panels. Where a bundle is necessary, serve the evaluated project artifact and render it in a script-only sandbox. The host grants only the panel's declared, module-scoped config/action/service operations. Neither production bundles nor HMR frames receive an agent credential. A proxy target must be a loopback service opted in by its owning module.

## Consequences

An external runtime can add per-app build, deploy, and UI behavior without a core release. The consumer can audit and reproduce its source selection independently of the catalog. Schema evaluation alone does not materialize files, run actions, or authorize a panel to execute an arbitrary command. Reviewed flake inputs still run trusted project code; iframe isolation does not sandbox Nix modules or the processes they install.

## Alternatives considered

A mutable marketplace resolver in Nix would make builds depend on catalog availability and account state. Dynamic host-side React imports would grant third-party JavaScript the Studio page's origin and agent access. A REST handler per module would recreate the project-selection and authorization policies that the shared service replaces.

## References

- [0004 — Agent API on Connect](./0004-agent-api-on-connect.md)
- [0005 — Per-request project selection](./0005-per-request-project-selection.md)
- [0006 — Single Stackpanel directory](./0006-single-stack-directory.md)
- [0007 — Deployment backend options](./0007-deploy-backends-are-options.md)
- [Module author guide](../../apps/docs/content/docs/extensions/writing-extensions.mdx)
