# 0011 — Nix widget options come from the Studio catalog

- **Status**: Accepted
- **Date**: 2026-11-18

## Context

The Studio catalog defines valid component inputs. Asking a module author to write a raw json-render document repeats layout boilerplate, and nixd cannot discover properties inside a free-form `props` object. A Nix helper alone improves construction but does not reliably give the language server an option path for its argument.

## Decision

Authors declare `ui.widgets.<id>.<kind>` in `mkModule` or `panels.<id>.spec.widgets` for another slot. Every kind has a corresponding SDK constructor for use in Nix composition. The [Studio author schema](../../apps/web/src/components/studio/panels/shared/spec/author-schema.ts) owns widget properties, descriptions, allowed bindings and child slots. Its generated, checked-in [catalog projection](../../nix/stackpanel/lib/ui/widget-catalog.v1.json) supplies Nix with those declarations. The same Nix declarations expose `lib.moduleAuthorOptions` to nixd and validate the typed layout before lowering it to the ordinary json-render document. No JavaScript runs during Nix evaluation.

The [module template](../../nix/flake/templates/module) keeps the editor’s SDK and nixd pin in a separate development flake. Open the module root to use its VS Code or Zed settings. An extension’s runtime flake still takes the SDK from its consumer; a project can therefore use a different version from the one the author’s editor describes.

## Consequences

- An editor can complete and document widget fields in the declaration. Dynamic action IDs, computed Nix expressions and cross-widget runtime behavior are not a static type system.
- The Nix compiler can report structural errors at the widget path. It preserves explicit child order, infers only a unique root, and cannot grant more capabilities than a raw document. Studio validation and the agent’s approval checks in [ADR 0010](./0010-module-ui-component-catalog.md) remain authoritative.
- Changes to the author schema require regeneration with `vp run widgets:generate` in `apps/web`. The package’s test suite checks the projection for drift. Authors do not need this generation step.

## Alternatives considered

Maintaining Nix widget definitions by hand would let editor guidance diverge from Studio. A list of arbitrary widget function calls would be terser, but would sacrifice the field completion and hover that motivated the author interface. A separate editor extension would duplicate work already supported by nixd’s option providers.

## References

- [Nix workflow for module authors](../../apps/docs/content/docs/extensions/writing-extensions.mdx#author-a-panel-in-nix)
- [nixd option-provider configuration](https://github.com/nix-community/nixd/blob/2.7.0/nixd/docs/configuration.md)
