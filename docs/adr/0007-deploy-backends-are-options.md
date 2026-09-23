# 0007 — Deploy backends are options; collisions are guarded and internals shared

- **Status**: Accepted
- **Date**: 2026-09-23

## Context

Stackpanel supports several ways to deploy: Alchemy (Cloudflare, AWS), SST,
Colmena/NixOS, containers (Fly and others), and per-app Alchemy scripts.
The September 2026 review asked whether these should collapse into one
deploy path. They should not: stackpanel's purpose is to give projects a
choice of backend.

The review did find problems that come from how the options are built, not
from having them:

- **Broken options.** The Nix-generated Alchemy infra modules import 25
  paths from `@stackpanel/infra` that do not exist; local deploy wrappers
  (`just deploy`, `scripts/deploy/*`) run a file deleted months ago; the
  CI NixOS deploy targets a flake whose `colmenaHive` is empty.
- **Copy-pasted internals.** The same AMI lookup, EC2 provisioning, and
  container field declarations exist in several backends and have drifted.
- **Collisions.** SST and `aws-secrets` both create
  `${projectName}-secrets-role` and the KMS alias `${projectName}-secrets`;
  enabling both (as this repository does) gives two tools ownership of the
  same AWS resources.
- **Ambiguous entry points.** "deploy" means four different things across
  the root `package.json`, the Justfile, turbo, and per-app scripts.

## Decision

Deploy backends remain independent, user-selectable options. Each option
must meet these rules:

1. **It works or it is removed.** A backend that cannot run end to end is
   fixed or deleted; it is not left discoverable.
2. **Shared mechanics live in one place.** Logic needed by more than one
   backend (AMI lookup, instance provisioning, container schema) is
   implemented once and called by each backend.
3. **Options that would own the same resources cannot be enabled
   together.** A Nix assertion fails evaluation with a message naming both
   options and the contested resource.
4. **Entry points are named per backend** (for example `deploy:alchemy`,
   `deploy:colmena`). A bare `deploy` either dispatches to the configured
   backend or does not exist.
5. **Two definitions may not claim one external name** (a DNS record, a
   hostname, a cloud resource name). Stackpanel's own services follow the
   same rule: `api.stackpanel.com` gets one owner.

## Consequences

**Pros**

- Users keep the choice of backend, which is the product's point.
- Future reviews stop proposing "one deploy path"; the rules above give a
  concrete bar instead.
- Collisions fail at evaluation time instead of in a cloud account.

**Cons**

- Supporting several backends is permanent maintenance cost; shared
  internals and the "works or removed" rule keep it bounded.

**Follow-ups** (tracked under stackpanel-thq.13)

- Fix or remove the Nix-generated Alchemy modules, the stale deploy
  wrappers, and the CI NixOS flake reference; add the SST/aws-secrets
  assertion; extract the shared AMI lookup and EC2 provisioning; rename
  entry points per backend.

## Alternatives considered

- **Consolidate on one deploy path (per-app Alchemy).** Simpler to
  maintain, but contradicts stackpanel's purpose of supporting the backend
  a project already uses.
- **Keep options as they are.** Leaves broken backends discoverable and
  resource collisions possible.

## References

- stackpanel-thq.13, stackpanel-rz0
- `nix/stackpanel/integrations/{infra,sst,deployment,containers}/`,
  `Justfile`, `scripts/deploy/`, `.github/workflows/deploy-*.y*ml`
