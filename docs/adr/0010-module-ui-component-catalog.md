# 0010 — Module UI uses a shared component catalog

- **Status**: Accepted
- **Date**: 2026-11-18

## Context

Modules already declare settings, outputs and executable actions. Asking an author to implement those controls again in a web application makes similar modules behave differently. Loading that application's JavaScript into Studio would also give it the privileges of the Studio page.

## Decision

Studio provides the default module UI. A contributor who wants a different layout supplies a [json-render spec](https://json-render.dev/docs/specs), not a renderer. Studio owns the component registry, validates the tree and prop values, and exposes only intentionally public data and panel-local selection. An unrecognized document cannot fall back to executable UI.

The public extension SDK exports native Web Components for metrics, tabular data, app selection, status, and actions. The json-render registry and standalone HTML panels use the same display and interaction controls. A module never registers JavaScript on the Studio page. Standalone JavaScript remains an explicit, separately approved iframe under [ADR 0009](./0009-modules-are-flake-inputs.md).

A view is not an authorization. Configured inventory needs no remote query. A live view names an evaluated, module-owned action; Studio binds a run to the project, panel and original agent grant. Reads do not start on mount. An operator can load once or opt into updates when the selected app changes. Approval ends with the mounted view or a changed authority. Commands requiring confirmation do not qualify for this path.

An iframe cannot choose a network URL through the SDK. For a service request it names a module-owned service and relative path. Studio reviews the validated destination and method before dispatch; the agent independently enforces the grant, local service identity and proxy restrictions. The operator can refuse a request, stop the frame, or disable module-supplied UI code on the agent.

## Consequences

- Standard panels follow Studio's accessibility and theme conventions without bundling a frontend or depending on React. Element names, properties and events are now a public SDK contract.
- The catalog intentionally does not expose every json-render expression, arbitrary HTML, or automatic writes. A custom interaction can use JavaScript in the sandbox at the cost of explicit trust and request review.
- Browser controls are not a machine firewall. A native action or local service may use the network under its process permissions. A trusted local development server controls its own response headers. Use OS-level isolation when all process egress must be mediated.

## Alternatives considered

A React-only extension kit would impose a framework and would not isolate third-party code. An iframe for every panel would require even a read-only metric to publish assets and acquire a document capability. Treating a module's `confirm` or response format as proof of read-only behavior would let the author grant itself authority.

## References

- [Module author guide](../../apps/docs/content/docs/extensions/writing-extensions.mdx)
- [json-render catalog and registry](https://json-render.dev/docs/registry)
- [Browser custom elements](https://developer.mozilla.org/en-US/docs/Web/API/Web_components/Using_custom_elements)
